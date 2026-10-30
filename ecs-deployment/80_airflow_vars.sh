#!/bin/bash
################################################################################
# SCRIPT: 80_airflow_vars.sh
# PURPOSE: Configure Airflow variables for ML pipeline integration
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Sets Airflow variables (key-value pairs) via CLI
# 2. Configures AWS credentials and S3 bucket names
# 3. Configures MLflow tracking URI
# 4. Runs commands inside Airflow scheduler container using ECS exec
#
# WHY WE NEED THIS:
# ----------------
# - Airflow DAGs need to know where to find S3 buckets, MLflow server, etc.
# - Variables are stored in Airflow's database (not hardcoded in DAGs)
# - This allows changing configuration without modifying code
#
# PREREQUISITES:
# -------------
# - 70_airflow_init.sh completed (Airflow initialized)
# - Airflow scheduler service is running and healthy
# - AWS CLI with ECS exec permissions
#
# STUDENT NOTE:
# ------------
# Airflow Variables = Configuration settings for your DAGs
# Think of them like environment variables, but stored in Airflow's database.
#
# Example: Instead of hardcoding S3 bucket name in your DAG, you use:
#   bucket = Variable.get("s3_bucket")
#
# This way, you can change the bucket without modifying code!
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "âš™ï¸  Step 8: Set Airflow Variables"
echo "=================================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Setting Airflow configuration variables"
echo "   2. Configuring S3 bucket names"
echo "   3. Configuring MLflow tracking URI"
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   Airflow Variables = Config settings stored in database"
echo "   DAGs read these instead of hardcoding values"
echo ""

# ============================================
# STEP 1: Set Variables via ECS Task
# ============================================
# WHAT: Run "airflow variables set" commands inside scheduler container
# WHY: Variables must be set from within Airflow environment
# HOW: Use ECS exec to run commands in running container
echo "Setting Airflow variables..."

# Create commands file
cat > /tmp/airflow_vars.sh << EOF
#!/bin/bash
set -e

echo "Setting Airflow variables..."

airflow variables set ECS_CLUSTER "$CLUSTER_NAME"
airflow variables set ECS_PRIVATE_SUBNETS '${PRIVATE_SUBNETS}'
airflow variables set ECS_SECURITY_GROUPS '["${SG_ECS_ID}"]'
airflow variables set S3_BUCKET "$S3_BUCKET"
airflow variables set MLFLOW_URL "$MLFLOW_URL"
airflow variables set AWS_REGION "$AWS_REGION"
airflow variables set TASK_EXECUTION_ROLE_ARN "$EXEC_ROLE_ARN"
airflow variables set TASK_ROLE_ARN "$TASK_ROLE_ARN"

# Task definition ARNs
airflow variables set TASK_DEF_DATA "churn-pipeline-data"
airflow variables set TASK_DEF_TRAIN "churn-pipeline-train"
airflow variables set TASK_DEF_INFERENCE "churn-pipeline-inference"

echo "âœ… All variables set!"
airflow variables list
EOF

# Base64 encode the script
VARS_SCRIPT=$(cat /tmp/airflow_vars.sh | base64)

# Run task to set variables
echo "Running task to set variables..."

TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "churn-pipeline-airflow-web" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=${PRIVATE_SUBNETS},securityGroups=[\"${SG_ECS_ID}\"],assignPublicIp=ENABLED}" \
    --overrides "{\"containerOverrides\":[{\"name\":\"web\",\"command\":[\"bash\",\"-c\",\"echo ${VARS_SCRIPT} | base64 -d | bash\"]}]}" \
    --region "$AWS_REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: $TASK_ARN"
echo "Waiting for task to complete..."

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
    echo -e "${GREEN}âœ… Variables set successfully${NC}"
else
    echo -e "${RED}âŒ Failed to set variables (exit code: $EXIT_CODE)${NC}"
    echo "Check CloudWatch logs: /ecs/${PROJECT}"
    exit 1
fi
echo ""

rm -f /tmp/airflow_vars.sh

# ============================================
# Print Manual Commands (Backup)
# ============================================
echo ""
echo "=========================================="
echo "ðŸ“ Manual Variable Commands (if needed)"
echo "=========================================="
echo ""
echo "If automated setup failed, run these in Airflow UI -> Admin -> Variables:"
echo ""
cat << EOF
ECS_CLUSTER = $CLUSTER_NAME
ECS_PRIVATE_SUBNETS = ${PRIVATE_SUBNETS}
ECS_SECURITY_GROUPS = ["${SG_ECS_ID}"]
S3_BUCKET = $S3_BUCKET
MLFLOW_URL = $MLFLOW_URL
AWS_REGION = $AWS_REGION
TASK_EXECUTION_ROLE_ARN = $EXEC_ROLE_ARN
TASK_ROLE_ARN = $TASK_ROLE_ARN
TASK_DEF_DATA = churn-pipeline-data
TASK_DEF_TRAIN = churn-pipeline-train
TASK_DEF_INFERENCE = churn-pipeline-inference
EOF
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Deployment Complete!"
echo "=========================================="
echo ""
echo "âœ… All infrastructure deployed"
echo "âœ… Services running"
echo "âœ… Airflow initialized"
echo "âœ… Variables configured"
echo ""
echo "ðŸŒ Access Your Services:"
echo ""
echo "Airflow UI:"
echo "  URL:      http://$ALB_DNS"
echo "  Username: $AIRFLOW_ADMIN_USER"
echo "  Password: $AIRFLOW_ADMIN_PASSWORD"
echo ""
echo "MLflow UI:"
echo "  URL:      http://$ALB_DNS:5001"
echo ""
echo "ðŸ“‹ Next Steps:"
echo "  1. Login to Airflow"
echo "  2. Upload your DAGs to the webserver"
echo "  3. Enable DAGs in the UI"
echo "  4. Monitor CloudWatch logs: /ecs/${PROJECT}"
echo ""
echo "ðŸ”§ Useful Commands:"
echo "  # View services"
echo "  aws ecs list-services --cluster $CLUSTER_NAME --region $AWS_REGION"
echo ""
echo "  # View running tasks"
echo "  aws ecs list-tasks --cluster $CLUSTER_NAME --region $AWS_REGION"
echo ""
echo "  # View logs"
echo "  aws logs tail /ecs/${PROJECT} --follow --region $AWS_REGION"
echo ""
