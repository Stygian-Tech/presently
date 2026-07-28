package main

import (
	"errors"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path"
	"strings"
	"time"

	"presently/oauth-worker/metadata"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	siteDirectory := os.Getenv("PRESENTLY_SITE_DIR")
	if siteDirectory == "" {
		siteDirectory = "../../apps/web/dist"
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           newHandler(metadata.ConfigFromEnvironment(), os.DirFS(siteDirectory)),
		ReadHeaderTimeout: 05 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("Presently OAuth metadata listening on :%s", port)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func newHandler(config metadata.Config, site fs.FS) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Cache-Control", "no-store")
		response.Header().Set("Content-Type", "application/json; charset=utf-8")
		response.WriteHeader(http.StatusOK)
		_, _ = response.Write([]byte(`{"status":"ok"}`))
	})

	mux.Handle(
		"GET /oauth/client-metadata.json",
		metadata.Handler(config),
	)
	mux.Handle("GET /", staticSiteHandler(site))

	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		mux.ServeHTTP(response, request)
	})
}

func staticSiteHandler(site fs.FS) http.Handler {
	files := http.FileServerFS(site)

	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		sitePath := strings.TrimPrefix(path.Clean("/"+request.URL.Path), "/")
		if info, err := fs.Stat(site, sitePath); err == nil && info.IsDir() {
			if _, err := fs.Stat(site, path.Join(sitePath, "index.html")); err != nil {
				http.NotFound(response, request)
				return
			}
		}

		if request.URL.Path == "/_astro" || strings.HasPrefix(request.URL.Path, "/_astro/") {
			response.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			response.Header().Set("Cache-Control", "public, max-age=300, s-maxage=300")
		}
		files.ServeHTTP(response, request)
	})
}
