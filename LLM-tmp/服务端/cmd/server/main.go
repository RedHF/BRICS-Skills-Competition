// yanxia-server is the server-authoritative companion for the Godot demo.
//
// Run from this directory:
//
//	go run ./cmd/server
//
// The content and save paths can be overridden for deployment or tests:
//
//	go run ./cmd/server -addr :8090 -data ./data/save.json -content ./content/chapters.json
package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"yanxia-server/internal/content"
	"yanxia-server/internal/httpapi"
	"yanxia-server/internal/store"
)

func main() {
	address := flag.String("addr", ":8090", "HTTP listen address")
	contentPath := flag.String("content", "content/chapters.json", "path to data-driven chapter catalog")
	dataPath := flag.String("data", "data/save.json", "path to server-side save database")
	flag.Parse()

	resolvedContentPath := resolvePath(*contentPath, "content/chapters.json")
	catalog, err := content.Load(resolvedContentPath)
	if err != nil {
		log.Fatalf("load content (%s): %v", resolvedContentPath, err)
	}
	resolvedDataPath := resolveDataPath(*dataPath)
	database, err := store.Open(resolvedDataPath)
	if err != nil {
		log.Fatalf("open persistence (%s): %v", resolvedDataPath, err)
	}
	api, err := httpapi.New(catalog, database)
	if err != nil {
		log.Fatalf("create API: %v", err)
	}

	server := &http.Server{
		Addr:              *address,
		Handler:           api,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	log.Printf("《檐下千秋》 server listening on %s (content=%s, data=%s)", *address, filepath.Clean(resolvedContentPath), filepath.Clean(resolvedDataPath))
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		if os.IsNotExist(err) {
			log.Fatalf("listen: %v", err)
		}
		log.Fatalf("server stopped: %v", err)
	}
}

func resolvePath(requested, defaultRelative string) string {
	candidates := []string{requested}
	if requested == defaultRelative || requested == "" {
		candidates = append(candidates, filepath.Join("LLM-tmp", "服务端", defaultRelative), filepath.Join("..", defaultRelative))
	}
	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return requested
}

func resolveDataPath(requested string) string {
	if requested == "" {
		requested = filepath.Join("data", "save.json")
	}
	// When launched from the repository root, keep the demo save beside the
	// service.  When launched from the service directory, the relative path is
	// intentionally left untouched and Store.Open creates ./data as needed.
	if requested == filepath.Join("data", "save.json") {
		if _, err := os.Stat(filepath.Join("LLM-tmp", "服务端", "content", "chapters.json")); err == nil {
			return filepath.Join("LLM-tmp", "服务端", "data", "save.json")
		}
	}
	return requested
}
