#!/bin/bash

# Coder Deployment Script with Database Persistence
# This script extends the deployment plan to include database setup
#
# IMPORTANT: Database connection requirements:
# - Use CODER_PG_CONNECTION_URL environment variable (not CODER_POSTGRES_URL)
# - Ensure RDS security group allows connections from ECS security group on port 5432

set -e

# Configuration
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPO_NAME="coder"

# Documentation deployment configuration
# These are set based on the actual deployed infrastructure
export DOCS_S3_BUCKET="coder-docs-buildworkforce"
export DOCS_CLOUDFRONT_DISTRIBUTION_ID="E1D97FI1EB5Z9H"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check Docker
    if ! command_exists docker; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Terraform
    if ! command_exists terraform; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    # Check if in nix-shell or nix available
    if ! command_exists nix-shell && [[ -z "$IN_NIX_SHELL" ]]; then
        log_error "Nix is not available. Please install Nix or run from nix-shell"
        exit 1
    fi
    
    # Check pnpm for offlinedocs build
    if ! command_exists pnpm; then
        log_error "pnpm is not installed. Please install pnpm for building documentation"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying database infrastructure with Terraform..."
    
    # Check if terraform files exist
    if [[ ! -f "aws-rds.tf" ]] || [[ ! -f "aws-secrets.tf" ]]; then
        log_error "Terraform files (aws-rds.tf, aws-secrets.tf) not found"
        exit 1
    fi
    
    # Prompt for database password if not set
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -n "Enter database password: "
        read -s DB_PASSWORD
        echo
        export TF_VAR_db_password="$DB_PASSWORD"
    fi
    
    # Initialize and apply Terraform
    terraform init
    terraform plan -out=tfplan
    
    echo "Review the Terraform plan above. Do you want to apply? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        log_info "Infrastructure deployed successfully"
    else
        log_warn "Infrastructure deployment cancelled"
        exit 1
    fi
}

# Build offline documentation
build_offlinedocs() {
    log_info "Building offline documentation..."
    
    # Check if offlinedocs directory exists
    if [[ ! -d "offlinedocs" ]]; then
        log_error "offlinedocs directory not found"
        exit 1
    fi
    
    # Navigate to offlinedocs directory
    cd offlinedocs
    
    # Install dependencies if needed
    if [[ ! -d "node_modules" ]]; then
        log_info "Installing offlinedocs dependencies..."
        pnpm install
    fi
    
    # Build the static documentation site
    log_info "Building static documentation site..."
    cd ..
    nix-shell --run "cd offlinedocs && pnpm build"
    cd offlinedocs
    
    # Deploy to S3 if configured
    if [[ -n "$DOCS_S3_BUCKET" ]]; then
        log_info "Deploying documentation to S3 bucket: $DOCS_S3_BUCKET"
        aws s3 sync ./out/ s3://$DOCS_S3_BUCKET --delete --region $AWS_REGION
        
        # Invalidate CloudFront cache if distribution exists
        if [[ -n "$DOCS_CLOUDFRONT_DISTRIBUTION_ID" ]]; then
            log_info "Invalidating CloudFront cache..."
            aws cloudfront create-invalidation \
                --distribution-id $DOCS_CLOUDFRONT_DISTRIBUTION_ID \
                --paths "/*" \
                --region $AWS_REGION
        fi
    else
        log_warn "DOCS_S3_BUCKET not set, skipping documentation deployment"
        log_info "Built documentation is available in offlinedocs/out/"
    fi
    
    # Navigate back to root directory
    cd ..
}

# Deploy only documentation
deploy_docs_only() {
    log_info "Deploying documentation only..."
    build_offlinedocs
    log_info "Documentation deployment completed!"
}

