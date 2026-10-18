SHELL := /usr/bin/env bash
.ONESHELL:

.PHONY: all clean install setup-dirs train-pipeline data-pipeline inference-pipeline help test mlflow-up mlflow-down mlflow-ui mlflow-logs mlflow-local

# Default Python interpreter
PYTHON = python
VENV = .venv/bin/activate
MLFLOW_PORT ?= 5001

# Default target
all: help

# Help target
help:
	@echo "🚀 Production ML Pipeline System"
	@echo "================================="
	@echo ""
	@echo "🎯 END-TO-END WORKFLOWS (Recommended):"
	@echo "  LOCAL:  ./run_local.sh           - 🚀 Deploy complete LOCAL setup"
	@echo "  ECS:    ./run_ecs.sh             - ☁️  Deploy complete ECS setup"
	@echo ""
	@echo "📦 SETUP & CLEANUP:"
	@echo "  make install             - Install project dependencies"
	@echo "  make setup-dirs          - Create necessary directories"
	@echo "  make clean               - Clean local cache only (safe)"
	@echo "  make docker-nuke         - ☢️  NUCLEAR: Remove ALL Docker resources"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🔄 KAFKA STREAMING (Real-time Inference)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make kafka-up                     (Managed by ECS services)"
	@echo "  make kafka-down                   (Managed by ECS services)"
	@echo "  make kafka-restart                make ecs-restart-kafka"
	@echo "  make kafka-status                 make ecs-status"
	@echo "  make kafka-logs                   make ecs-logs-kafka"
	@echo "  make logs-kafka-producer          aws logs tail /ecs/.../kafka-producer --follow"
	@echo "  make logs-kafka-inference         aws logs tail /ecs/.../kafka-inference --follow"
	@echo "  make logs-kafka-analytics         aws logs tail /ecs/.../kafka-analytics --follow"
	@echo "  make kafka-ui                     (Not available in ECS)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "⏸️  PAUSE/RESUME SERVICES"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make pause-kafka                  make pause-ecs"
	@echo "  make resume-kafka                 make resume-ecs"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✈️  AIRFLOW (Workflow Orchestration)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make airflow-up                   (Managed by ECS services)"
	@echo "  make airflow-down                 (Managed by ECS services)"
	@echo "  make airflow-ui                   open http://\$${ALB_DNS}:8080"
	@echo "  make airflow-init                 ./ecs-deployment/70_airflow_init.sh"
	@echo "  make airflow-reset                ./ecs-deployment/70_airflow_init_reset.sh"
	@echo "  docker logs airflow-scheduler     make ecs-logs-airflow"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🔬 MLFLOW (Experiment Tracking)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make mlflow-up                    (Managed by ECS services)"
	@echo "  make mlflow-down                  (Managed by ECS services)"
	@echo "  make mlflow-ui                    open http://\$${ALB_DNS}:5001"
	@echo "  http://localhost:5001             http://\$${ALB_DNS}:5001"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🔄 ML PIPELINES (Data & Training)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make data-pipeline                (Triggered via Airflow DAG)"
	@echo "  make train-pipeline               (Triggered via Airflow DAG)"
	@echo "  make inference-pipeline           (Triggered via Airflow DAG)"
	@echo "  make run-all                      (Trigger DAGs in Airflow UI)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "📊 MONITORING & STATUS"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  🏠 LOCAL                          ☁️  ECS"
	@echo "  ─────────────────────────────────────────────────────────────────"
	@echo "  make status                       make ecs-status"
	@echo "  make docker-status                make ecs-status"
	@echo "  make kafka-status                 make ecs-status"
	@echo "  docker ps                         aws ecs list-tasks --cluster churn-pipeline-ecs"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "📜 ADDITIONAL COMMANDS"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  📂 Local-Only (No AWS):"
	@echo "    make data-pipeline-local       - Run data pipeline locally"
	@echo "    make train-pipeline-local      - Run training locally"
	@echo "    make run-all-local             - Run all pipelines locally"
	@echo ""
	@echo "  🐳 Docker:"
	@echo "    make docker-build              - Build Docker images"
	@echo "    make docker-up                 - Start all Docker services"
	@echo "    make docker-down               - Stop all Docker services"
	@echo "    make docker-clean              - Clean Docker resources"
	@echo ""
	@echo "  📊 RDS Database:"
	@echo "    make rds-show-all              - Show all databases"
	@echo "    make rds-adminer               - Launch Adminer UI"
	@echo "    make rds-psql-airflow          - Connect to Airflow DB"
	@echo "    make rds-clear-airflow-cache   - Clear Airflow cache"
	@echo ""
	@echo "  ☁️  ECS Management:"
	@echo "    make ecs-restart-airflow       - Restart Airflow services"
	@echo "    make ecs-scale-kafka           - Scale Kafka services"
	@echo "    ./ecs-deployment/stop_ecs.sh   - Stop all ECS services"
	@echo "    ./ecs-deployment/restart_ecs.sh - Restart all ECS services"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "💡 TIP: Commands are organized as LOCAL → ECS equivalents"
	@echo "📖 For more details, see README.md or docs-capstone/URLS.md"

# ========================================================================================
# SETUP AND ENVIRONMENT COMMANDS
# ========================================================================================

# Install project dependencies and set up environment using uv
install:
	@echo "📦 Installing dependencies..."
	pip install uv
	uv pip install -e .
	uv pip install -r requirements.txt
	@echo "✅ Installation complete!"
	@echo "💡 Next steps:"
	@echo "   1. Configure AWS credentials (~/.aws/credentials)"
	@echo "   2. Update config.yaml with your settings"

# Create necessary directories
setup-dirs:
	@mkdir -p artifacts/data artifacts/models artifacts/analytics_reports
	@mkdir -p data/raw data/processed
	@mkdir -p reports

