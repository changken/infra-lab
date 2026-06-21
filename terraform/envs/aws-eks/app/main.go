package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

var (
	version   = getEnv("VERSION", "v2")
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

	port := getEnv("PORT", "8080")
	fmt.Printf("Listening on :%s\n", port)
	http.ListenAndServe(":"+port, mux)
}
