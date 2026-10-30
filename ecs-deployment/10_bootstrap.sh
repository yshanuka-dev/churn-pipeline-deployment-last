#!/bin/bash
################################################################################
# SCRIPT: 10_bootstrap.sh
# PURPOSE: Create ECR repositories and push Docker images to AWS
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Creates private Docker registries (ECR repositories) in AWS
# 2. Logs into AWS ECR (like "docker login" but for AWS)
# 3. Tags your local Docker images with ECR URLs
# 4. Pushes images to ECR so ECS can pull them
#
# WHY WE NEED THIS:
# ----------------
# - ECS Fargate can't access Docker images on your local machine
# - ECR (Elastic Container Registry) is AWS's private Docker registry
# - It's like Docker Hub, but private and integrated with AWS
#
# PREREQUISITES:
# -------------
# - Docker images must be built locally first (run_ecs.sh does this)
# - AWS credentials configured
# - 00_env.sh configured with ACCOUNT_ID and AWS_REGION
#
# STUDENT NOTE:
# ------------
# Think of this as uploading your Docker images to AWS's cloud storage
# so that ECS can download and run them.
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
# (Prevents AWS CLI from opening a pager like 'less')
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
# (Ensures we use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment)
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables (ACCOUNT_ID, AWS_REGION, image names, etc.)
source "$(dirname "$0")/00_env.sh"

echo "ðŸš€ Step 1: Bootstrap ECR Repositories"
echo "======================================"
echo ""
echo "ðŸ“š WHAT WE'RE DOING:"
echo "   1. Creating ECR repositories (private Docker registries)"
echo "   2. Logging into ECR"
echo "   3. Tagging local Docker images"
echo "   4. Pushing images to ECR"
echo ""

# ============================================
# DEFINE: ECR Repository Names
# ============================================
# These are the names of the Docker registries we'll create in AWS
# Format: project-name/service-name
# Example: churn-pipeline/airflow
REPOS=(
    "churn-pipeline/airflow"     # Airflow orchestration
    "churn-pipeline/mlflow"      # MLflow tracking server
    "churn-pipeline/data"        # Data preprocessing pipeline
    "churn-pipeline/model"       # Model training pipeline
    "churn-pipeline/inference"   # Inference pipeline
)

# ============================================
# DEFINE: Local Docker Image Tags
# ============================================
# These are the names of Docker images on your local machine
# They were built by docker-compose or run_ecs.sh
LOCAL_IMAGES=(
    "$IMG_AIRFLOW_LOCAL"    # e.g., churn-pipeline/airflow:2.8.1-amazon
    "$IMG_MLFLOW_LOCAL"     # e.g., churn-pipeline/mlflow:latest
    "$IMG_DATA_LOCAL"       # e.g., churn-pipeline/data:latest
    "$IMG_TRAIN_LOCAL"      # e.g., churn-pipeline/model:latest
    "$IMG_INFER_LOCAL"      # e.g., churn-pipeline/inference:latest
)

# ============================================
# STEP 1: Create ECR Repositories
# ============================================
# WHAT: Create private Docker registries in AWS
# WHY: ECS needs a place to pull Docker images from
# HOW: Use AWS CLI to create ECR repositories
echo "ðŸ“¦ Creating ECR repositories..."
echo ""
echo "ðŸ’¡ STUDENT NOTE:"
echo "   ECR = Elastic Container Registry (AWS's private Docker Hub)"
echo "   Each repository stores one type of Docker image"
echo ""

# Loop through each repository name
for repo in "${REPOS[@]}"; do
    echo "Checking repository: $repo"
    
    # Check if repository already exists
    # (aws ecr describe-repositories returns error if not found, hence &>/dev/null)
    if aws ecr describe-repositories \
        --repository-names "$repo" \
        --region "$AWS_REGION" &>/dev/null; then
        echo -e "${GREEN}âœ… Repository exists: $repo${NC}"
    else
        echo "Creating repository: $repo"
        # Create new ECR repository with:
        # - Image scanning enabled (checks for security vulnerabilities)
        # - AES256 encryption (encrypts images at rest)
        aws ecr create-repository \
            --repository-name "$repo" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 \
            --no-cli-pager
        echo -e "${GREEN}âœ… Created: $repo${NC}"
    fi
    echo ""
done

# ============================================
# Step 2: Login to ECR
# ============================================
echo ""
echo "ðŸ”‘ Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin \
    "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo -e "${GREEN}âœ… Logged in to ECR${NC}"
echo ""

# ============================================
# Step 3: Tag and Push Images
# ============================================
echo "ðŸ“¤ Tagging and pushing images..."
echo ""

# Build ECR URIs
ECR_AIRFLOW="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/churn-pipeline/airflow:2.8.1-amazon"
ECR_MLFLOW="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/churn-pipeline/mlflow:latest"
ECR_DATA="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/churn-pipeline/data:latest"
ECR_TRAIN="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/churn-pipeline/model:latest"
ECR_INFER="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/churn-pipeline/inference:latest"