# Clean up local cache only (safe cleanup)
clean:
	@echo "🧹 Cleaning local cache..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	find . -type f -name "*.pyo" -delete 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Local cache cleaned"

# Clean up S3 artifacts (project-specific only) - UNIFIED STRUCTURE
s3-clean:
	@echo "🧹 Cleaning S3 artifacts..."
	@echo "⚠️  This will delete:"
	@echo "   • s3://$(S3_BUCKET)/artifacts/data/*"
	@echo "   • s3://$(S3_BUCKET)/artifacts/train/*"
	@echo ""
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "Deleting data artifacts..."; \
		aws s3 rm s3://$(S3_BUCKET)/artifacts/data/ --recursive || true; \
		echo "Deleting training artifacts..."; \
		aws s3 rm s3://$(S3_BUCKET)/artifacts/train/ --recursive || true; \
		echo "✅ S3 artifacts cleaned"; \
	else \
		echo "❌ Cancelled"; \
	fi

# Remove legacy local artifact folders (since we're S3-only now)
clean-local-artifacts:
	@echo "🧹 Removing legacy local artifact folders..."
	@if [ -d "artifacts/data" ] || [ -d "artifacts/models" ]; then \
		echo "Found local artifacts:"; \
		ls -lh artifacts/ 2>/dev/null || true; \
		echo ""; \
		read -p "Delete these local artifacts? (yes/no): " confirm; \
		if [ "$$confirm" = "yes" ]; then \
			rm -rf artifacts/data/* artifacts/models/* 2>/dev/null || true; \
			echo "✅ Local artifacts removed"; \
		else \
			echo "❌ Cancelled"; \
		fi; \
	else \
		echo "✅ No local artifacts found"; \
	fi

# ========================================================================================
# DOCKER COMMANDS
# ========================================================================================

# Docker compose file (single file - embedded PySpark architecture)
DOCKER_COMPOSE = docker-compose.yml

# Build all Docker images (embedded PySpark architecture)
docker-build:
	@echo "🐳 Building Docker images (embedded PySpark architecture)..."
	docker-compose -f $(DOCKER_COMPOSE) build
	@echo "✅ Docker images built successfully"
	@echo "💡 Next: make docker-up"

# Start all services (MLflow + 3 pipeline containers)
docker-up:
	@echo "🚀 Starting all services (MLflow + 3 pipelines)..."
	docker-compose -f $(DOCKER_COMPOSE) up -d
	@echo "✅ Services started"
	@echo "💡 MLflow UI: http://localhost:$(MLFLOW_PORT)"
	@echo "💡 View logs: make docker-logs"
	@echo "💡 Run pipelines: make docker-run-all"

# Stop all services
docker-down:
	@echo "⏹️  Stopping all services..."
	docker-compose -f $(DOCKER_COMPOSE) down
	@echo "✅ Services stopped"

# Clean up Docker resources
docker-clean:
	@echo "🧹 Cleaning Docker resources..."
	docker-compose -f $(DOCKER_COMPOSE) down -v
	@echo "✅ Docker resources cleaned"

# Nuclear cleanup - Remove ALL project Docker images and containers
docker-clean-all:
	@echo "☢️  NUCLEAR CLEANUP - Removing ALL project Docker resources + ECS images"
	@echo ""
	@echo "⚠️  This will remove:"
	@echo "   • All churn-pipeline Docker images"
	@echo "   • All churn-pipeline containers"
	@echo "   • All churn-pipeline volumes"
	@echo "   • All churn-pipeline networks"
	@echo "   • All ECR images (if AWS credentials configured)"
	@echo ""
	@read -p "Are you ABSOLUTELY sure? Type 'DELETE' to confirm: " confirm; \
	if [ "$$confirm" = "DELETE" ]; then \
		echo ""; \
		echo "🔥 Starting nuclear cleanup..."; \
		echo ""; \
		echo "1️⃣ Stopping and removing containers..."; \
		docker ps -a --filter "name=churn-pipeline" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true; \
		echo "✅ Containers removed"; \
		echo ""; \
		echo "2️⃣ Removing Docker images..."; \
		docker images --filter "reference=churn-pipeline/*" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true; \
		echo "✅ Docker images removed"; \
		echo ""; \
		echo "3️⃣ Removing volumes..."; \
		docker volume ls --filter "name=churn-pipeline" --format "{{.Name}}" | xargs -r docker volume rm 2>/dev/null || true; \
		echo "✅ Volumes removed"; \
		echo ""; \
		echo "4️⃣ Removing networks..."; \
		docker network ls --filter "name=churn-pipeline" --format "{{.ID}}" | xargs -r docker network rm 2>/dev/null || true; \
		echo "✅ Networks removed"; \
		echo ""; \
		echo "5️⃣ Checking for ECR images..."; \
		if aws ecr describe-repositories --region $(AWS_REGION) 2>/dev/null | grep -q "churn-pipeline"; then \
			echo "Found ECR repositories. Deleting images..."; \
			for repo in $$(aws ecr describe-repositories --region $(AWS_REGION) --query 'repositories[?contains(repositoryName, `churn-pipeline`)].repositoryName' --output text); do \
				echo "Deleting images from $$repo..."; \
				aws ecr batch-delete-image --region $(AWS_REGION) --repository-name $$repo --image-ids $$(aws ecr list-images --region $(AWS_REGION) --repository-name $$repo --query 'imageIds[*]' --output json) 2>/dev/null || true; \
			done; \
			echo "✅ ECR images removed"; \
		else \
			echo "ℹ️  No ECR repositories found (or AWS not configured)"; \
		fi; \
		echo ""; \
		echo "✅ Nuclear cleanup complete!"; \
		echo ""; \
		echo "📊 Remaining Docker resources:"; \
		echo "Images:"; \
		docker images | grep churn-pipeline || echo "  None"; \
		echo "Containers:"; \
		docker ps -a | grep churn-pipeline || echo "  None"; \
		echo "Volumes:"; \
		docker volume ls | grep churn-pipeline || echo "  None"; \
	else \
		echo "❌ Cancelled - nothing was deleted"; \
	fi

# Show Docker service status
docker-status:
	@echo "📊 Docker Service Status:"
	@echo ""
	@docker-compose -f $(DOCKER_COMPOSE) ps
	@echo ""
	@echo "💡 View logs: make docker-logs"

# View Docker logs
docker-logs:
	@docker-compose -f $(DOCKER_COMPOSE) logs -f

# View Kafka Producer logs (continuous)
logs-kafka-producer:
	@echo "📤 Kafka Producer Logs (Ctrl+C to exit):"
	@docker logs -f kafka-producer

# View Kafka Inference logs (continuous)
logs-kafka-inference:
	@echo "📥 Kafka Inference Logs (Ctrl+C to exit):"
	@docker logs -f kafka-inference

# View Kafka Analytics logs (continuous)
logs-kafka-analytics:
	@echo "📊 Kafka Analytics Logs (Ctrl+C to exit):"
	@docker logs -f kafka-analytics

# Restart Kafka services (local Docker)
restart-kafka:
	@echo "🔄 Restarting Kafka services..."
	@echo ""
	@echo "1️⃣ Stopping Kafka containers..."
	docker stop kafka-producer kafka-inference kafka-analytics 2>/dev/null || true
	@echo "✅ Stopped"
	@echo ""
	@echo "2️⃣ Starting Kafka containers..."
	docker start kafka-producer kafka-inference kafka-analytics 2>/dev/null || true
	@echo "✅ Started"
	@echo ""
	@echo "3️⃣ Checking status..."
	@sleep 3
	@docker ps --filter "name=kafka-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "💡 View logs:"
	@echo "   make logs-kafka-producer"
	@echo "   make logs-kafka-inference"
	@echo "   make logs-kafka-analytics"

# Show Docker image sizes
docker-image-sizes:
	@echo "📊 Docker Image Sizes:"
	@docker images --filter "reference=churn-pipeline/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ========================================================================================
# ML PIPELINE COMMANDS (Local)
# ========================================================================================

# Run data preprocessing pipeline (with S3 enabled by default)
data-pipeline: setup-dirs
	@echo "🔄 Running data preprocessing pipeline..."
	$(PYTHON) pipelines/data_pipeline.py
	@echo "✅ Data pipeline complete"
	@echo "💡 Next: make train-pipeline"

# Run model training pipeline (with S3 enabled by default)
train-pipeline: setup-dirs
	@echo "🔄 Running model training pipeline..."
	$(PYTHON) pipelines/training_pipeline.py
	@echo "✅ Training pipeline complete"
	@echo "💡 Next: make inference-pipeline"

# Run model training pipeline with Docker MLflow URL
train-pipeline-docker: setup-dirs
	@CONTAINERIZED=true $(PYTHON) pipelines/training_pipeline.py

# Run batch inference pipeline
inference-pipeline: setup-dirs
	@$(PYTHON) pipelines/inference_pipeline.py

# ==========================================
# 📂 LOCAL-ONLY Pipeline Commands (No S3)
# ==========================================
# Run pipelines with local artifact storage (no AWS credentials needed)
data-pipeline-local: setup-dirs
	@echo "📂 Running data pipeline (local mode - no S3)"
	@USE_S3=false $(PYTHON) pipelines/data_pipeline.py

train-pipeline-local: setup-dirs
	@echo "📂 Running training pipeline (local mode - no S3)"
	@USE_S3=false $(PYTHON) pipelines/training_pipeline.py

inference-pipeline-local: setup-dirs
	@echo "📂 Running inference pipeline (local mode - no S3)"
	@USE_S3=false $(PYTHON) pipelines/inference_pipeline.py

# Run all pipelines locally
run-all-local: data-pipeline-local train-pipeline-local inference-pipeline-local
	@echo "✅ All local pipelines complete!"
	@echo "💡 Check artifacts/ folder for outputs"

# Validate local model
validate-model-local:
	@echo "🔬 Validating local model..."
	@$(PYTHON) -c "import pickle; import json; model = pickle.load(open('artifacts/models/best_model.pkl', 'rb')); metadata = json.load(open('artifacts/models/model_metadata.json')); print(f\"Model: {metadata['model_type']}\"); print(f\"Accuracy: {metadata['accuracy']:.2%}\"); assert metadata['accuracy'] >= 0.75, 'Model accuracy below threshold!'"

# Run all pipelines in sequence
run-all: data-pipeline train-pipeline inference-pipeline
	@echo "✅ All pipelines complete!"

# ========================================================================================
# AIRFLOW AUTOMATION COMMANDS (DockerOperator Approach)
# ========================================================================================

AIRFLOW_COMPOSE = docker-compose.airflow.yml
AIRFLOW_IMAGE = churn-pipeline/airflow:2.8.1-amazon

# Build custom Airflow image with Docker and Amazon providers
airflow-build:
	@echo "🐳 Building custom Airflow image..."
	docker build -f docker/Dockerfile.airflow -t $(AIRFLOW_IMAGE) .

# Initialize Airflow database and create admin user (ALWAYS clears DAG history + cache)
airflow-init:
	@echo "🗑️  Clearing RDS Airflow DAG cache and history..."
	@$(MAKE) rds-clear-airflow-cache
	@echo ""
	@echo "🔧 Initializing Airflow database..."
	docker-compose -f $(AIRFLOW_COMPOSE) run --rm airflow-init
	@echo ""
	@echo "✅ Airflow initialized successfully!"
	@echo "💡 Next steps:"
	@echo "   1. make airflow-up       # Start Airflow services"
	@echo "   2. Open http://localhost:8080"
	@echo "   3. Login: admin / admin"
	@echo ""
	@echo "⚠️  Note: All previous DAG runs and history have been cleared"

# Start Airflow services
airflow-up:
	@echo "🚀 Starting Airflow services..."
	@docker image inspect $(AIRFLOW_IMAGE) >/dev/null 2>&1 || $(MAKE) airflow-build
	@docker-compose -f $(AIRFLOW_COMPOSE) up -d --remove-orphans
	@echo ""
	@echo "✅ Airflow services started!"
	@echo ""
	@echo "🌐 Airflow UI: http://localhost:8080"
	@echo "   Username: admin"
	@echo "   Password: admin"
	@echo ""
	@echo "💡 View logs: docker-compose -f $(AIRFLOW_COMPOSE) logs -f"

# Stop Airflow services
airflow-down:
	@echo "⏹️  Stopping Airflow services..."
	docker-compose -f $(AIRFLOW_COMPOSE) down
	@echo "✅ Airflow services stopped"

# Reset Airflow completely (stop services, remove volumes, clear all DAG history)
airflow-reset:
	@echo "🔥 Resetting Airflow (stop services + delete volumes + clear RDS history)..."
	docker-compose -f $(AIRFLOW_COMPOSE) down -v
	@echo "🗑️  Clearing RDS Airflow DAG cache and history..."
	@$(MAKE) rds-clear-airflow-cache
	@echo "✅ Airflow reset complete"
	@echo "💡 Next: make airflow-init"

# ========================================================================================
# S3 UTILITY COMMANDS
# ========================================================================================

# List S3 keys with prefix
s3-list:
	@echo "📂 Listing S3 keys with prefix: $(PREFIX)"
	@aws s3 ls s3://$(S3_BUCKET)/$(PREFIX) --recursive --human-readable

# Delete specific S3 keys with prefix (use with caution)
s3-delete-prefix:
	@echo "⚠️  WARNING: This will delete all keys with prefix: $(PREFIX)"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		aws s3 rm s3://$(S3_BUCKET)/$(PREFIX) --recursive; \
	fi

# Upload local data folders to S3 (one-time setup)
s3-upload-data:
	@echo "📤 Uploading local data to S3..."
	aws s3 sync data/raw s3://$(S3_BUCKET)/data/raw
	aws s3 sync data/processed s3://$(S3_BUCKET)/data/processed
	@echo "✅ Data uploaded to S3"

# S3 smoke test (write/read roundtrip)
s3-smoke:
	@$(PYTHON) -c "from utils.s3_io import put_string, get_string; put_string('test-key', 'Hello S3!'); print(get_string('test-key'))"

# ========================================================================================
# MLFLOW EXPERIMENT TRACKING COMMANDS
# ========================================================================================

# Start MLflow tracking server (via Docker)
mlflow-up:
	@echo "🚀 Starting MLflow tracking server via Docker..."
	@docker info >/dev/null 2>&1 || (echo "❌ Docker Desktop is not running! Please start Docker Desktop, or run 'make mlflow-local' to run MLflow without Docker." && exit 1)
	docker-compose -f $(DOCKER_COMPOSE) up -d mlflow-tracking
	@echo ""
	@echo "✅ MLflow server started!"
	@echo "🌐 MLflow UI: http://localhost:$(MLFLOW_PORT)"
	@echo "💡 View logs: make mlflow-logs"

# Run MLflow UI locally with Python (No Docker needed)
mlflow-local:
	@echo "🚀 Starting MLflow server locally (without Docker)..."
	@echo "🌐 MLflow UI: http://localhost:$(MLFLOW_PORT)"
	@echo "💡 Press Ctrl+C to stop"
	mlflow server --backend-store-uri sqlite:///mlflow.db --port $(MLFLOW_PORT) --host 127.0.0.1 --workers 1

# Stop MLflow tracking server
mlflow-down:
	@echo "⏹️  Stopping MLflow tracking server..."
	docker-compose -f $(DOCKER_COMPOSE) stop mlflow-tracking
	@echo "✅ MLflow server stopped"

# View MLflow server logs
mlflow-logs:
	@docker-compose -f $(DOCKER_COMPOSE) logs -f mlflow-tracking

# Open MLflow UI in browser
mlflow-ui:
	@echo "🌐 Opening MLflow UI at http://localhost:$(MLFLOW_PORT)..."
	@start http://localhost:$(MLFLOW_PORT) 2>/dev/null || cmd.exe /c start http://localhost:$(MLFLOW_PORT) 2>/dev/null || open http://localhost:$(MLFLOW_PORT) 2>/dev/null || xdg-open http://localhost:$(MLFLOW_PORT) 2>/dev/null || echo "Please open http://localhost:$(MLFLOW_PORT) in your browser"

# Test MLflow S3 integration
test-mlflow:
	@$(PYTHON) -c "import mlflow; mlflow.set_tracking_uri('http://localhost:$(MLFLOW_PORT)'); print(mlflow.get_tracking_uri())"

# Show project status
status:
	@echo "📊 Project Status:"
	@echo ""
	@echo "📂 Local Artifacts:"
	@ls -lh artifacts/ 2>/dev/null || echo "  No local artifacts"
	@echo ""
	@echo "☁️  S3 Artifacts:"
	@aws s3 ls s3://$(S3_BUCKET)/artifacts/ --recursive --human-readable 2>/dev/null || echo "  Unable to access S3 (check credentials)"
	@echo ""
	@echo "🐳 Docker Status:"
	@docker ps --filter "name=churn-pipeline" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "  Docker not running"

# ========================================================================================
# RDS DATABASE VISUALIZATION COMMANDS
# ========================================================================================

# Load RDS credentials from .env file if it exists
# Otherwise fall back to default values (for backward compatibility)
ifneq (,$(wildcard .env))
    include .env
    export
endif

# RDS Connection Parameters with fallbacks
# RDS Configuration - load from .env file
RDS_HOST ?= localhost
RDS_PORT ?= 5432
RDS_USER ?= admin
RDS_PASSWORD ?= password
RDS_DB ?= airflow
RDS_MLFLOW_DB ?= mlflow
PSQL_CLIENT_IMAGE ?= postgres:15

PSQL_BIN := $(shell command -v psql 2>/dev/null | tr -d '\r')
DOCKER_BIN := $(shell command -v docker 2>/dev/null | tr -d '\r')

ifeq ($(PSQL_BIN),)
	ifeq ($(DOCKER_BIN),)
		PSQL_CLIENT_CMD = sh -c 'echo "❌ psql not found and Docker is unavailable. Install postgresql-client or Docker."; exit 127'
	else
		PSQL_CLIENT_CMD = docker run --rm -e PGPASSWORD="$(RDS_PASSWORD)" $(PSQL_CLIENT_IMAGE) psql
	endif
else
	PSQL_CLIENT_CMD = env PGPASSWORD="$(RDS_PASSWORD)" "$(PSQL_BIN)"
endif

# Show all RDS databases overview
rds-show-all:
	@echo "📊 RDS Databases Overview:"
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d postgres -c "\l"

# Show MLflow database schema
rds-show-mlflow:
	@echo "📊 MLflow Database Schema:"
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_MLFLOW_DB) -c "\dt"

# Show Airflow database schema
rds-show-airflow:
	@echo "📊 Airflow Database Schema:"
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_DB) -c "\dt"

# Launch Adminer web UI for database visualization
rds-adminer:
	@echo "🚀 Launching Adminer web UI..."
	@docker run -d --name adminer \
		-p 8081:8080 \
		-e ADMINER_DEFAULT_SERVER=$(RDS_HOST) \
		adminer
	@echo ""
	@echo "✅ Adminer started!"
	@echo "🌐 URL: http://localhost:8081"
	@echo ""
	@echo "📝 Login credentials:"
	@echo "   System: PostgreSQL"
	@echo "   Server: $(RDS_HOST)"
	@echo "   Username: $(RDS_USER)"
	@echo "   Password: $(RDS_PASSWORD)"
	@echo "   Database: $(RDS_DB) or $(RDS_MLFLOW_DB)"

# Stop Adminer
rds-adminer-down:
	@echo "⏹️  Stopping Adminer..."
	@docker stop adminer && docker rm adminer
	@echo "✅ Adminer stopped"

# Connect to MLflow database with psql
rds-psql-mlflow:
	@echo "🔌 Connecting to MLflow database..."
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_MLFLOW_DB)

# Connect to Airflow database with psql
rds-psql-airflow:
	@echo "🔌 Connecting to Airflow database..."
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_DB)


# Clear Airflow DAG cache and history from RDS
rds-clear-airflow-cache:
	@echo "🗑️  Clearing Airflow DAG cache and history from RDS..."
	@echo ""
	@echo "⚠️  This will:"
	@echo "   • Delete all DAG runs"
	@echo "   • Delete all task instances"
	@echo "   • Delete all job history"
	@echo "   • Clear serialized DAGs"
	@echo "   • Clear DAG parsing logs"
	@echo ""
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo ""; \
		echo "Executing cleanup SQL..."; \
		$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_DB) << 'EOF'
		-- Delete all DAG runs and task instances
		TRUNCATE TABLE task_instance CASCADE;
		TRUNCATE TABLE dag_run CASCADE;
		TRUNCATE TABLE job CASCADE;
		TRUNCATE TABLE log CASCADE;
		TRUNCATE TABLE xcom CASCADE;
		TRUNCATE TABLE sla_miss CASCADE;
		TRUNCATE TABLE task_fail CASCADE;
		TRUNCATE TABLE task_reschedule CASCADE;
		TRUNCATE TABLE rendered_task_instance_fields CASCADE;
		
		-- Clear serialized DAGs
		TRUNCATE TABLE serialized_dag CASCADE;
		
		-- Clear DAG parsing logs
		TRUNCATE TABLE import_error CASCADE;
		TRUNCATE TABLE dag_code CASCADE;
		
		-- Show remaining DAG metadata (should be empty)
		SELECT COUNT(*) as remaining_dag_runs FROM dag_run;
		SELECT COUNT(*) as remaining_task_instances FROM task_instance;
		EOF
		echo ""; \
		echo "✅ Airflow DAG cache and history cleared!"; \
		echo "💡 Restart Airflow services to see changes: make airflow-down && make airflow-up"; \
	else \
		echo "❌ Cancelled"; \
	fi

# ============================================================================
# 🎯 END-TO-END WORKFLOWS
# ============================================================================

# 1️⃣ Clean up EVERYTHING (Local + ECS)
clean-all:
	@echo "🔥 FULL CLEANUP - Local + RDS Airflow + ECS"
	@echo ""
	@echo "⚠️  This will:"
	@echo "   • Stop and remove all local Docker containers"
	@echo "   • Remove all local Docker images"
	@echo "   • Clear RDS Airflow DAG cache and history"
	@echo "   • Scale down ECS services to 0 (if configured)"
	@echo ""
	@read -p "Are you ABSOLUTELY sure? Type 'CLEAN' to confirm: " confirm; \
	if [ "$$confirm" = "CLEAN" ]; then \
		echo ""; \
		echo "1️⃣ Stopping local Docker services..."; \
		docker-compose -f docker-compose.yml down -v 2>/dev/null || true; \
		docker-compose -f docker-compose.airflow.yml down -v 2>/dev/null || true; \
		docker-compose -f docker-compose.kafka.yml down -v 2>/dev/null || true; \
		echo "✅ Local Docker stopped"; \
		echo ""; \
		echo "2️⃣ Clearing RDS Airflow cache..."; \
		$(MAKE) rds-clear-airflow-cache; \
		echo "✅ RDS Airflow cleared"; \
		echo ""; \
		echo "3️⃣ Checking ECS services..."; \
		if [ -f "ecs-deployment/00_env.sh" ]; then \
			echo "Found ECS configuration. Scaling down..."; \
			$(MAKE) pause-ecs; \
			echo "✅ ECS services scaled down"; \
		else \
			echo "ℹ️  No ECS configuration found"; \
		fi; \
		echo ""; \
		echo "✅ Full cleanup complete!"; \
	else \
		echo "❌ Cancelled"; \
	fi

# ========================================================================================
# KAFKA STREAMING
# ========================================================================================

KAFKA_COMPOSE = docker-compose.kafka.yml

# Build Kafka services
kafka-build:
	@echo "🐳 Building Kafka services..."
	docker-compose -f $(KAFKA_COMPOSE) build

# Start Kafka stack
kafka-up:
	@echo "🚀 Starting Kafka stack..."
	docker-compose -f $(KAFKA_COMPOSE) up -d
	@echo ""
	@echo "✅ Kafka services started!"
	@echo "🌐 Kafka UI: http://localhost:8080"
	@echo ""
	@echo "💡 View logs:"
	@echo "   make logs-kafka-producer"
	@echo "   make logs-kafka-inference"
	@echo "   make logs-kafka-analytics"

# Stop Kafka stack
kafka-down:
	@echo "⏹️  Stopping Kafka stack..."
	docker-compose -f $(KAFKA_COMPOSE) down
	@echo "✅ Kafka services stopped"

# View Kafka logs
kafka-logs:
	@docker-compose -f $(KAFKA_COMPOSE) logs -f

# Show Kafka stack status
kafka-status:
	@echo "📊 Kafka Stack Status:"
	@docker-compose -f $(KAFKA_COMPOSE) ps

# Clean Kafka (including volumes)
kafka-clean:
	@echo "🧹 Cleaning Kafka resources..."
	docker-compose -f $(KAFKA_COMPOSE) down -v
	@echo "✅ Kafka resources cleaned"

# Restart Kafka stack
kafka-restart: kafka-down kafka-up
	@echo "✅ Kafka stack restarted"

# Open Kafka UI in browser
kafka-ui:
	@open http://localhost:8080 || xdg-open http://localhost:8080 || echo "Please open http://localhost:8080 in your browser"

# Create RDS analytics tables
setup-analytics-tables:
	@echo "📊 Creating RDS analytics tables..."
	@if [ ! -f "sql/create_analytics_tables.sql" ]; then \
		echo "❌ SQL file not found: sql/create_analytics_tables.sql"; \
		exit 1; \
	fi
	@$(PSQL_CLIENT_CMD) -h $(RDS_HOST) -p $(RDS_PORT) -U $(RDS_USER) -d $(RDS_DB) -f sql/create_analytics_tables.sql
	@echo "✅ Analytics tables created"

# ========================================================================================
# NUCLEAR DOCKER CLEANUP (WARNING: DESTROYS EVERYTHING)
# ========================================================================================

# WARNING: This removes ALL Docker resources on your system, not just this project
# Use with extreme caution!
# Nuclear cleanup - removes ALL Docker resources
docker-nuke-confirm:
	@echo "☢️  ☢️  ☢️  NUCLEAR DOCKER CLEANUP ☢️  ☢️  ☢️"
	@echo ""
	@echo "⚠️  ⚠️  ⚠️  EXTREME WARNING ⚠️  ⚠️  ⚠️"
	@echo ""
	@echo "This will PERMANENTLY DELETE:"
	@echo "  • ALL Docker containers (running and stopped)"
	@echo "  • ALL Docker images (including system images)"
	@echo "  • ALL Docker volumes (all data will be lost)"
	@echo "  • ALL Docker networks"
	@echo "  • ALL build cache"
	@echo ""
	@echo "This affects:"
	@echo "  • This project"
	@echo "  • ALL other Docker projects on your system"
	@echo "  • ALL Docker data and configurations"
	@echo ""
	@echo "💀 THIS CANNOT BE UNDONE 💀"
	@echo ""
	@read -p "Type 'I UNDERSTAND THE RISKS' to proceed: " confirm; \
	if [ "$$confirm" = "I UNDERSTAND THE RISKS" ]; then \
		echo ""; \
		echo "🔥 Starting nuclear cleanup in 5 seconds..."; \
		echo "Press Ctrl+C NOW to cancel!"; \
		sleep 5; \
	else \
		echo "❌ Cancelled - Incorrect confirmation"; \
		exit 1; \
	fi

docker-nuke: docker-nuke-confirm
	@echo ""
	@echo "☢️  Executing nuclear cleanup..."
	@echo ""
	@echo "1️⃣ Stopping all containers..."
	@docker stop $$(docker ps -aq) 2>/dev/null || true
	@echo "✅ All containers stopped"
	@echo ""
	@echo "2️⃣ Removing all containers..."
	@docker rm $$(docker ps -aq) 2>/dev/null || true
	@echo "✅ All containers removed"
	@echo ""
	@echo "3️⃣ Removing all images..."
	@docker rmi $$(docker images -q) -f 2>/dev/null || true
	@echo "✅ All images removed"
	@echo ""
	@echo "4️⃣ Removing all volumes..."
	@docker volume rm $$(docker volume ls -q) 2>/dev/null || true
	@echo "✅ All volumes removed"
	@echo ""
	@echo "5️⃣ Removing all networks..."
	@docker network rm $$(docker network ls -q) 2>/dev/null || true
	@echo "✅ All networks removed"
	@echo ""
	@echo "6️⃣ Pruning system..."
	@docker system prune -af --volumes 2>/dev/null || true
	@echo "✅ System pruned"
	@echo ""
	@echo "☢️  Nuclear cleanup complete!"
	@echo ""
	@echo "📊 Docker Status:"
	@docker system df
	@echo ""
	@echo "💡 To rebuild this project:"
	@echo "   1. make docker-build"
	@echo "   2. make docker-up"

# ========================================================================================
# PAUSE/RESUME STREAMING & TRAINING
# ========================================================================================

# NOTE: These commands pause/resume Kafka services and provide instructions for Airflow DAGs
# Airflow DAG pause/unpause must be done manually via UI or CLI

# Pause Kafka services and Airflow DAGs
pause-kafka:
	@echo "⏸️  Pausing LOCAL Kafka services and Airflow DAGs..."
	@echo ""
	@echo "1️⃣ Pausing Kafka services..."
	@if docker ps --filter "name=kafka-producer" --filter "status=running" | grep -q kafka-producer; then \
		echo "Stopping kafka-producer..."; \
		docker stop kafka-producer; \
	else \
		echo "kafka-producer already stopped"; \
	fi
	@if docker ps --filter "name=kafka-inference" --filter "status=running" | grep -q kafka-inference; then \
		echo "Stopping kafka-inference..."; \
		docker stop kafka-inference; \
	else \
		echo "kafka-inference already stopped"; \
	fi
	@if docker ps --filter "name=kafka-analytics" --filter "status=running" | grep -q kafka-analytics; then \
		echo "Stopping kafka-analytics..."; \
		docker stop kafka-analytics; \
	else \
		echo "kafka-analytics already stopped"; \
	fi
	@echo "✅ Kafka services paused"
	@echo ""
	@echo "2️⃣ Airflow DAG Instructions:"
	@echo "   To pause Airflow DAGs, run these commands in Airflow container:"
	@echo ""
	@echo "   docker exec airflow-scheduler airflow dags pause data_pipeline_dag"
	@echo "   docker exec airflow-scheduler airflow dags pause model_training_dag"
	@echo ""
	@echo "   Or use Airflow UI: http://localhost:8080"
	@echo ""
	@echo "✅ Pause complete!"

# Resume Kafka services and Airflow DAGs
resume-kafka:
	@echo "▶️  Resuming LOCAL Kafka services and Airflow DAGs..."
	@echo ""
	@echo "1️⃣ Resuming Kafka services..."
	@if docker ps -a --filter "name=kafka-producer" --filter "status=exited" | grep -q kafka-producer; then \
		echo "Starting kafka-producer..."; \
		docker start kafka-producer; \
	else \
		echo "kafka-producer already running"; \
	fi
	@if docker ps -a --filter "name=kafka-inference" --filter "status=exited" | grep -q kafka-inference; then \
		echo "Starting kafka-inference..."; \
		docker start kafka-inference; \
	else \
		echo "kafka-inference already running"; \
	fi
	@if docker ps -a --filter "name=kafka-analytics" --filter "status=exited" | grep -q kafka-analytics; then \
		echo "Starting kafka-analytics..."; \
		docker start kafka-analytics; \
	else \
		echo "kafka-analytics already running"; \
	fi
	@echo "✅ Kafka services resumed"
	@echo ""
	@echo "2️⃣ Airflow DAG Instructions:"
	@echo "   To unpause Airflow DAGs, run these commands in Airflow container:"
	@echo ""
	@echo "   docker exec airflow-scheduler airflow dags unpause data_pipeline_dag"
	@echo "   docker exec airflow-scheduler airflow dags unpause model_training_dag"
	@echo ""
	@echo "   Or use Airflow UI: http://localhost:8080"
	@echo ""
	@echo "3️⃣ Checking Kafka status..."
	@sleep 3
	@docker ps --filter "name=kafka-" --format "table {{.Names}}\t{{.Status}}"
	@echo ""
	@echo "✅ Resume complete!"
	@echo ""
	@echo "💡 View Kafka logs:"
	@echo "   make logs-kafka-producer"
	@echo "   make logs-kafka-inference"
	@echo "   make logs-kafka-analytics"

# ========================================================================================
# ECS MANAGEMENT COMMANDS
# ========================================================================================

# NOTE: These commands manage ECS services in AWS
# Load environment variables
ENV_FILE = ecs-deployment/00_env.sh

# Pause ECS Kafka services and Airflow data/train services (scale to 0). Print DAG pause hint.
pause-ecs:
	@echo "⏸️  Pausing ECS Kafka services and Airflow DAGs..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		echo "💡 Run ECS deployment first: ./run_ecs.sh"; \
		exit 1; \
	fi
	@echo "1️⃣ Loading environment variables..."
	@. $(ENV_FILE) && \
	echo "✅ Environment loaded" && \
	echo "" && \
	echo "2️⃣ Scaling down Kafka services..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-producer --desired-count 0 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-producer scaled to 0" && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-inference --desired-count 0 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-inference scaled to 0" && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-analytics --desired-count 0 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-analytics scaled to 0" && \
	echo "" && \
	echo "3️⃣ Airflow DAG Instructions:" && \
	echo "   To pause Airflow DAGs, SSH into Airflow scheduler task and run:" && \
	echo "" && \
	echo "   airflow dags pause data_pipeline_dag" && \
	echo "   airflow dags pause model_training_dag" && \
	echo "" && \
	echo "   Or use Airflow UI: http://$$ALB_DNS:8080" && \
	echo "" && \
	echo "✅ ECS services paused!"

# Resume ECS Kafka services and Airflow data/train services (scale to 1). Print DAG unpause hint.
resume-ecs:
	@echo "▶️  Resuming ECS Kafka services and Airflow DAGs..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		echo "💡 Run ECS deployment first: ./run_ecs.sh"; \
		exit 1; \
	fi
	@echo "1️⃣ Loading environment variables..."
	@. $(ENV_FILE) && \
	echo "✅ Environment loaded" && \
	echo "" && \
	echo "2️⃣ Scaling up Kafka services..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-producer --desired-count 1 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-producer scaled to 1" && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-inference --desired-count 1 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-inference scaled to 1" && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-analytics --desired-count 1 --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-analytics scaled to 1" && \
	echo "" && \
	echo "3️⃣ Airflow DAG Instructions:" && \
	echo "   To unpause Airflow DAGs, SSH into Airflow scheduler task and run:" && \
	echo "" && \
	echo "   airflow dags unpause data_pipeline_dag" && \
	echo "   airflow dags unpause model_training_dag" && \
	echo "" && \
	echo "   Or use Airflow UI: http://$$ALB_DNS:8080" && \
	echo "" && \
	echo "4️⃣ Waiting for services to stabilize..." && \
	sleep 10 && \
	echo "" && \
	echo "✅ ECS services resumed!" && \
	echo "" && \
	echo "💡 Check status: make ecs-status"

# Show ECS services status
ecs-status:
	@echo "📊 ECS Services Status:"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@. $(ENV_FILE) && \
	aws ecs list-services --cluster $$CLUSTER_NAME --region $$AWS_REGION --output table && \
	echo "" && \
	echo "💡 For detailed service info:" && \
	echo "   aws ecs describe-services --cluster $$CLUSTER_NAME --services <service-name> --region $$AWS_REGION"

# View ECS Kafka logs
ecs-logs-kafka:
	@echo "📜 ECS Kafka Logs:"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@. $(ENV_FILE) && \
	echo "Select service:" && \
	echo "  1) kafka-producer" && \
	echo "  2) kafka-inference" && \
	echo "  3) kafka-analytics" && \
	read -p "Enter choice (1-3): " choice; \
	case $$choice in \
		1) SERVICE="kafka-producer" ;; \
		2) SERVICE="kafka-inference" ;; \
		3) SERVICE="kafka-analytics" ;; \
		*) echo "Invalid choice"; exit 1 ;; \
	esac; \
	echo "Fetching logs for $$SERVICE..."; \
	aws logs tail /ecs/$$CLUSTER_NAME/$$SERVICE --follow --region $$AWS_REGION

# View ECS Airflow logs
ecs-logs-airflow:
	@echo "📜 ECS Airflow Logs:"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@. $(ENV_FILE) && \
	echo "Select service:" && \
	echo "  1) airflow-webserver" && \
	echo "  2) airflow-scheduler" && \
	echo "  3) airflow-worker" && \
	read -p "Enter choice (1-3): " choice; \
	case $$choice in \
		1) SERVICE="airflow-webserver" ;; \
		2) SERVICE="airflow-scheduler" ;; \
		3) SERVICE="airflow-worker" ;; \
		*) echo "Invalid choice"; exit 1 ;; \
	esac; \
	echo "Fetching logs for $$SERVICE..."; \
	aws logs tail /ecs/$$CLUSTER_NAME/$$SERVICE --follow --region $$AWS_REGION

# Restart ECS Kafka services
ecs-restart-kafka:
	@echo "🔄 Restarting ECS Kafka services..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@. $(ENV_FILE) && \
	echo "Forcing new deployment for kafka-producer..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-producer --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-producer restarting" && \
	echo "Forcing new deployment for kafka-inference..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-inference --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-inference restarting" && \
	echo "Forcing new deployment for kafka-analytics..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-analytics --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-analytics restarting" && \
	echo "" && \
	echo "✅ Kafka services restart initiated!" && \
	echo "💡 Check status: make ecs-status"

# Restart ECS Airflow services
ecs-restart-airflow:
	@echo "🔄 Restarting ECS Airflow services..."
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@. $(ENV_FILE) && \
	echo "Forcing new deployment for airflow-webserver..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service airflow-webserver --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ airflow-webserver restarting" && \
	echo "Forcing new deployment for airflow-scheduler..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service airflow-scheduler --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ airflow-scheduler restarting" && \
	echo "Forcing new deployment for airflow-worker..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service airflow-worker --force-new-deployment --region $$AWS_REGION > /dev/null && \
	echo "✅ airflow-worker restarting" && \
	echo "" && \
	echo "✅ Airflow services restart initiated!" && \
	echo "💡 Check status: make ecs-status"

# Scale ECS Kafka services
ecs-scale-kafka:
	@echo "⚖️  Scale ECS Kafka services:"
	@echo ""
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "❌ Environment file not found: $(ENV_FILE)"; \
		exit 1; \
	fi
	@read -p "Enter desired count (0-5): " count; \
	if [ $$count -lt 0 ] || [ $$count -gt 5 ]; then \
		echo "❌ Invalid count. Must be between 0 and 5."; \
		exit 1; \
	fi; \
	. $(ENV_FILE) && \
	echo "Scaling kafka-producer to $$count..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-producer --desired-count $$count --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-producer scaled to $$count" && \
	echo "Scaling kafka-inference to $$count..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-inference --desired-count $$count --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-inference scaled to $$count" && \
	echo "Scaling kafka-analytics to $$count..." && \
	aws ecs update-service --cluster $$CLUSTER_NAME --service kafka-analytics --desired-count $$count --region $$AWS_REGION > /dev/null && \
	echo "✅ kafka-analytics scaled to $$count" && \
	echo "" && \
	echo "✅ Kafka services scaled!" && \
	echo "💡 Check status: make ecs-status"
