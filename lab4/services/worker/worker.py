"""shop worker: забирает новые заказы из postgres и помечает их обработанными."""
import logging
import os
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest
from psycopg import errors as pgerrors

DATABASE_URL = os.environ.get("DATABASE_URL", "")
INTERVAL = float(os.environ.get("WORKER_INTERVAL", "5"))
BATCH = int(os.environ.get("WORKER_BATCH", "10"))
PORT = int(os.environ.get("PORT", "8080"))
# Если главный цикл не отмечался дольше этого — воркер завис, /health отдаёт 503.
STALL_AFTER = max(60.0, INTERVAL * 6)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker")

PROCESSED = Counter("shop_worker_orders_processed_total", "Orders marked as processed")
ERRORS = Counter("shop_worker_errors_total", "Failed processing iterations")
LAST_SUCCESS = Gauge(
    "shop_worker_last_success_timestamp_seconds", "Unix time of the last successful iteration"
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS orders (
    id           SERIAL PRIMARY KEY,
    item         TEXT        NOT NULL,
    quantity     INTEGER     NOT NULL DEFAULT 1,
    status       TEXT        NOT NULL DEFAULT 'new',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
)
"""

# SKIP LOCKED: несколько реплик worker не схватят один и тот же заказ.
CLAIM = """
UPDATE orders SET status = 'processed', processed_at = now()
WHERE id IN (
    SELECT id FROM orders WHERE status = 'new'
    ORDER BY id LIMIT %s
    FOR UPDATE SKIP LOCKED
)
RETURNING id
"""

stop = threading.Event()
last_tick = time.monotonic()
_schema_ready = False


def health_fail():
    return os.environ.get("HEALTH_FAIL", "").lower() in ("1", "true", "yes")


def ensure_schema(conn):
    global _schema_ready
    if _schema_ready:
        return
    try:
        conn.execute(SCHEMA)
        conn.commit()
    except (pgerrors.UniqueViolation, pgerrors.DuplicateTable):
        conn.rollback()
    _schema_ready = True


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            stalled = time.monotonic() - last_tick > STALL_AFTER
            if stalled or health_fail():
                self._send(503, b"fail", "text/plain")
            else:
                self._send(200, b"ok", "text/plain")
        elif self.path == "/metrics":
            self._send(200, generate_latest(), CONTENT_TYPE_LATEST)
        else:
            self._send(404, b"not found", "text/plain")

    def _send(self, code, body, content_type):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # пробы дёргают /health каждые несколько секунд — не засоряем лог


def process_once():
    with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
        ensure_schema(conn)
        ids = [row[0] for row in conn.execute(CLAIM, (BATCH,)).fetchall()]
    if ids:
        PROCESSED.inc(len(ids))
        log.info("processed orders: %s", ids)
    LAST_SUCCESS.set_to_current_time()


def main():
    global last_tick
    # Свой обработчик SIGTERM: иначе Python с PID 1 в контейнере проигнорирует сигнал
    # и Kubernetes будет ждать весь grace period до SIGKILL.
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log.info("worker started: interval=%ss batch=%s, /health and /metrics on :%s", INTERVAL, BATCH, PORT)

    while not stop.is_set():
        last_tick = time.monotonic()
        try:
            process_once()
        except psycopg.Error as e:
            ERRORS.inc()
            log.warning("db error: %s", e)
        stop.wait(INTERVAL)

    server.shutdown()
    log.info("worker stopped")


if __name__ == "__main__":
    main()
