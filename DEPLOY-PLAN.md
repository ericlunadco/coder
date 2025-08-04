# Coder Deployment Plan for AWS

> **Note:** This deployment plan now assumes you are using a persistent PostgreSQL database (see `DATABASE-MIGRATION.md` for initial setup). After the first infrastructure deployment, all subsequent redeployments are streamlined and data will persist across deployments.

## Quick Redeployment (After Initial Setup)

Once your infrastructure is set up (RDS, Secrets Manager, ECS roles, etc.), you can redeploy Coder with a single command:

### MFA Authentication Required

Before running deployment commands, ensure you have valid MFA credentials:

```bash
# Check if your MFA session is still valid
aws sts get-caller-identity

# If expired, get a new MFA session (replace XXXXXX with your MFA code)
aws sts get-session-token --serial-number arn:aws:iam::YOUR_ACCOUNT:mfa/YOUR_USERNAME --token-code XXXXXX --duration-seconds 43200

# Update your ~/.aws/credentials [mfa-session] section with the new credentials
# Then set the profile and region:
export AWS_PROFILE=mfa-session
export AWS_REGION=us-east-1
```

### Run Deployment

```bash
./deploy-with-database.sh
```
- When prompted, choose option **3**: `Application only (requires existing infrastructure)`

This script will:
- Build the Coder binary (including frontend assets)
- Build and tag the Docker image
- Push the image to ECR
- Register a new ECS task definition
- Update the ECS service to use the new image
- Output the public IP/URL for your deployment

**Your data will persist across redeployments.**

---

This document outlines the steps to deploy your Coder frontend changes to AWS using Docker containers.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed and running
- ECR repository created or permissions to create one
- AWS ECS permissions
- **MFA Authentication Required**: Your AWS account has MFA enforcement enabled

## Step 1: Build the Offline Documentation

Build the offline documentation site first:

```bash
# Navigate to offlinedocs directory
cd offlinedocs

# Install dependencies
pnpm install

# Build the static documentation site
pnpm build

# The static site will be in the 'out' directory
```

**Note:** This creates a static Next.js site that can be deployed to any static hosting service (S3, CloudFront, etc.).

### Deploy Documentation to AWS S3 + CloudFront

```bash
# Create S3 bucket for docs (one-time setup) - COMPLETED
aws s3 mb s3://coder-docs-buildworkforce --region us-east-1

# Enable static website hosting - COMPLETED
aws s3 website s3://coder-docs-buildworkforce --index-document index.html --error-document 404.html

# Sync the built docs to S3 - COMPLETED
aws s3 sync ./out/ s3://coder-docs-buildworkforce --delete

# Create CloudFront distribution for HTTPS and caching (one-time setup) - COMPLETED
# Distribution ID: E1D97FI1EB5Z9H
# CloudFront Domain: d3bxhxl4fsp8gb.cloudfront.net
aws cloudfront create-distribution --distribution-config '{
  "CallerReference": "coder-docs-'$(date +%s)'",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "coder-docs-origin",
        "DomainName": "coder-docs-buildworkforce.s3-website-us-east-1.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "coder-docs-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "MinTTL": 0,
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {"Forward": "none"}
    }
  },
  "Comment": "Coder documentation site",
  "Enabled": true
}'

# Get CloudFront distribution domain name - COMPLETED
CLOUDFRONT_DOMAIN=$(aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`Coder documentation site`].DomainName' --output text)
echo "Documentation will be available at: https://$CLOUDFRONT_DOMAIN"

# DEPLOYED INFRASTRUCTURE:
# S3 Bucket: coder-docs-buildworkforce
# CloudFront Distribution ID: E1D97FI1EB5Z9H
# CloudFront Domain: d3bxhxl4fsp8gb.cloudfront.net
# Documentation URL: https://d3bxhxl4fsp8gb.cloudfront.net
# Custom Domain: https://docs.workbench.buildworkforce.ai (requires DNS setup)
```

**Important:** Update the `CODER_DOCS_URL` environment variable in your deployment to point to your CloudFront domain.

## Step 2: Build the Coder Binary

Build the Coder binary with your frontend changes embedded:

