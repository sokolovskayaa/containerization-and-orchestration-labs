package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx, stop := signal.NotifyContext(
		context.Background(),
		os.Interrupt, syscall.SIGTERM,
	)
	defer stop()

	db, err := pgxpool.New(ctx, "")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	log.Println("Worker started")

	for {
		select {
		case <-ctx.Done():
			log.Println("Worker stopped")
			return

		case <-ticker.C:
			queryCtx, cancel := context.WithTimeout(
				ctx, 3*time.Second,
			)

			tag, err := db.Exec(queryCtx, `
                WITH next AS (
                    SELECT id FROM orders
                    WHERE status = 'new'
                    ORDER BY id
                    FOR UPDATE SKIP LOCKED
                    LIMIT 10
                )
                UPDATE orders AS o
                SET status = 'done'
                FROM next
                WHERE o.id = next.id
            `)

			cancel()

			if err != nil {
				log.Printf("Processing error: %v", err)
				continue
			}

			if tag.RowsAffected() > 0 {
				log.Printf("Processed: %d orders", tag.RowsAffected())
			}
		}
	}
}
