#!/bin/bash
################################################################################
# SCRIPT: 50_register_tasks.sh
# PURPOSE: Register ECS Task Definitions from templates
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Reads task definition templates from taskdefs/ directory
# 2. Replaces environment variables (like $ACCOUNT_ID, $AWS_REGION)
# 3. Registers task definitions with ECS
# 4. Creates versioned blueprints for running containers
#
# WHY WE NEED THIS:
# ----------------
# - Task Definitions are "blueprints" for containers (like Dockerfiles for ECS)
# - They define: which image to use, CPU/memory, environment variables, ports
# - ECS uses these blueprints to launch containers
# - Each registration creates a new version (immutable)
#
# PREREQUISITES:
# -------------
# - 10_bootstrap.sh completed (Docker images pushed to ECR)
# - 30_iam.sh completed (IAM roles created)
# - taskdefs/*.json.template files exist
# - 00_env.sh configured with all required variables
#
# STUDENT NOTE:
# ------------
# Task Definition = Recipe for running a container
# It tells ECS: "Use this Docker image, give it 2GB RAM, expose port 8080,
# set these environment variables, use this IAM role for permissions."
#
# Templates allow us to reuse the same definition across environments
# by replacing variables like ${ACCOUNT_ID} with actual values.
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "ðŸ“‹ Step 5: Register Task Definitions"
echo "====================================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Processing task definition templates"
echo "   2. Replacing environment variables"
echo "   3. Registering with ECS"
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   Task Definition = Container blueprint (CPU, memory, image, env vars)"
echo "   Each service (Airflow, MLflow, etc.) has its own task definition"
echo ""

TASKDEFS_DIR="$(dirname "$0")/taskdefs"

# ============================================
# Function: Process and Register Task Definition
# ============================================
# WHAT: Replace variables in template and register with ECS
# WHY: Templates are reusable, actual values come from environment
# HOW: Use envsubst to replace ${VAR} with actual values, then register
register_task() {
    local template=$1
    local family=$2
    
    echo "Processing: $template"
    
    # Use local dir instead of /tmp/ (fixes Git Bash path mangling)
    local processed="$(dirname "$0")/.tmp/${family}.json"
    mkdir -p "$(dirname "$0")/.tmp"
    envsubst < "$template" > "$processed"
    
    # Validate JSON using python instead of jq
    if ! python -m json.tool "$processed" > /dev/null 2>&1; then
        echo -e "${RED}âŒ Invalid JSON in $template${NC}"
        cat "$processed"
        return 1
    fi
    
    # Register task definition
    TASK_ARN=$(aws ecs register-task-definition \
        --cli-input-json "file://${processed}" \
        --region "$AWS_REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    echo -e "${GREEN}âœ… Registered: $family${NC}"
    echo "   ARN: $TASK_ARN"
    echo ""
    
    export "TASK_${family//-/_}_ARN=$TASK_ARN"
    
    rm -f "$processed"
}

# ============================================
# Register All Task Definitions
# ============================================

echo "Registering task definitions..."
echo ""

# Register Airflow tasks
if [[ -f "$TASKDEFS_DIR/airflow-web.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-web.json.template" "churn-pipeline-airflow-web"
fi

if [[ -f "$TASKDEFS_DIR/airflow-scheduler.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-scheduler.json.template" "churn-pipeline-airflow-scheduler"
fi

if [[ -f "$TASKDEFS_DIR/airflow-worker.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-worker.json.template" "churn-pipeline-airflow-worker"
fi

# Register MLflow task
if [[ -f "$TASKDEFS_DIR/mlflow-tracking.json.template" ]]; then
    register_task "$TASKDEFS_DIR/mlflow-tracking.json.template" "churn-pipeline-mlflow"
fi

# Register pipeline tasks
if [[ -f "$TASKDEFS_DIR/data-pipeline.json.template" ]]; then
    register_task "$TASKDEFS_DIR/data-pipeline.json.template" "churn-pipeline-data"
fi

if [[ -f "$TASKDEFS_DIR/train-pipeline.json.template" ]]; then
    register_task "$TASKDEFS_DIR/train-pipeline.json.template" "churn-pipeline-train"
fi

if [[ -f "$TASKDEFS_DIR/inference-pipeline.json.template" ]]; then
    register_task "$TASKDEFS_DIR/inference-pipeline.json.template" "churn-pipeline-inference"
fi

# Register EC2 task definitions
echo "Registering EC2-specific task definitions..."
echo ""

if [[ -f "$TASKDEFS_DIR/airflow-web-ec2.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-web-ec2.json.template" "churn-pipeline-airflow-web-ec2"
fi

if [[ -f "$TASKDEFS_DIR/airflow-scheduler-ec2.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-scheduler-ec2.json.template" "churn-pipeline-airflow-scheduler-ec2"
fi

if [[ -f "$TASKDEFS_DIR/airflow-worker-ec2.json.template" ]]; then
    register_task "$TASKDEFS_DIR/airflow-worker-ec2.json.template" "churn-pipeline-airflow-worker-ec2"
fi

if [[ -f "$TASKDEFS_DIR/mlflow-tracking-ec2.json.template" ]]; then
    register_task "$TASKDEFS_DIR/mlflow-tracking-ec2.json.template" "churn-pipeline-mlflow-ec2"
fi

# Register Kafka tasks
echo "Registering Kafka task definitions..."
echo ""

if [[ -f "$TASKDEFS_DIR/kafka-producer.json.template" ]]; then
    register_task "$TASKDEFS_DIR/kafka-producer.json.template" "churn-pipeline-kafka-producer"
fi

if [[ -f "$TASKDEFS_DIR/kafka-inference.json.template" ]]; then
    register_task "$TASKDEFS_DIR/kafka-inference.json.template" "churn-pipeline-kafka-inference"
fi

if [[ -f "$TASKDEFS_DIR/kafka-analytics.json.template" ]]; then
    register_task "$TASKDEFS_DIR/kafka-analytics.json.template" "churn-pipeline-kafka-analytics"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Task Registration Complete!"
echo "=========================================="
echo ""
echo "Registered task definitions:"
aws ecs list-task-definitions \
    --family-prefix "churn-pipeline" \
    --region "$AWS_REGION" \
    --query 'taskDefinitionArns' \
    --output table
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./60_services.sh${NC}"