```bash
# Navigate back to root directory
cd ..

# Build the "fat" binary that includes the frontend (with extended timeout)
nix-shell --run "make build-fat"
```

**Note:** This command may take 5-10 minutes to complete as it builds both the Go binary and the frontend assets.

This will create a `coder` binary in the root directory that includes your frontend changes from the `site/` directory.

## Step 3: Create Docker Image

Use the existing build script to create a Docker image:

```bash
# Get the current version
CODER_VERSION=$(nix-shell --run "./scripts/version.sh")

# Build for AMD64 architecture (recommended for AWS ECS)
nix-shell --run "./scripts/build_docker.sh --arch amd64 --version $CODER_VERSION ./build/coder_${CODER_VERSION}_linux_amd64"

# For ARM64 (only if deploying to ARM-based instances)
# nix-shell --run "./scripts/build_docker.sh --arch arm64 --version $CODER_VERSION ./build/coder_${CODER_VERSION}_linux_arm64"
```

The script will:
- Create a temporary directory with the Coder binary
- Build the Docker image using `scripts/Dockerfile`
- Tag the image appropriately

## Step 4: Set Up ECR Repository

### First Time Setup (One-time only)

Create an ECR repository for your Coder image:

```bash
# Set your AWS region and repository name
export AWS_REGION="us-east-1"
export REPO_NAME="coder"

# Create ECR repository (only needed once)
aws ecr create-repository \
    --repository-name $REPO_NAME \
    --region $AWS_REGION
```

### For Each Deployment

```bash
# Set environment variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get ECR login token
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

## Step 5: Tag and Push Image to ECR

Tag your local image and push it to ECR:

```bash
# Set environment variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPO_NAME="coder"

# Get version and create Docker-compatible version (replace + with -)
CODER_VERSION_RAW=$(nix-shell --run "./scripts/version.sh")
CODER_VERSION=$(echo $CODER_VERSION_RAW | sed 's/+/-/g')

# Tag the image for ECR
LOCAL_IMAGE_TAG="ghcr.io/coder/coder:v${CODER_VERSION}-amd64"
ECR_IMAGE_TAG="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$CODER_VERSION"

docker tag $LOCAL_IMAGE_TAG $ECR_IMAGE_TAG

# Push to ECR (may take 3-5 minutes)
docker push $ECR_IMAGE_TAG
```

**Note:** The push command may take several minutes to complete. If it times out, run it again as Docker will resume from where it left off.

## Step 6: Deploy to ECS

### First Time Setup (One-time only)

1. **Create ECS Cluster:**
```bash
aws ecs create-cluster --cluster-name coder-cluster --region us-east-1
```

2. **Create CloudWatch Log Group:**
```bash
aws logs create-log-group --log-group-name /ecs/coder --region us-east-1
```

3. **Create Security Group:**
```bash
# Get default VPC ID
VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)

# Create security group
SG_ID=$(aws ec2 create-security-group \
    --group-name coder-sg \
    --description "Security group for Coder application" \
    --vpc-id $VPC_ID \
    --region us-east-1 \
    --query 'GroupId' --output text)

# Allow inbound traffic on port 3000
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0 \
    --region us-east-1

