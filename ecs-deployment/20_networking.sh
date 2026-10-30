#!/bin/bash
################################################################################
# SCRIPT: 20_networking.sh
# PURPOSE: Configure network security and logging for ECS deployment
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Creates Security Groups (virtual firewalls) for ECS tasks and Load Balancer
# 2. Configures firewall rules (who can talk to whom)
# 3. Creates CloudWatch Log Group for centralized logging
#
# WHY WE NEED THIS:
# ----------------
# - Security Groups act as firewalls to control network traffic
# - ECS tasks need to communicate with each other and the load balancer
# - CloudWatch Logs collects all container logs in one place for monitoring
# - Without proper security groups, services can't communicate or be accessed
#
# PREREQUISITES:
# -------------
# - 00_env.sh configured with VPC_ID and AWS_REGION
# - VPC must exist (created by AWS or manually)
# - AWS CLI configured with proper permissions
#
# STUDENT NOTE:
# ------------
# Think of Security Groups as firewall rules for your cloud resources.
# It's like setting up "who can enter your house and through which door."
# CloudWatch Logs is like a centralized logbook where all services write their logs.
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
# (Prevents AWS CLI from opening 'less' or similar pagers)
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
# (Ensures we use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment)
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables (VPC_ID, AWS_REGION, PROJECT name, etc.)
source "$(dirname "$0")/00_env.sh"

echo "ðŸ”’ Step 2: Networking Configuration"
echo "===================================="
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Creating Security Groups (firewalls)"
echo "   2. Configuring network rules"
echo "   3. Setting up CloudWatch Logs"
echo ""

# ============================================
# STEP 1: Create Security Groups
# ============================================
# WHAT: Create virtual firewalls for ECS tasks and Load Balancer
# WHY: Control which services can communicate with each other
# HOW: Use AWS EC2 API (security groups are VPC resources, not EC2-specific!)
echo "Creating security groups..."
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   Security Group = Virtual firewall with inbound/outbound rules"
echo "   Even though we use 'aws ec2' commands, these work for ECS Fargate too!"
echo ""

# ============================================
# Create Security Group for ECS Tasks
# ============================================
# WHAT: Firewall for all ECS Fargate containers
# WHY: Allows containers to talk to each other and access the internet
# HOW: Create security group with self-referencing rule (containers can talk to each other)

SG_ECS_NAME="ecs-tasks-${PROJECT}"
echo "Checking ECS security group: $SG_ECS_NAME"

# Check if security group already exists
# (Query returns "None" if not found, otherwise returns the security group ID)
SG_ECS_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_ECS_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ECS_ID" = "None" ]; then
    echo "Creating ECS tasks security group..."
    
    # Create new security group
    SG_ECS_ID=$(aws ec2 create-security-group \
        --group-name "$SG_ECS_NAME" \
        --description "Security group for ECS tasks in ${PROJECT}" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Allow all outbound traffic (containers can access internet, RDS, S3, etc.)
    # Protocol -1 means "all protocols" (TCP, UDP, ICMP, etc.)
    # CIDR 0.0.0.0/0 means "anywhere on the internet"
    aws ec2 authorize-security-group-egress \
        --group-id "$SG_ECS_ID" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Allow internal communication between ECS tasks
    # This is a "self-referencing" rule: containers in this security group
    # can talk to other containers in the same security group
    # Example: Airflow scheduler can talk to Airflow worker
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ECS_ID" \
        --protocol -1 \
        --source-group "$SG_ECS_ID" \
        --region "$AWS_REGION" \
        --no-cli-pager
    
    echo -e "${GREEN}âœ… Created ECS security group: $SG_ECS_ID${NC}"
else
    echo -e "${GREEN}âœ… ECS security group exists: $SG_ECS_ID${NC}"
fi
echo ""

# ============================================
# Create Security Group for Application Load Balancer (ALB)
# ============================================
# WHAT: Firewall for the load balancer that routes traffic to ECS tasks
# WHY: ALB needs to accept HTTP traffic from the internet and forward to containers
# HOW: Allow inbound port 80 from anywhere, outbound to anywhere

SG_ALB_NAME="alb-${PROJECT}"
echo "Checking ALB security group: $SG_ALB_NAME"

# Check if ALB security group already exists
SG_ALB_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_ALB_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ALB_ID" = "None" ]; then
    echo "Creating ALB security group..."
    
    # Create new security group for ALB
    SG_ALB_ID=$(aws ec2 create-security-group \
        --group-name "$SG_ALB_NAME" \
        --description "Security group for ALB in ${PROJECT}" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Allow inbound HTTP traffic from anywhere on the internet
    # Port 80 = HTTP (web traffic)
    # CIDR 0.0.0.0/0 = anywhere (public internet)
    # This allows users to access Airflow UI, MLflow UI, etc.
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ALB_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" \
        --no-cli-pager
    
    # Allow all outbound traffic (ALB can forward requests to ECS tasks)
    aws ec2 authorize-security-group-egress \
        --group-id "$SG_ALB_ID" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" 2>/dev/null || true
    
    echo -e "${GREEN}âœ… Created ALB security group: $SG_ALB_ID${NC}"
    echo -e "${YELLOW}âš ï¸  NOTE: ALB allows port 80 from anywhere (0.0.0.0/0)${NC}"
    echo "   This is OK for development/learning."
    echo "   In production, use HTTPS (port 443) with SSL certificate!"
else
    echo -e "${GREEN}âœ… ALB security group exists: $SG_ALB_ID${NC}"
fi
echo ""

# ============================================
# STEP 2: Create CloudWatch Log Group
# ============================================
# WHAT: Centralized log storage for all ECS containers
# WHY: Collect logs from all services in one place for monitoring and debugging
# HOW: Create a CloudWatch Logs group where ECS will send container logs
echo "Creating CloudWatch Logs group..."
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   CloudWatch Logs = Centralized logging service"
echo "   All container stdout/stderr will be sent here"
echo "   You can view logs in AWS Console or via AWS CLI"
echo ""

if aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$AWS_REGION" \
    --query 'logGroups[0].logGroupName' \
    --output text | grep -q "$LOG_GROUP"; then
    echo -e "${GREEN}âœ… Log group exists: $LOG_GROUP${NC}"
else
    aws logs create-log-group \
        --log-group-name "$LOG_GROUP" \
        --region "$AWS_REGION"
    
    # Set retention to 7 days
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP" \
        --retention-in-days 7 \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}âœ… Created log group: $LOG_GROUP${NC}"
fi
echo ""

# ============================================
# Step 3: Update .env.out
# ============================================
echo "ðŸ’¾ Saving outputs..."

cat >> "$(dirname "$0")/.env.out" << EOF

# Security Groups (from 20_networking.sh)
export SG_ECS_ID="${SG_ECS_ID}"
export SG_ALB_ID="${SG_ALB_ID}"
export LOG_GROUP="${LOG_GROUP}"
EOF

echo -e "${GREEN}âœ… Saved to .env.out${NC}"
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Networking Setup Complete!"
echo "=========================================="
echo ""
echo "Security Groups:"
echo "  âœ… ECS Tasks: $SG_ECS_ID"
echo "  âœ… ALB:       $SG_ALB_ID"
echo ""
echo "CloudWatch Logs:"
echo "  âœ… Log Group: $LOG_GROUP"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./30_iam.sh${NC}"
