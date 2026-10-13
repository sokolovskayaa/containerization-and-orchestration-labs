"""shop api: HTTP-сервис заказов поверх postgres."""
import logging
import os
import socket
import time

import psycopg
from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from psycopg import errors as pgerrors

APP_VERSION = os.environ.get("APP_VERSION", "dev")
# Пустая строка = libpq сам возьмёт PGHOST/PGUSER/PGPASSWORD/PGDATABASE из окружения.
DATABASE_URL = os.environ.get("DATABASE_URL", "")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("api")

app = Flask(__name__)

REQUESTS = Counter("shop_http_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("shop_http_request_duration_seconds", "HTTP request latency", ["path"])
ORDERS_CREATED = Counter("shop_orders_created_total", "Orders created")

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

_schema_ready = False


def health_fail():
    return os.environ.get("HEALTH_FAIL", "").lower() in ("1", "true", "yes")


def db():
    return psycopg.connect(DATABASE_URL, connect_timeout=3)


def ensure_schema(conn):
    global _schema_ready
    if _schema_ready:
        return
    try:
        conn.execute(SCHEMA)
        conn.commit()
    except (pgerrors.UniqueViolation, pgerrors.DuplicateTable):
        # api и worker могут создавать таблицу одновременно — проигравший получит конфликт, это нормально.
        conn.rollback()
    _schema_ready = True


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def record_metrics(response):
    path = request.url_rule.rule if request.url_rule else "unknown"
    if path != "/metrics":
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        LATENCY.labels(path).observe(time.perf_counter() - g.start)
    return response


@app.get("/health")
def health():
    # HEALTH_FAIL=true — «сломанная версия» для Части 2: пробы начинают падать.
    if health_fail():
        return Response("fail", status=503, mimetype="text/plain")
    return Response("ok", mimetype="text/plain")


@app.get("/version")
def version():
    # hostname внутри пода = имя пода: видно, какая реплика и какой версии ответила.
    return jsonify(version=APP_VERSION, hostname=socket.gethostname())


@app.post("/order")
def create_order():
    data = request.get_json(silent=True) or {}
    item = str(data.get("item", "")).strip()
    try:
        quantity = int(data.get("quantity", 1))
    except (TypeError, ValueError):
        quantity = 0
    if not item or quantity < 1:
        return jsonify(error='expected JSON like {"item": "book", "quantity": 1}'), 400

    try:
        with db() as conn:
            ensure_schema(conn)
            order_id, created_at = conn.execute(
                "INSERT INTO orders (item, quantity) VALUES (%s, %s) RETURNING id, created_at",
                (item, quantity),
            ).fetchone()
    except psycopg.Error as e:
        log.warning("db error on POST /order: %s", e)
        return jsonify(error="database unavailable"), 503

    ORDERS_CREATED.inc()
    return jsonify(
        id=order_id, item=item, quantity=quantity, status="new", created_at=created_at.isoformat()
    ), 201


@app.get("/orders")
def list_orders():
    try:
        with db() as conn:
            ensure_schema(conn)
            rows = conn.execute(
                "SELECT id, item, quantity, status, created_at, processed_at "
                "FROM orders ORDER BY id DESC LIMIT 100"
            ).fetchall()
    except psycopg.Error as e:
        log.warning("db error on GET /orders: %s", e)
        return jsonify(error="database unavailable"), 503

    return jsonify([
        {
            "id": r[0],
            "item": r[1],
            "quantity": r[2],
            "status": r[3],
            "created_at": r[4].isoformat(),
            "processed_at": r[5].isoformat() if r[5] else None,
        }
        for r in rows
    ])


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), content_type=CONTENT_TYPE_LATEST)
