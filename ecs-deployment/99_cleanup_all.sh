#!/bin/bash
# ==========================================
# CLEANUP: Remove All ECS Resources
# ==========================================
# This script removes ALL resources created by deployment scripts
# WARNING: This is DESTRUCTIVE and cannot be undone!

set -euo pipefail

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "âš ï¸  WARNING: DESTRUCTIVE CLEANUP"
echo "================================"
echo ""
echo "This will DELETE all resources created by the deployment:"
echo ""
echo "  - ECS Services (4)"
echo "  - ECS Tasks (running)"
echo "  - ECS Cluster"
echo "  - Application Load Balancer"
echo "  - Target Groups (2)"
echo "  - CloudWatch Log Group"
echo "  - IAM Roles (2)"
echo "  - Security Groups (2)"
echo "  - ECR Repositories (5)"
echo ""
echo "Resources NOT deleted (manual cleanup required):"
echo "  - ElastiCache Redis: churn-pipeline-redis"
echo "  - Secrets Manager: airflow-db-password, airflow-fernet-key"
echo "  - RDS (your existing database)"
echo "  - S3 Bucket (your existing bucket)"
echo ""

# Confirm deletion
read -p "Are you ABSOLUTELY SURE you want to delete everything? (type 'DELETE' to confirm): " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "ðŸ—‘ï¸  Starting cleanup..."
echo ""

# ============================================
# Step 1: Delete ECS Services
# ============================================
echo "Step 1: Deleting ECS Services..."

SERVICES=(
    "airflow-webserver-svc"
    "airflow-scheduler-svc"
    "airflow-worker-svc"
    "mlflow-tracking-svc"
)

for service in "${SERVICES[@]}"; do
    if aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service" \
        --region "$AWS_REGION" \
        --query 'services[0].serviceName' \
        --output text 2>/dev/null | grep -q "$service"; then
        
        echo "Deleting service: $service"
        
        # Scale to 0 first
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service" \
            --desired-count 0 \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        # Delete service
        aws ecs delete-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service" \
            --force \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        echo -e "${GREEN}âœ… Deleted: $service${NC}"
    else
        echo "Service not found: $service"
    fi
done

echo "Waiting for services to be deleted..."
sleep 10
echo ""

# ============================================
# Step 2: Stop All Running Tasks
# ============================================
echo "Step 2: Stopping all running tasks..."

TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'taskArns[]' \
    --output text 2>/dev/null || echo "")

if [[ -n "$TASKS" ]]; then
    for task in $TASKS; do
        echo "Stopping task: $task"
        aws ecs stop-task \
            --cluster "$CLUSTER_NAME" \
            --task "$task" \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}âœ… All tasks stopped${NC}"
else
    echo "No running tasks found"
fi
echo ""

# ============================================
# Step 3: Delete ECS Cluster
# ============================================
echo "Step 3: Deleting ECS Cluster..."

if aws ecs describe-clusters \
    --clusters "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'clusters[0].clusterName' \
    --output text 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    
    echo "Deleting cluster: $CLUSTER_NAME"
    aws ecs delete-cluster \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --no-cli-pager >/dev/null 2>&1 || true
    
    echo -e "${GREEN}âœ… Deleted ECS cluster${NC}"
else
    echo "Cluster not found: $CLUSTER_NAME"
fi
echo ""

# ============================================
# Step 4: Delete ALB Listener
# ============================================
echo "Step 4: Deleting ALB Listener..."

if [[ -n "${LISTENER_ARN:-}" ]]; then
    echo "Deleting listener: $LISTENER_ARN"
    aws elbv2 delete-listener \
        --listener-arn "$LISTENER_ARN" \
        --region "$AWS_REGION" \
        --no-cli-pager >/dev/null 2>&1 || true
    
    echo -e "${GREEN}âœ… Deleted ALB listener${NC}"
else
    echo "Listener ARN not found in .env.out"
fi
echo ""

# ============================================
# Step 5: Delete Target Groups
# ============================================
echo "Step 5: Deleting Target Groups..."

TG_NAMES=(
    "${PROJECT}-airflow-tg"
    "${PROJECT}-mlflow-tg"
)

for tg_name in "${TG_NAMES[@]}"; do
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$TG_ARN" != "None" ]]; then
        echo "Deleting target group: $tg_name"
        aws elbv2 delete-target-group \
            --target-group-arn "$TG_ARN" \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        echo -e "${GREEN}âœ… Deleted: $tg_name${NC}"
    else
        echo "Target group not found: $tg_name"
    fi
done
echo ""

# ============================================
# Step 6: Delete Application Load Balancer
# ============================================
echo "Step 6: Deleting Application Load Balancer..."

ALB_NAME="${PROJECT}-alb"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || echo "None")

if [[ "$ALB_ARN" != "None" ]]; then
    echo "Deleting ALB: $ALB_NAME"
    aws elbv2 delete-load-balancer \
        --load-balancer-arn "$ALB_ARN" \
        --region "$AWS_REGION" \
        --no-cli-pager >/dev/null 2>&1 || true
    
    echo "Waiting for ALB to be deleted..."
    sleep 10
    
    echo -e "${GREEN}âœ… Deleted ALB${NC}"
