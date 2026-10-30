#!/bin/bash
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

set -euo pipefail
export AWS_PAGER=""
unset AWS_PROFILE 2>/dev/null || true

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/00_env.sh"
[[ -f "${SCRIPT_DIR}/.env.out" ]] && source "${SCRIPT_DIR}/.env.out"

# Use local tmp dir instead of /tmp/ (fixes Git Bash path mangling on Windows)
TMPDIR="${SCRIPT_DIR}/.tmp"
mkdir -p "$TMPDIR"

echo "ðŸ” Step 3: IAM Roles Configuration"
echo "==================================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Creating Task Execution Role (for ECS platform)"
echo "   2. Creating Task Role (for your application code)"
echo "   3. Attaching policies for S3, RDS, CloudWatch access"
echo ""

# ============================================
# STEP 1: Create Task Execution Role
# ============================================
echo "Creating Task Execution Role..."
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   Task Execution Role = Permissions for ECS (not your code)"
echo "   Allows ECS to: pull Docker images, write CloudWatch logs, read secrets"
echo ""

EXEC_ROLE_NAME="${PROJECT}-task-execution-role"

if aws iam get-role --role-name "$EXEC_ROLE_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}âœ… Task execution role exists: $EXEC_ROLE_NAME${NC}"
    EXEC_ROLE_ARN=$(aws iam get-role --role-name "$EXEC_ROLE_NAME" --region "$AWS_REGION" --query 'Role.Arn' --output text)
else
    # Write trust policy to LOCAL path (not /tmp/)
    cat > "${TMPDIR}/task-execution-trust.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    EXEC_ROLE_ARN=$(aws iam create-role \
        --role-name "$EXEC_ROLE_NAME" \
        --assume-role-policy-document "file://${TMPDIR}/task-execution-trust.json" \
        --region "$AWS_REGION" \
        --query 'Role.Arn' \
        --output text)

    aws iam attach-role-policy \
        --role-name "$EXEC_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
        --region "$AWS_REGION"

    cat > "${TMPDIR}/exec-role-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": [
        "${RDS_PASSWORD_SECRET_ARN}",
        "${FERNET_KEY_SECRET_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$EXEC_ROLE_NAME" \
        --policy-name "ExecutionRolePolicy" \
        --policy-document "file://${TMPDIR}/exec-role-policy.json" \
        --region "$AWS_REGION"

    echo -e "${GREEN}âœ… Created task execution role: $EXEC_ROLE_ARN${NC}"
fi
echo ""

# ============================================
# STEP 2: Create Task Role
# ============================================
echo "Creating Task Role..."

TASK_ROLE_NAME="${PROJECT}-task-role"

if aws iam get-role --role-name "$TASK_ROLE_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}âœ… Task role exists: $TASK_ROLE_NAME${NC}"
    TASK_ROLE_ARN=$(aws iam get-role --role-name "$TASK_ROLE_NAME" --region "$AWS_REGION" --query 'Role.Arn' --output text)
else
    TASK_ROLE_ARN=$(aws iam create-role \
        --role-name "$TASK_ROLE_NAME" \
        --assume-role-policy-document "file://${TMPDIR}/task-execution-trust.json" \
        --region "$AWS_REGION" \
        --query 'Role.Arn' \
        --output text)

    cat > "${TMPDIR}/task-role-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:ListBucket","s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": [
        "${RDS_PASSWORD_SECRET_ARN}",
        "${FERNET_KEY_SECRET_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream","logs:PutLogEvents","logs:GetLogEvents","logs:DescribeLogStreams"],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
    },
    {
      "Effect": "Allow",
      "Action": ["ecs:RunTask","ecs:DescribeTasks","ecs:StopTask"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["iam:PassRole"],
      "Resource": [
        "${EXEC_ROLE_ARN}",
        "arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT}-task-role"
      ]
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$TASK_ROLE_NAME" \
        --policy-name "TaskRolePolicy" \
        --policy-document "file://${TMPDIR}/task-role-policy.json" \
        --region "$AWS_REGION"

    echo -e "${GREEN}âœ… Created task role: $TASK_ROLE_ARN${NC}"
fi
echo ""

# ============================================
# Step 3: Update .env.out
# ============================================
echo "ðŸ’¾ Saving outputs..."

cat >> "${SCRIPT_DIR}/.env.out" << EOF

# IAM Roles (from 30_iam.sh)
export EXEC_ROLE_ARN="${EXEC_ROLE_ARN}"
export TASK_ROLE_ARN="${TASK_ROLE_ARN}"
export EXEC_ROLE_NAME="${EXEC_ROLE_NAME}"
export TASK_ROLE_NAME="${TASK_ROLE_NAME}"
EOF

echo -e "${GREEN}âœ… Saved to .env.out${NC}"

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "=========================================="
echo "ðŸŽ‰ IAM Setup Complete!"
echo "=========================================="
echo ""
echo "Task Execution Role:"
echo "  âœ… Name: $EXEC_ROLE_NAME"
echo "  âœ… ARN:  $EXEC_ROLE_ARN"
echo ""
echo "Task Role:"
echo "  âœ… Name: $TASK_ROLE_NAME"
echo "  âœ… ARN:  $TASK_ROLE_ARN"
echo ""
echo "Permissions:"
echo "  âœ… ECR pull"
  echo "  âœ… CloudWatch Logs"
  echo "  âœ… Secrets Manager"
echo "  âœ… S3 access to ${S3_BUCKET}"
echo "  âœ… ECS RunTask (for Airflow)"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./40_cluster_alb.sh${NC}"