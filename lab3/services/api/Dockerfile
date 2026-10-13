FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

ARG VERSION=dev
ENV APP_VERSION=$VERSION

# Числовой UID, а не имя: так Kubernetes может проверить, что процесс не root.
USER 10001
EXPOSE 8080

# Один процесс с потоками — метрики prometheus_client живут в одном месте.
# gunicorn на SIGTERM дорабатывает текущие запросы и выходит.
# --worker-tmp-dir /dev/shm — gunicorn не пишет в файловую систему образа.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", \
     "--worker-tmp-dir", "/dev/shm", "--graceful-timeout", "20", "app:app"]
