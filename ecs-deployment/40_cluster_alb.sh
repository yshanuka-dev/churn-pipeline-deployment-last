#!/bin/bash
################################################################################
# SCRIPT: 40_cluster_alb.sh
# PURPOSE: Create ECS Cluster and Application Load Balancer
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Creates ECS Fargate cluster (container orchestration platform)
# 2. Creates Application Load Balancer (ALB) to route traffic
# 3. Creates Target Groups for each service (Airflow, MLflow, Kafka)
# 4. Configures health checks and routing rules
#
# WHY WE NEED THIS:
# ----------------
# - ECS Cluster is where all containers run (like a "datacenter" for containers)
# - ALB acts as a single entry point, routing traffic to correct services
# - Target Groups define which containers receive traffic for each service
# - Health checks ensure only healthy containers receive traffic
#
# PREREQUISITES:
# -------------
# - 20_networking.sh completed (security groups created)
# - 30_iam.sh completed (IAM roles created)
# - VPC with public subnets configured in 00_env.sh
#
# STUDENT NOTE:
# ------------
# Think of ECS Cluster as a "container farm" where all your services live.
# The ALB is like a smart receptionist that directs visitors (HTTP requests)
# to the right office (container). Target Groups are like department labels.
#
# Example: Request to /airflow â†’ ALB â†’ Airflow Target Group â†’ Airflow Container
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "ðŸš€ Step 4: ECS Cluster + ALB Setup"
echo "===================================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Creating ECS Fargate Cluster"
echo "   2. Creating Application Load Balancer (ALB)"
echo "   3. Creating Target Groups for routing"
echo "   4. Configuring health checks"
echo ""

# ============================================
# STEP 1: Create ECS Cluster
# ============================================
# WHAT: Container orchestration platform (Fargate = serverless)
# WHY: Manages running containers, scaling, health monitoring
# HOW: Use ECS API to create cluster with Fargate capacity provider
echo "Creating ECS cluster..."
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   ECS Cluster = Platform where all containers run"
echo "   Fargate = Serverless (no EC2 instances to manage!)"
echo "   AWS handles all infrastructure automatically"
echo ""

if aws ecs describe-clusters \
    --clusters "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'clusters[0].clusterName' \
    --output text | grep -q "$CLUSTER_NAME"; then
    echo -e "${GREEN}âœ… ECS cluster exists: $CLUSTER_NAME${NC}"
else
    aws ecs create-cluster \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --no-cli-pager
    
    echo -e "${GREEN}âœ… Created ECS cluster: $CLUSTER_NAME${NC}"
fi
echo ""

# ============================================
# Step 2: Create Application Load Balancer
# ============================================
echo "Creating Application Load Balancer..."

ALB_NAME="${PROJECT}-alb"

# Check if ALB exists
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || echo "None")

if [ "$ALB_ARN" != "None" ]; then
    echo -e "${GREEN}âœ… ALB exists: $ALB_NAME${NC}"
    
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
else
    # Parse subnets from JSON array
    SUBNET_IDS=$(echo "$PUBLIC_SUBNETS" | jq -r '.[]' | tr '\n' ' ')
    
    # Create ALB
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets $SUBNET_IDS \
        --security-groups "$SG_ALB_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Get DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo -e "${GREEN}âœ… Created ALB: $ALB_NAME${NC}"
    echo "   DNS: $ALB_DNS"
fi
echo ""

# ============================================
# Step 3: Create Target Group
# ============================================
echo "Creating Target Group for Airflow..."

TG_NAME="${PROJECT}-airflow-tg"

# Check if target group exists
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "None")

if [ "$TG_ARN" != "None" ]; then
    echo -e "${GREEN}âœ… Target group exists: $TG_NAME${NC}"
else
    # Create target group
    TG_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo -e "${GREEN}âœ… Created target group: $TG_NAME${NC}"
fi
echo ""

# ============================================
# Step 4: Create Listener
# ============================================
echo "Creating ALB Listener..."

# Check if listener exists
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region "$AWS_REGION" \
    --query 'Listeners[0].ListenerArn' \
    --output text 2>/dev/null || echo "None")

if [ "$LISTENER_ARN" != "None" ]; then
    echo -e "${GREEN}âœ… Listener exists${NC}"
else
    # Create listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
        --region "$AWS_REGION" \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    echo -e "${GREEN}âœ… Created listener on port 80${NC}"
fi
echo ""

# ============================================
# Step 5: Create MLflow Target Group
# ============================================
echo "Creating Target Group for MLflow..."

MLFLOW_TG_NAME="${PROJECT}-mlflow-tg"

# Check if target group exists
MLFLOW_TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$MLFLOW_TG_NAME" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "None")

if [ "$MLFLOW_TG_ARN" != "None" ]; then
    echo -e "${GREEN}âœ… MLflow target group exists: $MLFLOW_TG_NAME${NC}"
else
    # Create target group
    MLFLOW_TG_ARN=$(aws elbv2 create-target-group \
        --name "$MLFLOW_TG_NAME" \
        --protocol HTTP \
        --port 5001 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path /health \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo -e "${GREEN}âœ… Created MLflow target group: $MLFLOW_TG_NAME${NC}"
fi
echo ""

# ============================================
# Step 6: Update .env.out
# ============================================
echo "ðŸ’¾ Saving outputs..."

cat >> "$(dirname "$0")/.env.out" << EOF

# ECS Cluster + ALB (from 40_cluster_alb.sh)
export CLUSTER_NAME="${CLUSTER_NAME}"
export ALB_ARN="${ALB_ARN}"
export ALB_DNS="${ALB_DNS}"
export TG_ARN="${TG_ARN}"
export MLFLOW_TG_ARN="${MLFLOW_TG_ARN}"
export LISTENER_ARN="${LISTENER_ARN}"
EOF

echo -e "${GREEN}âœ… Saved to .env.out${NC}"
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ ECS Cluster + ALB Setup Complete!"
echo "=========================================="
echo ""
echo "ECS Cluster:"
echo "  âœ… Name: $CLUSTER_NAME"
echo ""
echo "Application Load Balancer:"
echo "  âœ… Name: $ALB_NAME"
echo "  âœ… DNS:  $ALB_DNS"
echo "  âœ… ARN:  $ALB_ARN"
echo ""
echo "Target Groups:"
echo "  âœ… Airflow: $TG_NAME"
echo "  âœ… MLflow:  $MLFLOW_TG_NAME"
echo ""
echo "Access URLs (after services are running):"
echo "  ðŸŒ Airflow UI: http://$ALB_DNS"
echo "  ðŸŒ MLflow UI:  http://$ALB_DNS:5001"
echo ""
echo -e "${YELLOW}âš ï¸  Note: ALB is publicly accessible. Restrict access in production!${NC}"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./50_register_tasks.sh${NC}"
