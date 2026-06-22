package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	brt "github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	brtypes "github.com/aws/aws-sdk-go-v2/service/bedrockruntime/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	version         = getEnv("VERSION", "v7")
	startTime       = time.Now()
	region          = getEnv("AWS_REGION", "us-east-1")
	knowledgeBucket = getEnv("KNOWLEDGE_BUCKET", "")
	knowledgePrefix = getEnv("KNOWLEDGE_PREFIX", "knowledge/")
)

// model shortcuts → Bedrock cross-region inference profile ID
var modelAliases = map[string]string{
	"nova":     "us.amazon.nova-lite-v1:0",
	"llama":    "us.meta.llama3-1-8b-instruct-v1:0",
	"deepseek": "us.deepseek.r1-v1:0",
	"llama4":   "us.meta.llama4-scout-17b-instruct-v1:0",
}

// Prometheus metrics
var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "custom_app_http_requests_total",
		Help: "Total HTTP requests by path and status",
	}, []string{"path", "status"})

	bedrockRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "custom_app_bedrock_requests_total",
		Help: "Total Bedrock Converse API calls by model and status",
	}, []string{"model", "status"})

	awsRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "custom_app_aws_requests_total",
		Help: "Total AWS API calls by service and status",
	}, []string{"service", "status"})

	ragContextChars = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "custom_app_rag_context_chars",
		Help:    "Characters of S3 context injected into RAG system prompt",
		Buckets: []float64{500, 1000, 2000, 4000, 8000, 16000},
	})
)

