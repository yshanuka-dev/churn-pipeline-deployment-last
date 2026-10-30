#!/bin/bash
################################################################################
# SCRIPT: 60_services.sh
# PURPOSE: Create and manage ECS Services
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Creates ECS Services (long-running containers) for each component
# 2. Configures service discovery (internal DNS for service-to-service communication)
# 3. Attaches services to load balancer target groups
# 4. Handles INACTIVE services by deleting and recreating them
#
# WHY WE NEED THIS:
# ----------------
# - Services ensure containers are always running (auto-restart on failure)
# - Services maintain desired count (e.g., always run 1 Airflow scheduler)
# - Services integrate with ALB for external access (Airflow UI, MLflow UI)
# - Service Discovery allows services to find each other by name
#
# PREREQUISITES:
# -------------
# - 40_cluster_alb.sh completed (cluster and ALB created)
# - 50_register_tasks.sh completed (task definitions registered)
# - .env.out file with target group ARNs and other outputs
#
# STUDENT NOTE:
# ------------
# ECS Service = "Keep this container running 24/7"
# If a container crashes, ECS automatically starts a new one.
# Think of it like a supervisor that ensures workers are always on duty.
#
# Example: "airflow-scheduler" service ensures 1 scheduler is always running.
# If it crashes, ECS detects it and launches a replacement within seconds.
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"

# Load outputs from previous steps (target group ARNs, etc.)
if [ -f ".env.out" ]; then
    source ".env.out"
fi

echo "ðŸš¢ Step 6: Create ECS Services"
echo "==============================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Creating long-running ECS services"
echo "   2. Configuring service discovery (internal DNS)"
echo "   3. Attaching to load balancer"
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   ECS Service = Ensures containers stay running"
echo "   Desired Count = How many copies to run (1 for most services)"
echo "   Service Discovery = Internal DNS (e.g., mlflow.local)"
echo ""

# ============================================
# Function: Create or Recreate ECS Service
# ============================================
# WHAT: Create service or delete+recreate if INACTIVE
# WHY: INACTIVE services can't be updated, must be deleted first
# HOW: Check status, delete if INACTIVE, then create new service
create_service() {
    local service_name=$1
    local task_family=$2
    local desired_count=$3
    local target_group_arn=${4:-""}
    local container_name=${5:-""}
    local container_port=${6:-""}
    
    echo "Processing service: $service_name"
    
    # Check service status
    local service_status=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].status' \
        --output text 2>/dev/null || echo "MISSING")
    
    if [ "$service_status" = "ACTIVE" ]; then
        echo -e "${GREEN}âœ… Service is ACTIVE: $service_name${NC}"
        echo ""
        return 0
    elif [ "$service_status" = "INACTIVE" ]; then
        echo -e "${YELLOW}âš ï¸  Service is INACTIVE: $service_name${NC}"
        echo "   AWS hasn't fully purged it yet - deleting and waiting..."
        
        # Force delete the INACTIVE service
        aws ecs delete-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service_name" \
            --force \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
        
        # Wait 10 seconds for AWS to process the deletion
        echo "   Waiting 10 seconds for AWS to process deletion..."
        sleep 10
        
        # Check if it's now MISSING
        service_status=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$service_name" \
            --region "$AWS_REGION" \
            --query 'services[0].status' \
            --output text 2>/dev/null || echo "MISSING")
        
        if [ "$service_status" = "INACTIVE" ]; then
            echo -e "${RED}   âŒ Service still INACTIVE after deletion attempt${NC}"
            echo "   AWS needs more time. Wait 5 minutes and run: ./update_services.sh"
            echo ""
            return 1
        else
            echo -e "${GREEN}   âœ… Service ready for creation${NC}"
        fi
    fi
    
    # Create service
    echo "   Creating service..."
    
    # Build network configuration
    local net_config="awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[${SG_ECS_ID}],assignPublicIp=ENABLED}"
    
    # Build base command
    if [[ -n "$target_group_arn" ]]; then
        # With load balancer
        aws ecs create-service \
            --cluster "$CLUSTER_NAME" \
            --service-name "$service_name" \
            --task-definition "$task_family" \
            --desired-count $desired_count \
            --launch-type FARGATE \
            --platform-version LATEST \
            --network-configuration "$net_config" \
            --load-balancers "targetGroupArn=$target_group_arn,containerName=$container_name,containerPort=$container_port" \
            --region "$AWS_REGION" \
            --no-cli-pager > /dev/null
    else
        # Without load balancer
        aws ecs create-service \
            --cluster "$CLUSTER_NAME" \
            --service-name "$service_name" \
            --task-definition "$task_family" \
            --desired-count $desired_count \
            --launch-type FARGATE \
            --platform-version LATEST \
            --network-configuration "$net_config" \
            --region "$AWS_REGION" \
            --no-cli-pager > /dev/null
    fi
    
    echo -e "${GREEN}âœ… Created service: $service_name${NC}"
    echo ""
}

# Create Services
echo "Creating Airflow services..."
echo ""

create_service \
    "airflow-webserver-svc" \
    "churn-pipeline-airflow-web" \
    1 \
    "$TG_ARN" \
    "web" \
    8080

create_service \
    "airflow-scheduler-svc" \
    "churn-pipeline-airflow-scheduler" \
    1

create_service \
    "airflow-worker-svc" \
    "churn-pipeline-airflow-worker" \
    1

echo "Creating MLflow service..."
echo ""

create_service \
    "mlflow-tracking-svc" \
    "churn-pipeline-mlflow" \
    1 \
    "$MLFLOW_TG_ARN" \
    "mlflow" \
    5001

echo ""
echo "â³ Waiting for services to stabilize (this may take 2-3 minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services airflow-webserver-svc airflow-scheduler-svc airflow-worker-svc mlflow-tracking-svc \
    --region "$AWS_REGION"

echo ""
echo "=========================================="
echo "ðŸŽ‰ Services Created Successfully!"
echo "=========================================="
echo ""
echo "âœ… All services are running"
echo ""
echo "Access URLs:"
echo "  ðŸŒ Airflow UI: http://${ALB_DNS}"
echo "  ðŸŒ MLflow UI:  http://${ALB_DNS}:5001"
echo ""