# Build and push Docker image
build_and_push_image() {
    log_info "Building Coder binary and Docker image..."
    
    # Skip documentation build for application-only deployments
    # Documentation should be deployed separately when needed
    
    # Build the fat binary
    if [[ -n "$IN_NIX_SHELL" ]]; then
        make build-fat
    else
        nix-shell --run "make build-fat"
    fi
    
    # Get version
    if [[ -n "$IN_NIX_SHELL" ]]; then
        CODER_VERSION_RAW=$(./scripts/version.sh)
    else
        CODER_VERSION_RAW=$(nix-shell --run "./scripts/version.sh")
    fi
    
    CODER_VERSION=$(echo $CODER_VERSION_RAW | sed 's/+/-/g')
    
    log_info "Building Docker image for version: $CODER_VERSION"
    
    # Build Docker image
    if [[ -n "$IN_NIX_SHELL" ]]; then
        ./scripts/build_docker.sh --arch amd64 --version $CODER_VERSION_RAW ./build/coder_${CODER_VERSION_RAW}_linux_amd64
    else
        nix-shell --run "./scripts/build_docker.sh --arch amd64 --version $CODER_VERSION_RAW ./build/coder_${CODER_VERSION_RAW}_linux_amd64"
    fi
    
    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin \
        $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Tag and push image
    LOCAL_IMAGE_TAG="ghcr.io/coder/coder:v${CODER_VERSION}-amd64"
    ECR_IMAGE_TAG="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$CODER_VERSION"
    
    docker tag $LOCAL_IMAGE_TAG $ECR_IMAGE_TAG
    docker push $ECR_IMAGE_TAG
    
    log_info "Image pushed successfully: $ECR_IMAGE_TAG"
    
    # Update task definition with new image
    sed -i.bak "s|\"image\": \".*\"|\"image\": \"$ECR_IMAGE_TAG\"|" coder-task-definition.json
    rm coder-task-definition.json.bak
    
    # Add docs URL environment variable if configured
    if [[ -n "$DOCS_S3_BUCKET" ]]; then
        # Get CloudFront domain if distribution is configured
        if [[ -n "$DOCS_CLOUDFRONT_DISTRIBUTION_ID" ]]; then
            DOCS_DOMAIN=$(aws cloudfront get-distribution --id $DOCS_CLOUDFRONT_DISTRIBUTION_ID --query 'Distribution.DomainName' --output text)
            DOCS_URL="https://$DOCS_DOMAIN"
        else
            DOCS_URL="https://$DOCS_S3_BUCKET.s3-website-$AWS_REGION.amazonaws.com"
        fi
        
        log_info "Documentation will be available at: $DOCS_URL"
        log_info "Set CODER_DOCS_URL environment variable to: $DOCS_URL"
    fi
}

# Deploy to ECS
deploy_to_ecs() {
    log_info "Deploying to ECS..."
    
    # Register task definition
    aws ecs register-task-definition --cli-input-json file://coder-task-definition.json --region $AWS_REGION
    
    # Get latest task definition revision
    LATEST_REVISION=$(aws ecs describe-task-definition --task-definition coder --region $AWS_REGION --query 'taskDefinition.revision' --output text)
    
    # Check if service exists
    SERVICE_EXISTS=$(aws ecs describe-services --cluster coder-cluster --services coder-service --region $AWS_REGION --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")
    
    if [[ "$SERVICE_EXISTS" == "MISSING" ]] || [[ "$SERVICE_EXISTS" == "None" ]]; then
        log_info "Creating new ECS service..."
        
        # Get ECS security group from Terraform output
        ECS_SG_ID=$(terraform output -raw ecs_security_group_id)
        
        # Get a public subnet
        SUBNET_ID=$(aws ec2 describe-subnets --region $AWS_REGION --filters "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text)
        
        # Create service
        aws ecs create-service \
            --cluster coder-cluster \
            --service-name coder-service \
            --task-definition coder:$LATEST_REVISION \
            --desired-count 1 \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
            --region $AWS_REGION
    else
        log_info "Updating existing ECS service..."
        
        # Update service
        aws ecs update-service \
            --cluster coder-cluster \
            --service coder-service \
            --task-definition coder:$LATEST_REVISION \
            --region $AWS_REGION
    fi
    
    log_info "ECS deployment initiated"
}

# Get service endpoint
get_service_endpoint() {
    log_info "Waiting for service to be running..."
    
    # Wait for service to stabilize
    aws ecs wait services-stable --cluster coder-cluster --services coder-service --region $AWS_REGION
    
    # Get task ARN
    TASK_ARN=$(aws ecs list-tasks --cluster coder-cluster --service-name coder-service --region $AWS_REGION --query 'taskArns[0]' --output text)
    
    if [[ "$TASK_ARN" != "None" ]] && [[ -n "$TASK_ARN" ]]; then
        # Get network interface ID
        ENI_ID=$(aws ecs describe-tasks --cluster coder-cluster --tasks $TASK_ARN --region $AWS_REGION --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
        
        # Get public IP
        PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region $AWS_REGION --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
        
        log_info "Coder is accessible at: http://$PUBLIC_IP:3000"
        log_info "Database persistence is now enabled - data will survive deployments"
        log_info "Note: Ensure RDS security group allows connections from ECS security group on port 5432"
        log_info "Note: Use CODER_PG_CONNECTION_URL (not CODER_POSTGRES_URL) for database connection"
    else
        log_error "Failed to get task information"
    fi
}

# Main deployment function
main() {
    echo "=== Coder Deployment with Database Persistence ==="
    echo
    
    check_prerequisites
    
    echo "Deployment options:"
    echo "1. Full deployment (infrastructure + application)"
    echo "2. Infrastructure only"
    echo "3. Application only (requires existing infrastructure)"
    echo "4. Documentation only"
    echo -n "Choose option (1-4): "
    read -r option
    
    case $option in
        1)
            deploy_infrastructure
            build_and_push_image
            deploy_to_ecs
            get_service_endpoint
            ;;
        2)
            deploy_infrastructure
            ;;
        3)
            build_and_push_image
            deploy_to_ecs
            get_service_endpoint
            ;;
        4)
            deploy_docs_only
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
    
    log_info "Deployment completed successfully!"
}

# Run main function
main "$@"