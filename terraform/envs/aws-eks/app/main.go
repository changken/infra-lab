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
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

var (
	version   = getEnv("VERSION", "v3")
	startTime = time.Now()
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

	// IRSA demo: 透過 ServiceAccount 的 IAM Role 呼叫 S3，不需要 hardcoded credentials
	mux.HandleFunc("/aws", func(w http.ResponseWriter, r *http.Request) {
		ctx := context.Background()
		cfg, err := config.LoadDefaultConfig(ctx)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed to load AWS config: %v", err), http.StatusInternalServerError)
			return
		}

		client := s3.NewFromConfig(cfg)
		result, err := client.ListBuckets(ctx, &s3.ListBucketsInput{})
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
			"region":  cfg.Region,
			"buckets": buckets,
			"count":   len(buckets),
		})
	})

	port := getEnv("PORT", "8080")
	fmt.Printf("Listening on :%s\n", port)
	http.ListenAndServe(":"+port, mux)
}
