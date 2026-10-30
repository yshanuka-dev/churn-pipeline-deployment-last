#!/bin/bash
set -e

echo "🚀 Starting MLflow Tracking Server..."
echo "📍 Backend Store URI: ${MLFLOW_BACKEND_STORE_URI}"
echo "☁️  Artifact Root:     ${MLFLOW_DEFAULT_ARTIFACT_ROOT}"
echo "🌐 Host: 0.0.0.0:5001"

# MLflow CLI auto-maps env vars to flags (MLFLOW_GUNICORN_OPTS -> --gunicorn-opts).
# Unset it so it doesn't conflict with --uvicorn-opts below.
unset MLFLOW_GUNICORN_OPTS

# Build uvicorn options — allow Docker service hostnames to prevent
# false-positive "DNS rebinding attack" errors in MLflow 2.15+
UVICORN_OPTS="${MLFLOW_UVICORN_OPTS:---forwarded-allow-ips=*}"

# Start MLflow server with proper signal handling
# --uvicorn-opts replaces deprecated --gunicorn-opts (MLflow 2.15+)
exec mlflow server \
    --host 0.0.0.0 \
    --port 5001 \
    --backend-store-uri "${MLFLOW_BACKEND_STORE_URI}" \
    --default-artifact-root "${MLFLOW_DEFAULT_ARTIFACT_ROOT}" \
    --serve-artifacts \
    --uvicorn-opts "${UVICORN_OPTS}"
