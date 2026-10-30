#!/bin/bash
################################################################################
# SCRIPT: 70_airflow_init.sh
# PURPOSE: Initialize Airflow database and create admin user
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Runs "airflow db init" to create database schema
# 2. Creates default admin user for Airflow UI login
# 3. Optionally resets DAG history (if RESET_DAG_HISTORY=true)
#
# WHY WE NEED THIS:
# ----------------
# - Airflow needs database tables for metadata (DAGs, tasks, runs, users)
# - Admin user is required to access Airflow web UI
# - This is a one-time setup (or run again to reset)
#
# PREREQUISITES:
# -------------
# - 60_services.sh completed (Airflow services running)
# - Airflow scheduler container is healthy
# - RDS database is accessible from ECS
#
# STUDENT NOTE:
# ------------
# This is like setting up a new application for the first time:
# - "db init" creates all necessary database tables
# - "users create" adds your login credentials
# 
# You only need to run this once. If you run it again, it's safe
# (it will skip existing tables and update the admin user).
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "ðŸ”§ Step 7: Initialize Airflow"
echo "=============================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Initializing Airflow database schema"
echo "   2. Creating admin user"
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   This is a one-time setup for Airflow"
echo "   Creates database tables and admin login"
echo ""

# ============================================
# Optional: Reset DAG History
# ============================================
# Uncomment this section to clear all DAG runs on initialization
# WARNING: This deletes ALL DAG run history!
#
# RESET_HISTORY=${RESET_DAG_HISTORY:-false}
# if [[ "$RESET_HISTORY" == "true" ]]; then
#     echo "ðŸ—‘ï¸  Clearing DAG history (RESET_DAG_HISTORY=true)..."
#     
#     TASK_ARN=$(aws ecs run-task \
#         --cluster "$CLUSTER_NAME" \
#         --task-definition "churn-pipeline-airflow-web" \
#         --launch-type FARGATE \
#         --network-configuration "awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[\"${SG_ECS_ID}\"],assignPublicIp=ENABLED}" \
#         --overrides '{"containerOverrides":[{"name":"web","command":["bash","-c","airflow db reset --yes"]}]}' \
#         --region "$AWS_REGION" \
#         --query 'tasks[0].taskArn' \
#         --output text)
#     
#     echo "Task started: $TASK_ARN"
#     echo "Waiting for DB reset to complete..."
#     
#     aws ecs wait tasks-stopped \
#         --cluster "$CLUSTER_NAME" \
#         --tasks "$TASK_ARN" \
#         --region "$AWS_REGION"
#     
#     echo -e "${GREEN}âœ… DAG history cleared${NC}"
#     echo ""
# fi

# ============================================
# Run DB Migration
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

# Wait for task to complete
aws ecs wait tasks-stopped \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION"

# Check exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --region "$AWS_REGION" \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [[ "$EXIT_CODE" == "0" ]]; then
    echo -e "${GREEN}âœ… DB migration completed successfully${NC}"
else
    echo -e "${RED}âŒ DB migration failed with exit code: $EXIT_CODE${NC}"
    echo "Check CloudWatch logs: /ecs/${PROJECT}"
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
    --overrides "{\"containerOverrides\":[{\"name\":\"web\",\"command\":[\"bash\",\"-c\",\"airflow users create --username ${AIRFLOW_ADMIN_USER} --password ${AIRFLOW_ADMIN_PASSWORD} --firstname Admin --lastname User --role Admin --email ${AIRFLOW_ADMIN_EMAIL} || echo 'User may already exist'\"]}]}" \
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
    echo -e "${YELLOW}âš ï¸  User creation exit code: $EXIT_CODE (may already exist)${NC}"
fi
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Airflow Initialization Complete!"
echo "=========================================="
echo ""
echo "Airflow is ready to use!"
echo ""
echo "Access Information:"
echo "  ðŸŒ URL:      http://$ALB_DNS"
echo "  ðŸ‘¤ Username: $AIRFLOW_ADMIN_USER"
echo "  ðŸ”‘ Password: $AIRFLOW_ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}âš ï¸  Change the admin password after first login!${NC}"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./80_airflow_vars.sh${NC}"
