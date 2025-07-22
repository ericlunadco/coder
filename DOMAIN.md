# Domain and Load Balancer Setup for Coder

This document provides a plan to set up a stable domain URL for your Coder deployment instead of relying on changing public IP addresses.

## Overview

Currently, each ECS deployment gets a new public IP address, requiring you to find the new IP after each deployment. This plan sets up:

1. **Application Load Balancer (ALB)** - Provides a stable endpoint for your ECS service
2. **Existing SSL Certificate** - Use your existing `*.buildworkforce.ai` wildcard certificate
3. **Manual Route 53 DNS** - You'll manually add DNS records in your separate AWS account

## Prerequisites

- Existing `*.buildworkforce.ai` SSL certificate (already available)
- Route 53 hosted zone for `buildworkforce.ai` (in separate AWS account)
- Existing ECS service running (from DEPLOY-PLAN.md)
- AWS CLI configured with appropriate permissions in current account
- Access to Route 53 console in the account with the domain

## Step 1: Create Application Load Balancer

### 1.1 Create Target Group

```bash
# Set environment variables
export AWS_REGION="us-east-1"
export VPC_ID=$(aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)

# Create target group for Coder (IP targets for Fargate)
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name coder-targets \
    --protocol HTTP \
    --port 3000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /healthz \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 5 \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "Target Group ARN: $TARGET_GROUP_ARN"
```

### 1.2 Create Security Group for ALB

```bash
# Create security group for ALB
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name coder-alb-sg \
    --description "Security group for Coder ALB" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' --output text)

# Allow HTTP (port 80) from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

# Allow HTTPS (port 443) from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

echo "ALB Security Group ID: $ALB_SG_ID"
```

### 1.3 Create Application Load Balancer

```bash
# Get public subnets
SUBNET_IDS=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ' ')

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name coder-alb \
    --subnets $SUBNET_IDS \
    --security-groups $ALB_SG_ID \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].DNSName' --output text)

echo "ALB ARN: $ALB_ARN"
echo "ALB DNS: $ALB_DNS"
```

## Step 2: Find Your Existing SSL Certificate

### 2.1 List Available Certificates

```bash
# List all ACM certificates to find your *.buildworkforce.ai certificate
aws acm list-certificates \
    --region $AWS_REGION \
    --query 'CertificateSummaryList[?contains(DomainName, `buildworkforce.ai`)]' \
    --output table
```

### 2.2 Get Certificate ARN

```bash
# Get the ARN of your *.buildworkforce.ai certificate
CERT_ARN=$(aws acm list-certificates \
    --region $AWS_REGION \
    --query 'CertificateSummaryList[?contains(DomainName, `buildworkforce.ai`)].CertificateArn' \
    --output text)

echo "Certificate ARN: $CERT_ARN"
```

### 2.3 Verify Certificate Details

```bash
# Verify the certificate covers your subdomain
aws acm describe-certificate \
    --certificate-arn $CERT_ARN \
    --region $AWS_REGION \
    --query 'Certificate.[DomainName,SubjectAlternativeNames,Status]' \
    --output table
```

**Note:** Your existing `*.buildworkforce.ai` certificate should cover any subdomain like `coder.buildworkforce.ai`.

## Step 3: Configure Load Balancer Listeners

### 3.1 Create HTTP Listener (redirects to HTTPS)

```bash
# Create HTTP listener that redirects to HTTPS
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
    --region $AWS_REGION
```

### 3.2 Create HTTPS Listener

```bash
# Create HTTPS listener
HTTPS_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=$CERT_ARN \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
    --region $AWS_REGION \
    --query 'Listeners[0].ListenerArn' --output text)

echo "HTTPS Listener ARN: $HTTPS_LISTENER_ARN"
```

## Step 4: Update ECS Service Security Group

```bash
# Get current ECS service security group ID
# (Replace with your actual security group ID from DEPLOY-PLAN.md)
ECS_SG_ID="sg-YOUR_EXISTING_SG_ID"

# Allow ALB to communicate with ECS service on port 3000
aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG_ID \
    --protocol tcp \
    --port 3000 \
    --source-group $ALB_SG_ID \
    --region $AWS_REGION

# Remove direct internet access to port 3000 (optional, for security)
# aws ec2 revoke-security-group-ingress \
#     --group-id $ECS_SG_ID \
#     --protocol tcp \
#     --port 3000 \
#     --cidr 0.0.0.0/0 \
#     --region $AWS_REGION
```

## Step 5: Update ECS Service to Use ALB

