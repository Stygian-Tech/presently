package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"time"

	"presently/oauth-worker/metadata"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           newHandler(metadata.ConfigFromEnvironment()),
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

func newHandler(config metadata.Config) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Cache-Control", "public, max-age=300, s-maxage=300")
		response.Header().Set("Content-Type", "text/html; charset=utf-8")
		response.WriteHeader(http.StatusOK)
		_, _ = response.Write([]byte(`<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Presently OAuth</title>
<body>
<main>
<h1>Presently</h1>
<p>This service publishes the OAuth client metadata used by the Presently mobile apps.</p>
<p><a href="/oauth/client-metadata.json">View OAuth client metadata</a></p>
</main>
</body>
</html>`))
	})

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

	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		mux.ServeHTTP(response, request)
	})
}
