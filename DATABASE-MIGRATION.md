# Database Migration Guide

This guide provides step-by-step instructions for migrating from the current ephemeral SQLite setup to persistent PostgreSQL database.

## Current State

- **Problem**: Data loss occurs on every ECS deployment
- **Cause**: SQLite database stored in ephemeral container storage
- **Impact**: Users, workspaces, and settings are lost during updates

## Solution Overview

The solution implements:
1. **RDS PostgreSQL** instance for persistent storage
2. **AWS Secrets Manager** for secure credential management
3. **Updated ECS task definition** with database connection
4. **Terraform infrastructure** for automated deployment

## Migration Steps

### 1. Backup Current Data (If Any)

If you have existing data that needs to be preserved:

```bash
# Connect to running container
TASK_ARN=$(aws ecs list-tasks --cluster coder-cluster --service-name coder-service --region us-east-1 --query 'taskArns[0]' --output text)

# Get container ID (if you have ECS Exec enabled)
aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "/bin/bash" \
    --interactive
```

### 2. Deploy Database Infrastructure

```bash
# Clone/update the infrastructure files
# Ensure you have: aws-rds.tf, aws-secrets.tf, coder-task-definition.json

# Set database password
export TF_VAR_db_password="your-secure-password"

# Deploy infrastructure
terraform init
terraform plan
terraform apply
```

### 3. Update ECS Task Definition

The task definition has been updated to include:
- **Database connection**: Via `CODER_POSTGRES_URL` secret
- **IAM permissions**: For Secrets Manager access
- **Security groups**: For ECS-to-RDS communication

### 4. Deploy Updated Application

```bash
# Use the deployment script
./deploy-with-database.sh

# Or manually:
# 1. Build and push new image
# 2. Register updated task definition
# 3. Update ECS service
```

### 5. Verify Database Connection

After deployment, check the logs:

```bash
# Check container logs
aws logs tail /ecs/coder --follow --region us-east-1
```

Look for successful database connection messages.

## Infrastructure Components

### RDS PostgreSQL Instance
- **Instance**: `db.t3.micro` (suitable for development)
- **Storage**: 20GB, auto-scaling to 100GB
- **Backup**: 7-day retention
- **Security**: Encrypted storage, VPC-only access

### AWS Secrets Manager
- **Secret**: `coder-postgres-url`
- **Access**: Limited to ECS task execution role
- **Format**: PostgreSQL connection string

### Security Groups
- **ECS Security Group**: Allows inbound on port 3000
- **RDS Security Group**: Allows inbound on port 5432 from ECS

## Post-Migration Verification

### 1. Data Persistence Test
```bash
# 1. Create a test user/workspace
# 2. Deploy a new version
# 3. Verify data survives deployment
```

### 2. Database Connection Test
```bash
# Connect to RDS instance
psql -h <rds-endpoint> -U coder -d coder
```

### 3. Application Health
- Check Coder web interface loads
- Verify user authentication works
- Test workspace creation

## Rollback Plan

If issues occur, you can rollback to the previous SQLite setup:

```bash
# 1. Remove secrets section from task definition
# 2. Revert to original executionRoleArn
# 3. Deploy previous task definition
```

## Cost Considerations

### RDS Costs
- **db.t3.micro**: ~$13/month
- **Storage**: ~$2/month for 20GB
- **Backup**: Included in storage cost

### Total Additional Cost
- Approximately **$15-20/month** for persistent database

## Security Best Practices

1. **Use strong database passwords** (stored in Secrets Manager)
2. **Enable VPC-only access** for RDS instance
3. **Use IAM roles** instead of hardcoded credentials
4. **Enable encryption** for database storage
5. **Monitor access logs** via CloudWatch

## Troubleshooting

### Common Issues

1. **"Connection refused" errors**
   - Check security group rules
   - Verify RDS instance is running
   - Confirm subnet group configuration

2. **"Authentication failed" errors**
   - Verify secret value in Secrets Manager
   - Check IAM role permissions
   - Confirm database user exists

3. **"Database does not exist" errors**
   - Verify database name in connection string
   - Check if database was created during RDS setup

### Useful Commands

```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier coder-postgres

# Check secret value
aws secretsmanager get-secret-value --secret-id coder-postgres-url

# Check ECS task logs
aws logs tail /ecs/coder --follow

# Test database connection
psql -h <endpoint> -U coder -d coder -c "SELECT version();"
```

## Migration Checklist

- [ ] Backup existing data (if any)
- [ ] Deploy RDS infrastructure with Terraform
- [ ] Update IAM roles and permissions
- [ ] Deploy updated task definition
- [ ] Verify database connection in logs
- [ ] Test data persistence across deployments
- [ ] Monitor application performance
- [ ] Update monitoring/alerting for database

## Next Steps

After successful migration:

1. **Set up monitoring** for database performance
2. **Configure automated backups** if needed
3. **Implement SSL/TLS** for database connections
4. **Set up database maintenance windows**
5. **Create disaster recovery procedures**

## Support

If you encounter issues:
1. Check CloudWatch logs for error messages
2. Verify security group configurations
3. Test database connectivity manually
4. Review Terraform outputs for correct values