#!/bin/bash
# ==========================================
# Rebuild Docker Images for linux/amd64
# ==========================================
# Required for AWS Fargate deployment (only supports AMD64)
# Run this on Apple Silicon before pushing to ECR

set -euo pipefail

cd "$(dirname "$0")/.."

echo "ðŸ”§ Rebuilding Docker images for linux/amd64 platform"
echo "====================================================="
echo ""
echo "âš ï¸  This may take 10-15 minutes on Apple Silicon"
echo "    Docker will use QEMU emulation for AMD64"
echo ""

# Check if buildx is available (better for cross-platform)
if docker buildx version &>/dev/null; then
    echo "âœ… Using docker buildx for cross-platform build"
    BUILDER="buildx"
    
    # Create/use buildx builder
    docker buildx create --name amd64-builder --use 2>/dev/null || docker buildx use amd64-builder
else
    echo "â„¹ï¸  Using standard docker build"
    BUILDER="standard"
fi

echo ""
echo "ðŸ—ï¸  Building images..."
echo ""

# Image configurations: dockerfile|target|tag
IMAGES=(
    "docker/Dockerfile.airflow||churn-pipeline/airflow:2.8.1-amazon"
    "docker/Dockerfile.mlflow||churn-pipeline/mlflow:latest"
    "docker/Dockerfile.base|data-pipeline|churn-pipeline/data:latest"
    "docker/Dockerfile.base|model-pipeline|churn-pipeline/model:latest"
    "docker/Dockerfile.base|inference-pipeline|churn-pipeline/inference:latest"
)

for img_info in "${IMAGES[@]}"; do
    IFS='|' read -r dockerfile target full_tag <<< "$img_info"
    
    echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
    echo "Building: $full_tag"
    if [ -n "$target" ]; then
        echo "  Dockerfile: $dockerfile (target: $target)"
    else
        echo "  Dockerfile: $dockerfile"
    fi
    echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
    
    # Build command with optional target
    if [ "$BUILDER" = "buildx" ]; then
        if [ -n "$target" ]; then
            docker buildx build \
                --platform linux/amd64 \
                --load \
                -f "$dockerfile" \
                --target "$target" \
                -t "$full_tag" \
                . || {
                    echo "âŒ Failed to build $full_tag"
                    exit 1
                }
        else
            docker buildx build \
                --platform linux/amd64 \
                --load \
                -f "$dockerfile" \
                -t "$full_tag" \
                . || {
                    echo "âŒ Failed to build $full_tag"
                    exit 1
                }
        fi
    else
        if [ -n "$target" ]; then
            docker build \
                --platform linux/amd64 \
                -f "$dockerfile" \
                --target "$target" \
                -t "$full_tag" \
                . || {
                    echo "âŒ Failed to build $full_tag"
                    exit 1
                }
        else
            docker build \
                --platform linux/amd64 \
                -f "$dockerfile" \
                -t "$full_tag" \
                . || {
                    echo "âŒ Failed to build $full_tag"
                    exit 1
                }
        fi
    fi
    
    echo "âœ… Built: $full_tag"
    echo ""
done

echo ""
# Verify platform
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
echo "ðŸ” Verifying image platforms..."
echo "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”"
echo ""

for img_info in "${IMAGES[@]}"; do
    IFS='|' read -r dockerfile target full_tag <<< "$img_info"
    
    platform=$(docker image inspect "$full_tag" --format '{{.Os}}/{{.Architecture}}' 2>/dev/null || echo "not found")
    if [ "$platform" = "linux/amd64" ]; then
        echo "âœ… $full_tag â†’ $platform"
    else
        echo "âŒ $full_tag â†’ $platform (expected linux/amd64)"
    fi
done

echo ""
echo "=========================================="
echo "ðŸŽ‰ Rebuild Complete!"
echo "=========================================="
echo ""

# Clean up dangling images (old ARM64 versions)
echo "ðŸ§¹ Cleaning up dangling images (old ARM64 versions)..."
echo ""

# Show what will be removed
DANGLING_COUNT=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')

if [ "$DANGLING_COUNT" -gt 0 ]; then
    echo "Found $DANGLING_COUNT dangling image(s)"
    echo "These are the old ARM64 images that were replaced"
    echo ""
    
    # Remove dangling images
    docker image prune -f
    
    echo ""
    echo "âœ… Cleanup complete! Disk space freed."
else
    echo "No dangling images found - nothing to clean up"
fi

echo ""
echo "=========================================="
echo "ðŸ“ Next steps:"
echo "=========================================="
echo ""
echo "   1. cd ecs-deploy"
echo "   2. ./10_bootstrap.sh  # Push AMD64 images to ECR"
echo "   3. Force service update to use new images:"
echo "      ./update_services.sh"
echo ""