```bash
# Update ECS service to use target group
aws ecs update-service \
    --cluster coder-cluster \
    --service coder-service \
    --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=coder,containerPort=3000 \
    --region $AWS_REGION
```

## Step 6: Configure DNS (Manual)

### Get ALB DNS Name for Manual Entry

```bash
# Get the ALB DNS name that you'll need to add to Route 53
echo "ALB DNS Name: $ALB_DNS"
echo "ALB Hosted Zone ID: Z35SXDOTRQ7X7K"  # US East 1 ALB hosted zone ID
```

### Manual DNS Configuration

**In your Route 53 console (separate AWS account):**

1. **Navigate to Route 53** in the account that manages `buildworkforce.ai`
2. **Select the hosted zone** for `buildworkforce.ai`
3. **Create a new record** with these settings:
   - **Record name**: `coder` (or your preferred subdomain)
   - **Record type**: `A`
   - **Alias**: `Yes`
   - **Route traffic to**: `Alias to Application and Classic Load Balancer`
   - **Region**: `US East (N. Virginia)`
   - **Load balancer**: Paste the `$ALB_DNS` value from above
   - **Hosted zone ID**: `Z35SXDOTRQ7X7K`

**Alternative CNAME approach:**
- **Record name**: `coder`
- **Record type**: `CNAME`
- **Value**: `$ALB_DNS` (from Step 1.3)
- **TTL**: `300`

**Final domain**: `https://coder.buildworkforce.ai`

## Step 7: Update Coder Configuration

Update your ECS task definition to include the stable URL:

```json
{
  "environment": [
    {
      "name": "CODER_HTTP_ADDRESS",
      "value": "0.0.0.0:3000"
    },
    {
      "name": "CODER_ACCESS_URL",
      "value": "https://coder.buildworkforce.ai"
    },
    {
      "name": "CODER_WILDCARD_ACCESS_URL",
      "value": "*.coder.buildworkforce.ai"
    }
  ]
}
```

## Step 8: Test the Setup

1. **Wait for DNS propagation** (may take 5-60 minutes)
2. **Test HTTP redirect**: `curl -I http://coder.buildworkforce.ai`
3. **Test HTTPS access**: `curl -I https://coder.buildworkforce.ai`
4. **Access Coder**: Open `https://coder.buildworkforce.ai` in your browser

## Benefits

After completing this setup:

✅ **Stable URL**: `https://coder.buildworkforce.ai` never changes  
✅ **SSL/TLS**: Uses your existing wildcard certificate  
✅ **High Availability**: ALB distributes traffic across multiple AZs  
✅ **Health Checks**: ALB monitors service health  
✅ **Security**: Traffic flows through AWS security groups  

## Cost Considerations

- **Application Load Balancer**: ~$16/month
- **SSL Certificate**: Already covered by existing certificate
- **Route 53**: No additional costs (using existing hosted zone)
- **Data Transfer**: Standard AWS rates apply

## Maintenance

- **Certificate renewal**: ACM handles automatic renewal of your existing certificate
- **DNS changes**: Only needed if changing subdomains
- **Load balancer**: Requires minimal maintenance

## Troubleshooting

### Common Issues:

1. **Certificate not found**: Verify your `*.buildworkforce.ai` certificate exists in current AWS account
2. **502 Bad Gateway**: Check ECS service health and security group rules
3. **DNS not resolving**: Wait for propagation or check Route 53 record in separate account
4. **HTTPS not working**: Verify certificate covers `coder.buildworkforce.ai` subdomain

### Health Check Commands:

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn $CERT_ARN --region $AWS_REGION

# Check target group health
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region $AWS_REGION

# Check load balancer status
aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION
```

## Integration with Existing Deployment

After completing this setup, your `deploy-with-database.sh` script will continue to work unchanged. The only difference is that users will access Coder via your stable domain instead of finding the new IP address after each deployment.

Your domain `https://coder.buildworkforce.ai` will remain constant while the underlying infrastructure can be updated seamlessly.

## Quick Setup Summary

1. **Create ALB and target group** (Steps 1-3)
2. **Find existing `*.buildworkforce.ai` certificate ARN** (Step 2)
3. **Configure HTTPS listener with existing certificate** (Step 3)
4. **Update ECS security groups** (Step 4)
5. **Connect ECS service to ALB** (Step 5)
6. **Manually add DNS record** in Route 53 (Step 6)
7. **Update Coder environment variables** (Step 7)
8. **Test the setup** (Step 8)

**Final URL**: `https://coder.buildworkforce.ai`