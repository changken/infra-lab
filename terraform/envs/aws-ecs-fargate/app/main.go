package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

type Response struct {
	Status    string         `json:"status"`
	Version   string         `json:"version"`
	Hostname  string         `json:"hostname"`
	Region    string         `json:"region"`
	Timestamp string         `json:"timestamp"`
	ECS       *ECSTaskInfo   `json:"ecs,omitempty"`
}

type ECSTaskInfo struct {
	Cluster  string `json:"cluster"`
	Family   string `json:"family"`
	Revision string `json:"revision"`
	TaskARN  string `json:"task_arn"`
}

func getECSTaskInfo() *ECSTaskInfo {
	metaURL := os.Getenv("ECS_CONTAINER_METADATA_URI_V4")
	if metaURL == "" {
		return nil
	}
	resp, err := http.Get(metaURL + "/task")
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var meta map[string]any
	if err := json.Unmarshal(body, &meta); err != nil {
		return nil
	}
	info := &ECSTaskInfo{}
	if v, ok := meta["Cluster"].(string); ok {
		info.Cluster = v
	}
	if v, ok := meta["Family"].(string); ok {
		info.Family = v
	}
	if v, ok := meta["Revision"].(string); ok {
		info.Revision = v
	}
	if v, ok := meta["TaskARN"].(string); ok {
		info.TaskARN = v
	}
	return info
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	resp := Response{
		Status:    "ok",
		Version:   os.Getenv("APP_VERSION"),
		Hostname:  hostname,
		Region:    os.Getenv("AWS_REGION"),
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		ECS:       getECSTaskInfo(),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "ok")
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	log.Printf("ECS Fargate demo app listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