echo "Security Group ID: $SG_ID"
```

### For Each Deployment

1. **Create Task Definition:**
Create a task definition JSON file (`coder-task-definition.json`) with your specific values:

```json
{
  "family": "coder",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "coder",
      "image": "YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/coder:VERSION",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "CODER_HTTP_ADDRESS",
          "value": "0.0.0.0:3000"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/coder",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

2. **Register Task Definition:**
```bash
aws ecs register-task-definition --cli-input-json file://coder-task-definition.json --region us-east-1
```

3. **Update Service (if exists) or Create New Service:**

**For First Time:**
```bash
# Get a public subnet
SUBNET_ID=$(aws ec2 describe-subnets --region us-east-1 --filters "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text)

# Create service (replace SG_ID with your security group ID)
aws ecs create-service \
    --cluster coder-cluster \
    --service-name coder-service \
    --task-definition coder:1 \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[sg-YOUR_SG_ID],assignPublicIp=ENABLED}" \
    --region us-east-1
```

**For Updates:**
```bash
# Update existing service to use new task definition
aws ecs update-service \
    --cluster coder-cluster \
    --service coder-service \
    --task-definition coder:REVISION_NUMBER \
    --region us-east-1
```

4. **Get Public IP:**
```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks --cluster coder-cluster --service-name coder-service --region us-east-1 --query 'taskArns[0]' --output text)

# Get network interface ID
ENI_ID=$(aws ecs describe-tasks --cluster coder-cluster --tasks $TASK_ARN --region us-east-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)

# Get public IP
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region us-east-1 --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "Coder is accessible at: http://$PUBLIC_IP:3000"
```

## Step 7: Configure Load Balancer and DNS

1. **Create Application Load Balancer** for ECS
2. **Configure SSL certificate** through ACM
3. **Set up Route 53 DNS** to point to your load balancer

## Environment Variables

Key environment variables for Coder deployment:

```bash
CODER_HTTP_ADDRESS=0.0.0.0:3000
WORKBENCH_ACCESS_URL=https://your-domain.com
CODER_PG_CONNECTION_URL=postgresql://...  # If using external DB
CODER_WILDCARD_ACCESS_URL=*.your-domain.com
CODER_DOCS_URL=https://docs.workbench.buildworkforce.ai  # Custom domain (requires DNS setup)
# OR use CloudFront domain directly:
# CODER_DOCS_URL=https://d3bxhxl4fsp8gb.cloudfront.net
```

## Monitoring and Logging

- Set up CloudWatch logs for container logging
- Configure CloudWatch metrics for monitoring
- Set up alerts for service health

## Security Considerations

- Use IAM roles with least privilege
- Enable VPC security groups with minimal required ports
- Use AWS Secrets Manager for sensitive configuration
- Enable AWS WAF if exposing to the internet

## Quick Redeployment Steps

For subsequent deployments after initial setup:

1. **Run the deployment script:**
```bash
./deploy-with-database.sh
```
- Choose option 3: Application only (requires existing infrastructure)
- Choose option 4: Documentation only (to update documentation separately)

2. **(Optional) Manual Steps**
If you need to customize the deployment or run steps manually, you can still follow the detailed steps below (build, tag, push, update ECS), but the script automates all of this for you.

---

## Rollback Plan

To rollback to previous version:
1. Update task definition to use previous image tag
2. Update ECS service to use previous task definition
3. Monitor deployment and health checks

## Important Notes

- The Coder binary includes the frontend assets embedded via Go embed
- Frontend changes are included in the binary build process
- No separate frontend deployment is needed
- Database migrations (if any) should be handled during deployment
- Build process may take 5-10 minutes due to frontend compilation
- Docker push may take 3-5 minutes; if it times out, run again
- Version strings with '+' characters must be converted to '-' for Docker compatibility
- AWS CLI commands must include `--region us-east-1` parameter
- Security groups need to allow inbound traffic on port 3000 for public access

## Troubleshooting

### Common Issues:

1. **Build timeout:** Increase timeout or run `nix-shell --run "make build-fat"` with patience
2. **Docker push timeout:** Run the push command again; Docker will resume from where it left off
3. **Version format error:** Ensure version strings replace '+' with '-' for Docker tags
4. **AWS region errors:** Always specify `--region us-east-1` in AWS CLI commands
5. **Service not accessible:** Check security group allows inbound traffic on port 3000
6. **Task failing to start:** Check CloudWatch logs at `/ecs/coder` log group
7. **Database connection timeout:** Ensure RDS security group allows connections from ECS security group on port 5432
8. **Wrong environment variable:** Use `CODER_PG_CONNECTION_URL` not `CODER_POSTGRES_URL` for database connection
9. **MFA Authentication Errors:**
   - **Error:** `ExpiredToken` or `AccessDeniedException` with explicit deny
   - **Cause:** MFA session has expired or you're using a profile without MFA
   - **Solution:** Run `aws sts get-session-token` with your MFA device to get new credentials
   - **Verify:** Use `export AWS_PROFILE=mfa-session` and test with `aws sts get-caller-identity`
