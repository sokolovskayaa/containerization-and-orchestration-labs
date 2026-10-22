package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	ctx, stop := signal.NotifyContext(
		context.Background(),
		os.Interrupt,
		syscall.SIGTERM,
	)
	defer stop()

	// PostgreSQL
	db, err := pgxpool.New(ctx, "")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Prometheus metrics
	requests := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "shop_http_requests_total",
			Help: "Total HTTP requests",
		},
		[]string{"code", "method"},
	)

	duration := prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "shop_http_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method"},
	)

	prometheus.MustRegister(requests, duration)

	// HTTP routes
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, r *http.Request) {
		checkCtx, cancel := context.WithTimeout(
			r.Context(),
			time.Second,
		)
		defer cancel()

		if err := db.Ping(checkCtx); err != nil {
			http.Error(
				w,
				"Database unavailable",
				http.StatusServiceUnavailable,
			)
			return
		}

		fmt.Fprintln(w, "ready")
	})

	mux.HandleFunc("POST /orders", func(w http.ResponseWriter, r *http.Request) {
		var id int64

		err := db.QueryRow(
			r.Context(),
			"INSERT INTO orders(status) VALUES('new') RETURNING id",
		).Scan(&id)

		if err != nil {
			log.Printf("Create order: %v", err)
			http.Error(
				w,
				"Database error",
				http.StatusInternalServerError,
			)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)

		fmt.Fprintf(w, "{\"id\":%d}\n", id)
	})

	mux.HandleFunc("GET /orders", func(w http.ResponseWriter, r *http.Request) {
		var pending, done int64

		err := db.QueryRow(r.Context(), `
			SELECT
				COUNT(*) FILTER (WHERE status = 'new'),
				COUNT(*) FILTER (WHERE status = 'done')
			FROM orders
		`).Scan(&pending, &done)

		if err != nil {
			log.Printf("List orders: %v", err)
			http.Error(
				w,
				"Database error",
				http.StatusInternalServerError,
			)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		fmt.Fprintf(
			w,
			"{\"new\":%d,\"done\":%d}\n",
			pending,
			done,
		)
	})

	// Instrument HTTP handlers
	handler := promhttp.InstrumentHandlerCounter(
		requests,
		promhttp.InstrumentHandlerDuration(
			duration,
			mux,
		),
	)

	// Main HTTP server
	server := &http.Server{
		Addr:              ":8080",
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Prometheus metrics server
	metricsServer := &http.Server{
		Addr:              ":9090",
		Handler:           promhttp.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Println("Metrics server listening on :9090")

		if err := metricsServer.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			log.Printf("Metrics server error: %v", err)
		}
	}()

	// Graceful shutdown
	go func() {
		<-ctx.Done()

		log.Println("Shutdown signal received")

		// Allow time for endpoint propagation.
		time.Sleep(2 * time.Second)

		shutdownCtx, cancel := context.WithTimeout(
			context.Background(),
			10*time.Second,
		)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("API shutdown error: %v", err)
		}

		if err := metricsServer.Shutdown(shutdownCtx); err != nil {
			log.Printf("Metrics shutdown error: %v", err)
		}

		log.Println("Servers stopped")
	}()

	log.Println("API server listening on :8080")

	if err := server.ListenAndServe(); err != nil &&
		!errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