type Info struct {
	Hostname  string `json:"hostname"`
	NodeName  string `json:"node_name"`
	Namespace string `json:"namespace"`
	Version   string `json:"version"`
	Uptime    string `json:"uptime"`
	GoVersion string `json:"go_version"`
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func loadAWSConfig(ctx context.Context) (aws.Config, error) {
	return config.LoadDefaultConfig(ctx, config.WithRegion(region))
}

func resolveModel(alias string) (string, bool) {
	if alias == "" {
		alias = "nova"
	}
	id, ok := modelAliases[alias]
	return id, ok
}

func callBedrock(ctx context.Context, cfg aws.Config, modelID, systemPrompt, userQuery string) (string, error) {
	client := brt.NewFromConfig(cfg)

	input := &brt.ConverseInput{
		ModelId: aws.String(modelID),
		Messages: []brtypes.Message{{
			Role: brtypes.ConversationRoleUser,
			Content: []brtypes.ContentBlock{
				&brtypes.ContentBlockMemberText{Value: userQuery},
			},
		}},
	}
	if systemPrompt != "" {
		input.System = []brtypes.SystemContentBlock{
			&brtypes.SystemContentBlockMemberText{Value: systemPrompt},
		}
	}

	resp, err := client.Converse(ctx, input)
	if err != nil {
		return "", err
	}

	if msg, ok := resp.Output.(*brtypes.ConverseOutputMemberMessage); ok {
		for _, block := range msg.Value.Content {
			if text, ok := block.(*brtypes.ContentBlockMemberText); ok {
				return text.Value, nil
			}
		}
	}
	return "", nil
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		hostname, _ := os.Hostname()
		info := Info{
			Hostname:  hostname,
			NodeName:  os.Getenv("NODE_NAME"),
			Namespace: os.Getenv("NAMESPACE"),
			Version:   version,
			Uptime:    time.Since(startTime).Round(time.Second).String(),
			GoVersion: runtime.Version(),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info)
		httpRequestsTotal.WithLabelValues("/", "200").Inc()
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
		httpRequestsTotal.WithLabelValues("/health", "200").Inc()
	})

	mux.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"version":"%s","go_version":"%s"}`, version, runtime.Version())
		httpRequestsTotal.WithLabelValues("/version", "200").Inc()
	})

	// IRSA demo: S3 ListBuckets
	mux.HandleFunc("/aws", func(w http.ResponseWriter, r *http.Request) {
		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			awsRequestsTotal.WithLabelValues("s3", "error").Inc()
			return
		}
		client := s3.NewFromConfig(cfg)
		result, err := client.ListBuckets(r.Context(), &s3.ListBucketsInput{})
		if err != nil {
			http.Error(w, fmt.Sprintf("s3:ListBuckets failed: %v", err), http.StatusForbidden)
			awsRequestsTotal.WithLabelValues("s3", "error").Inc()
			return
		}
		buckets := make([]string, len(result.Buckets))
		for i, b := range result.Buckets {
			buckets[i] = aws.ToString(b.Name)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"note":    "called via IRSA — no hardcoded credentials",
			"region":  region,
			"buckets": buckets,
			"count":   len(buckets),
		})
		awsRequestsTotal.WithLabelValues("s3", "ok").Inc()
	})

	chatAPIKey := getEnv("CHAT_API_KEY", "")

	authCheck := func(w http.ResponseWriter, r *http.Request) bool {
		if chatAPIKey != "" && r.Header.Get("X-API-Key") != chatAPIKey {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return false
		}
		return true
	}

	// Bedrock Converse — single-turn chat
	mux.HandleFunc("/chat", func(w http.ResponseWriter, r *http.Request) {
		if !authCheck(w, r) {
			httpRequestsTotal.WithLabelValues("/chat", "401").Inc()
			return
		}
		query := r.URL.Query().Get("q")
		if query == "" {
			http.Error(w, `{"error":"missing ?q="}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/chat", "400").Inc()
			return
		}
		modelID, ok := resolveModel(r.URL.Query().Get("model"))
		if !ok {
			http.Error(w, `{"error":"unknown model, use: nova, llama, deepseek, llama4"}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/chat", "400").Inc()
			return
		}
		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		reply, err := callBedrock(r.Context(), cfg, modelID, "", query)
		if err != nil {
			http.Error(w, fmt.Sprintf("bedrock error: %v", err), http.StatusInternalServerError)
			bedrockRequestsTotal.WithLabelValues(r.URL.Query().Get("model"), "error").Inc()
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"model": modelID,
			"query": query,
			"reply": reply,
			"via":   "IRSA → bedrock:Converse",
		})
		bedrockRequestsTotal.WithLabelValues(r.URL.Query().Get("model"), "ok").Inc()
		httpRequestsTotal.WithLabelValues("/chat", "200").Inc()
	})

	// Poor Man's RAG — S3 knowledge base → Bedrock system prompt
	// 1. ListObjectsV2 on knowledge prefix
	// 2. GetObject for each .txt (max 12000 chars total)
	// 3. Inject as Bedrock system prompt
	// 4. Return answer + sources list
	mux.HandleFunc("/rag", func(w http.ResponseWriter, r *http.Request) {
		if !authCheck(w, r) {
			httpRequestsTotal.WithLabelValues("/rag", "401").Inc()
			return
		}
		if knowledgeBucket == "" {
			http.Error(w, `{"error":"KNOWLEDGE_BUCKET not configured"}`, http.StatusServiceUnavailable)
			return
		}
		query := r.URL.Query().Get("q")
		if query == "" {
			http.Error(w, `{"error":"missing ?q="}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/rag", "400").Inc()
			return
		}
		modelAlias := r.URL.Query().Get("model")
		modelID, ok := resolveModel(modelAlias)
		if !ok {
			http.Error(w, `{"error":"unknown model"}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/rag", "400").Inc()
			return
		}
		if modelAlias == "" {
			modelAlias = "nova"
		}

		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		s3Client := s3.NewFromConfig(cfg)

		// Step 1: list knowledge files
		listResult, err := s3Client.ListObjectsV2(r.Context(), &s3.ListObjectsV2Input{
			Bucket: aws.String(knowledgeBucket),
			Prefix: aws.String(knowledgePrefix),
		})
		if err != nil {
			http.Error(w, fmt.Sprintf("s3:ListObjectsV2 failed: %v", err), http.StatusInternalServerError)
			awsRequestsTotal.WithLabelValues("s3", "error").Inc()
			return
		}

		// Step 2: fetch content of each .txt file
		const maxContextChars = 12000
		var contextParts []string
		var sources []string
		totalChars := 0

		for _, obj := range listResult.Contents {
			key := aws.ToString(obj.Key)
			if !strings.HasSuffix(key, ".txt") {
				continue
			}
			if totalChars >= maxContextChars {
				break
			}
			getResult, err := s3Client.GetObject(r.Context(), &s3.GetObjectInput{
				Bucket: aws.String(knowledgeBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				continue
			}
			body, err := io.ReadAll(io.LimitReader(getResult.Body, int64(maxContextChars-totalChars)))
			getResult.Body.Close()
			if err != nil || len(body) == 0 {
				continue
			}
			contextParts = append(contextParts, string(body))
			sources = append(sources, key)
			totalChars += len(body)
		}
		awsRequestsTotal.WithLabelValues("s3", "ok").Inc()

		// Step 3: build system prompt with injected context
		systemPrompt := "You are a helpful assistant for the Infra Lab project. " +
			"Answer questions based on the following context. " +
			"If the answer is not in the context, say so clearly.\n\n" +
			"Context:\n---\n" + strings.Join(contextParts, "\n---\n")

		ragContextChars.Observe(float64(totalChars))

		// Step 4: call Bedrock with context-aware system prompt
		reply, err := callBedrock(r.Context(), cfg, modelID, systemPrompt, query)
		if err != nil {
			http.Error(w, fmt.Sprintf("bedrock error: %v", err), http.StatusInternalServerError)
			bedrockRequestsTotal.WithLabelValues(modelAlias, "error").Inc()
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"model":         modelID,
			"query":         query,
			"reply":         reply,
			"sources":       sources,
			"context_chars": totalChars,
			"via":           "IRSA → s3:GetObject → bedrock:Converse",
		})
		bedrockRequestsTotal.WithLabelValues(modelAlias, "ok").Inc()
		httpRequestsTotal.WithLabelValues("/rag", "200").Inc()
	})

	mux.HandleFunc("/models", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(modelAliases)
		httpRequestsTotal.WithLabelValues("/models", "200").Inc()
	})

	mux.Handle("/metrics", promhttp.Handler())

	port := getEnv("PORT", "8080")
	fmt.Printf("Listening on :%s (version=%s, knowledge_bucket=%s)\n", port, version, knowledgeBucket)
	http.ListenAndServe(":"+port, mux)
}