# Process images one by one
echo "Processing: $IMG_AIRFLOW_LOCAL -> $ECR_AIRFLOW"
if docker image inspect "$IMG_AIRFLOW_LOCAL" &>/dev/null; then
    docker tag "$IMG_AIRFLOW_LOCAL" "$ECR_AIRFLOW"
    echo -e "${GREEN}âœ… Tagged: $IMG_AIRFLOW_LOCAL${NC}"
    echo "Pushing to ECR..."
    docker push "$ECR_AIRFLOW"
    echo -e "${GREEN}âœ… Pushed: $ECR_AIRFLOW${NC}"
else
    echo -e "${RED}âŒ Local image not found: $IMG_AIRFLOW_LOCAL${NC}"
    echo "   Build it first with: docker-compose build"
fi
echo ""

echo "Processing: $IMG_MLFLOW_LOCAL -> $ECR_MLFLOW"
if docker image inspect "$IMG_MLFLOW_LOCAL" &>/dev/null; then
    docker tag "$IMG_MLFLOW_LOCAL" "$ECR_MLFLOW"
    echo -e "${GREEN}âœ… Tagged: $IMG_MLFLOW_LOCAL${NC}"
    echo "Pushing to ECR..."
    docker push "$ECR_MLFLOW"
    echo -e "${GREEN}âœ… Pushed: $ECR_MLFLOW${NC}"
else
    echo -e "${RED}âŒ Local image not found: $IMG_MLFLOW_LOCAL${NC}"
    echo "   Build it first with: docker-compose build"
fi
echo ""

echo "Processing: $IMG_DATA_LOCAL -> $ECR_DATA"
if docker image inspect "$IMG_DATA_LOCAL" &>/dev/null; then
    docker tag "$IMG_DATA_LOCAL" "$ECR_DATA"
    echo -e "${GREEN}âœ… Tagged: $IMG_DATA_LOCAL${NC}"
    echo "Pushing to ECR..."
    docker push "$ECR_DATA"
    echo -e "${GREEN}âœ… Pushed: $ECR_DATA${NC}"
else
    echo -e "${RED}âŒ Local image not found: $IMG_DATA_LOCAL${NC}"
    echo "   Build it first with: docker-compose build"
fi
echo ""

echo "Processing: $IMG_TRAIN_LOCAL -> $ECR_TRAIN"
if docker image inspect "$IMG_TRAIN_LOCAL" &>/dev/null; then
    docker tag "$IMG_TRAIN_LOCAL" "$ECR_TRAIN"
    echo -e "${GREEN}âœ… Tagged: $IMG_TRAIN_LOCAL${NC}"
    echo "Pushing to ECR..."
    docker push "$ECR_TRAIN"
    echo -e "${GREEN}âœ… Pushed: $ECR_TRAIN${NC}"
else
    echo -e "${RED}âŒ Local image not found: $IMG_TRAIN_LOCAL${NC}"
    echo "   Build it first with: docker-compose build"
fi
echo ""

echo "Processing: $IMG_INFER_LOCAL -> $ECR_INFER"
if docker image inspect "$IMG_INFER_LOCAL" &>/dev/null; then
    docker tag "$IMG_INFER_LOCAL" "$ECR_INFER"
    echo -e "${GREEN}âœ… Tagged: $IMG_INFER_LOCAL${NC}"
    echo "Pushing to ECR..."
    docker push "$ECR_INFER"
    echo -e "${GREEN}âœ… Pushed: $ECR_INFER${NC}"
else
    echo -e "${RED}âŒ Local image not found: $IMG_INFER_LOCAL${NC}"
    echo "   Build it first with: docker-compose build"
fi
echo ""

# ============================================
# Step 4: Save ECR URIs to .env.out
# ============================================
echo "ðŸ’¾ Saving ECR URIs to .env.out..."

cat > "$(dirname "$0")/.env.out" << EOF
# Generated by 10_bootstrap.sh
# Source this file: source .env.out

# ECR Image URIs
export ECR_AIRFLOW="${ECR_AIRFLOW}"
export ECR_MLFLOW="${ECR_MLFLOW}"
export ECR_DATA="${ECR_DATA}"
export ECR_TRAIN="${ECR_TRAIN}"
export ECR_INFER="${ECR_INFER}"
EOF

echo -e "${GREEN}âœ… Saved to .env.out${NC}"
echo ""

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "ðŸŽ‰ Bootstrap Complete!"
echo "=========================================="
echo ""
echo "ECR Repositories Created:"
for repo in "${REPOS[@]}"; do
    echo "  âœ… $repo"
done
echo ""
echo "Images Pushed:"
echo "  âœ… Airflow: $ECR_AIRFLOW"
echo "  âœ… MLflow:  $ECR_MLFLOW"
echo "  âœ… Data:    $ECR_DATA"
echo "  âœ… Train:   $ECR_TRAIN"
echo "  âœ… Infer:   $ECR_INFER"
echo ""
echo -e "${YELLOW}ðŸ“ Next step: ./20_networking.sh${NC}"

