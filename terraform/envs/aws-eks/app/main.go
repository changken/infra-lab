package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
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
	version   = getEnv("VERSION", "v6")
	startTime = time.Now()
	region    = getEnv("AWS_REGION", "us-east-1")
)

// model shortcuts → Bedrock cross-region inference profile ID
// on-demand throughput requires "us." prefix inference profiles
var modelAliases = map[string]string{
	"nova":     "us.amazon.nova-lite-v1:0",
	"llama":    "us.meta.llama3-1-8b-instruct-v1:0",
	"deepseek": "us.deepseek.r1-v1:0",
	"llama4":   "us.meta.llama4-scout-17b-instruct-v1:0",
	"mistral":  "mistral.mistral-large-2402-v1:0",
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

	// Bedrock Converse API — supports nova / llama / deepseek / llama4
	// Usage: GET /chat?q=<question>&model=<alias>
	// Requires X-API-Key header matching CHAT_API_KEY env var (prevents public LLM proxy abuse)
	chatAPIKey := getEnv("CHAT_API_KEY", "")
	mux.HandleFunc("/chat", func(w http.ResponseWriter, r *http.Request) {
		if chatAPIKey != "" && r.Header.Get("X-API-Key") != chatAPIKey {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			httpRequestsTotal.WithLabelValues("/chat", "401").Inc()
			return
		}
		query := r.URL.Query().Get("q")
		if query == "" {
			http.Error(w, `{"error":"missing ?q=<question>"}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/chat", "400").Inc()
			return
		}

		modelAlias := r.URL.Query().Get("model")
		if modelAlias == "" {
			modelAlias = "nova"
		}
		modelID, ok := modelAliases[modelAlias]
		if !ok {
			http.Error(w, `{"error":"unknown model, use: nova, llama, deepseek, llama4"}`, http.StatusBadRequest)
			httpRequestsTotal.WithLabelValues("/chat", "400").Inc()
			return
		}

		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			bedrockRequestsTotal.WithLabelValues(modelAlias, "error").Inc()
			return
		}

		client := brt.NewFromConfig(cfg)
		resp, err := client.Converse(r.Context(), &brt.ConverseInput{
			ModelId: aws.String(modelID),
			Messages: []brtypes.Message{{
				Role: brtypes.ConversationRoleUser,
				Content: []brtypes.ContentBlock{
					&brtypes.ContentBlockMemberText{Value: query},
				},
			}},
		})
		if err != nil {
			http.Error(w, fmt.Sprintf("bedrock error: %v", err), http.StatusInternalServerError)
			bedrockRequestsTotal.WithLabelValues(modelAlias, "error").Inc()
			return
		}

		var reply string
		if msg, ok := resp.Output.(*brtypes.ConverseOutputMemberMessage); ok {
			for _, block := range msg.Value.Content {
				if text, ok := block.(*brtypes.ContentBlockMemberText); ok {
					reply = text.Value
					break
				}
			}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"model": modelID,
			"query": query,
			"reply": reply,
			"via":   "IRSA → bedrock:Converse",
		})
		bedrockRequestsTotal.WithLabelValues(modelAlias, "ok").Inc()
		httpRequestsTotal.WithLabelValues("/chat", "200").Inc()
	})

	// list supported model aliases
	mux.HandleFunc("/models", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(modelAliases)
		httpRequestsTotal.WithLabelValues("/models", "200").Inc()
	})

	// Prometheus metrics endpoint — scraped by kube-prometheus-stack ServiceMonitor
	mux.Handle("/metrics", promhttp.Handler())

	port := getEnv("PORT", "8080")
	fmt.Printf("Listening on :%s (version=%s)\n", port, version)
	http.ListenAndServe(":"+port, mux)
}
