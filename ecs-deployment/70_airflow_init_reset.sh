#!/bin/bash
# ==========================================
# Initialize Airflow with FULL RESET
# ==========================================
# This script ALWAYS clears all DAG history
# Use for: Clean slate, testing, dev environments

set -euo pipefail

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "ðŸ”§ Step 7: Initialize Airflow (WITH RESET)"
echo "==========================================="
echo ""
echo "âš ï¸  WARNING: This will DELETE ALL DAG run history!"
echo ""
read -p "Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "âŒ Aborted"
    exit 0
fi
echo ""

# ============================================
# Reset Database (Clears ALL history)
# ============================================
echo "ðŸ—‘ï¸  Resetting Airflow database..."

TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "churn-pipeline-airflow-web" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[\"${SG_ECS_ID}\"],assignPublicIp=ENABLED}" \
    --overrides '{"containerOverrides":[{"name":"web","command":["bash","-c","airflow db reset --yes"]}]}' \
    --region "$AWS_REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: $TASK_ARN"
echo "Waiting for DB reset to complete..."

aws ecs wait tasks-stopped \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION"

EXIT_CODE=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [[ "$EXIT_CODE" == "0" ]]; then
    echo -e "${GREEN}âœ… Database reset completed${NC}"
else
    echo -e "${RED}âŒ Database reset failed with exit code: $EXIT_CODE${NC}"
    echo "Check CloudWatch logs: /ecs/${PROJECT}"
    exit 1
fi
echo ""

# ============================================
# Run DB Migration (after reset)
# ============================================
echo "Running Airflow DB migration..."

TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "churn-pipeline-airflow-web" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[\"${SG_ECS_ID}\"],assignPublicIp=ENABLED}" \
    --overrides '{"containerOverrides":[{"name":"web","command":["bash","-c","airflow db migrate"]}]}' \
    --region "$AWS_REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: $TASK_ARN"
echo "Waiting for DB migration to complete..."

aws ecs wait tasks-stopped \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION"

EXIT_CODE=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [[ "$EXIT_CODE" == "0" ]]; then
    echo -e "${GREEN}âœ… DB migration completed${NC}"
else
    echo -e "${RED}âŒ DB migration failed with exit code: $EXIT_CODE${NC}"
    exit 1
fi
echo ""

# ============================================
# Create Admin User
# ============================================
echo "Creating Airflow admin user..."

TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "churn-pipeline-airflow-web" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[\"${SG_ECS_ID}\"],assignPublicIp=ENABLED}" \
    --overrides "{\"containerOverrides\":[{\"name\":\"web\",\"command\":[\"bash\",\"-c\",\"airflow users create --username ${AIRFLOW_ADMIN_USER} --password ${AIRFLOW_ADMIN_PASSWORD} --firstname Admin --lastname User --role Admin --email ${AIRFLOW_ADMIN_EMAIL}\"]}]}" \
    --region "$AWS_REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: $TASK_ARN"
echo "Waiting for user creation to complete..."

aws ecs wait tasks-stopped \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION"

EXIT_CODE=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [[ "$EXIT_CODE" == "0" ]]; then
    echo -e "${GREEN}âœ… Admin user created${NC}"
else
    echo -e "${RED}âŒ User creation failed with exit code: $EXIT_CODE${NC}"
    exit 1
fi
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Airflow Reset & Initialization Complete!"
echo "=========================================="
echo ""
echo "All DAG history has been cleared!"
echo "Airflow database is fresh and ready to use!"
echo ""
echo "Access Information:"
echo "  ðŸŒ URL:      http://$ALB_DNS"
echo "  ðŸ‘¤ Username: $AIRFLOW_ADMIN_USER"
echo "  ðŸ”‘ Password: $AIRFLOW_ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./80_airflow_vars.sh${NC}"
echo ""

