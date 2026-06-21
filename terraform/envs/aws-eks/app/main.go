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
)

var (
	version   = getEnv("VERSION", "v4")
	startTime = time.Now()
	region    = getEnv("AWS_REGION", "us-east-1")
)

// model shortcuts → full Bedrock model ID
var modelAliases = map[string]string{
	"nova":     "amazon.nova-lite-v1:0",
	"llama":    "meta.llama3-8b-instruct-v1:0",
	"deepseek": "deepseek.r1-v1:0",
	"mistral":  "mistral.mistral-7b-instruct-v0:2",
}

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
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	mux.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"version":"%s","go_version":"%s"}`, version, runtime.Version())
	})

	// IRSA demo: S3 ListBuckets
	mux.HandleFunc("/aws", func(w http.ResponseWriter, r *http.Request) {
		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		client := s3.NewFromConfig(cfg)
		result, err := client.ListBuckets(r.Context(), &s3.ListBucketsInput{})
		if err != nil {
			http.Error(w, fmt.Sprintf("s3:ListBuckets failed: %v", err), http.StatusForbidden)
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
	})

	// Bedrock Converse API — supports nova / llama / deepseek / mistral
	// Usage: GET /chat?q=<question>&model=<alias>
	// Requires X-API-Key header matching CHAT_API_KEY env var (prevents public LLM proxy abuse)
	chatAPIKey := getEnv("CHAT_API_KEY", "")
	mux.HandleFunc("/chat", func(w http.ResponseWriter, r *http.Request) {
		if chatAPIKey != "" && r.Header.Get("X-API-Key") != chatAPIKey {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		query := r.URL.Query().Get("q")
		if query == "" {
			http.Error(w, `{"error":"missing ?q=<question>"}`, http.StatusBadRequest)
			return
		}

		modelAlias := r.URL.Query().Get("model")
		if modelAlias == "" {
			modelAlias = "nova"
		}
		modelID, ok := modelAliases[modelAlias]
		if !ok {
			http.Error(w, `{"error":"unknown model, use: nova, llama, deepseek, mistral"}`, http.StatusBadRequest)
			return
		}

		cfg, err := loadAWSConfig(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
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
	})

	// list supported model aliases
	mux.HandleFunc("/models", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(modelAliases)
	})

	port := getEnv("PORT", "8080")
	fmt.Printf("Listening on :%s (version=%s)\n", port, version)
	http.ListenAndServe(":"+port, mux)
}