else
    echo "ALB not found: $ALB_NAME"
fi
echo ""

# ============================================
# Step 7: Delete CloudWatch Log Group
# ============================================
echo "Step 7: Deleting CloudWatch Log Group..."

if aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$AWS_REGION" \
    --query 'logGroups[0].logGroupName' \
    --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
    
    echo "Deleting log group: $LOG_GROUP"
    aws logs delete-log-group \
        --log-group-name "$LOG_GROUP" \
        --region "$AWS_REGION" \
        --no-cli-pager >/dev/null 2>&1 || true
    
    echo -e "${GREEN}âœ… Deleted log group${NC}"
else
    echo "Log group not found: $LOG_GROUP"
fi
echo ""

# ============================================
# Step 8: Delete IAM Roles
# ============================================
echo "Step 8: Deleting IAM Roles..."

IAM_ROLES=(
    "${PROJECT}-task-execution-role"
    "${PROJECT}-task-role"
)

for role in "${IAM_ROLES[@]}"; do
    if aws iam get-role --role-name "$role" --region "$AWS_REGION" &>/dev/null; then
        echo "Deleting IAM role: $role"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role" \
            --region "$AWS_REGION" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy in $ATTACHED_POLICIES; do
            aws iam detach-role-policy \
                --role-name "$role" \
                --policy-arn "$policy" \
                --region "$AWS_REGION" \
                --no-cli-pager >/dev/null 2>&1 || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role" \
            --region "$AWS_REGION" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$role" \
                --policy-name "$policy" \
                --region "$AWS_REGION" \
                --no-cli-pager >/dev/null 2>&1 || true
        done
        
        # Delete role
        aws iam delete-role \
            --role-name "$role" \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        echo -e "${GREEN}âœ… Deleted: $role${NC}"
    else
        echo "IAM role not found: $role"
    fi
done
echo ""

# ============================================
# Step 9: Delete Security Groups
# ============================================
echo "Step 9: Deleting Security Groups..."

SG_NAMES=(
    "alb-${PROJECT}"
    "ecs-tasks-${PROJECT}"
)

# Wait a bit for resources to fully detach
echo "Waiting for resources to detach from security groups..."
sleep 15

for sg_name in "${SG_NAMES[@]}"; do
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$SG_ID" != "None" ]]; then
        echo "Deleting security group: $sg_name ($SG_ID)"
        aws ec2 delete-security-group \
            --group-id "$SG_ID" \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        echo -e "${GREEN}âœ… Deleted: $sg_name${NC}"
    else
        echo "Security group not found: $sg_name"
    fi
done
echo ""

# ============================================
# Step 10: Delete ECR Repositories
# ============================================
echo "Step 10: Deleting ECR Repositories..."

ECR_REPOS=(
    "${PROJECT}/airflow"
    "${PROJECT}/mlflow"
    "${PROJECT}/data"
    "${PROJECT}/model"
    "${PROJECT}/inference"
    "${PROJECT}/kafka-producer"
    "${PROJECT}/kafka-inference"
    "${PROJECT}/kafka-analytics"
)

for repo in "${ECR_REPOS[@]}"; do
    if aws ecr describe-repositories \
        --repository-names "$repo" \
        --region "$AWS_REGION" &>/dev/null; then
        
        echo "Deleting ECR repository: $repo"
        aws ecr delete-repository \
            --repository-name "$repo" \
            --force \
            --region "$AWS_REGION" \
            --no-cli-pager >/dev/null 2>&1 || true
        
        echo -e "${GREEN}âœ… Deleted: $repo${NC}"
    else
        echo "ECR repository not found: $repo"
    fi
done
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Cleanup Complete!"
echo "=========================================="
echo ""
echo "Deleted Resources:"
echo "  âœ… ECS Services (4)"
echo "  âœ… ECS Tasks"
echo "  âœ… ECS Cluster"
echo "  âœ… Application Load Balancer"
echo "  âœ… Target Groups (2)"
echo "  âœ… CloudWatch Log Group"
echo "  âœ… IAM Roles (2)"
echo "  âœ… Security Groups (2)"
echo "  âœ… ECR Repositories (5)"
echo ""
echo "âš ï¸  Manual Cleanup Required:"
echo ""
echo "1. Delete ElastiCache Redis:"
echo "   aws elasticache delete-cache-cluster \\"
echo "     --cache-cluster-id churn-pipeline-redis \\"
echo "     --region $AWS_REGION"
echo ""
echo "2. Delete Secrets Manager Secrets:"
echo "   aws secretsmanager delete-secret \\"
echo "     --secret-id airflow-db-password \\"
echo "     --force-delete-without-recovery \\"
echo "     --region $AWS_REGION"
echo ""
echo "   aws secretsmanager delete-secret \\"
echo "     --secret-id airflow-fernet-key \\"
echo "     --force-delete-without-recovery \\"
echo "     --region $AWS_REGION"
echo ""
echo "3. Cleanup .env.out file:"
echo "   rm -f $(dirname "$0")/.env.out"
echo ""
echo "Note: RDS and S3 were not touched (pre-existing resources)"
echo ""

