# Database Access Guide

This document provides instructions for accessing the PostgreSQL database used by the Coder deployment.

## Overview

The Coder application uses AWS RDS PostgreSQL for persistent data storage. Direct database access is available through ECS Exec, which allows you to connect to the running container and then to the database.

## Prerequisites

- AWS CLI configured with appropriate permissions
- MFA token configured (if required)
- Access to the `coder-cluster` ECS cluster

## Access Methods

### Method 1: ECS Exec (Recommended)

This method connects to the running Coder container and then to the database.

#### Step 1: Get the Current Task ARN

```bash
TASK_ARN=$(aws ecs list-tasks \
    --cluster coder-cluster \
    --service-name coder-service \
    --region us-east-1 \
    --query 'taskArns[0]' \
    --output text)

echo "Current task: $TASK_ARN"
```

#### Step 2: Connect to the Container

```bash
aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "/bin/sh" \
    --interactive \
    --region us-east-1
```

#### Step 3: Install PostgreSQL Client (if needed)

The container uses Alpine Linux and already has PostgreSQL client pre-installed. You can verify with:

```bash
# Check if psql is available
aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "which psql" \
    --interactive \
    --region us-east-1
```

If not installed, you can install it:

```bash
# Inside the container
apk add postgresql-client
```

#### Step 4: Connect to Database

```bash
# Inside the container
psql $CODER_PG_CONNECTION_URL
```

### Method 2: Direct Connection with psql

If you have the connection details and network access:

```bash
# Get the connection URL from AWS Secrets Manager
DB_URL=$(aws secretsmanager get-secret-value \
    --secret-id coder-postgres-url \
    --region us-east-1 \
    --query 'SecretString' \
    --output text)

# Connect directly (requires network access to RDS)
psql "$DB_URL"
```

## Common Database Operations

### View Tables

```sql
-- List all tables
\dt

-- Show table structure
\d templates
\d users
\d workspaces
```

### Query Templates

```sql
-- Find templates with specific text
SELECT id, name, description 
FROM templates 
WHERE description LIKE '%Coder%' OR description LIKE '%Workbench%';

-- Update template descriptions
UPDATE templates 
SET description = 'A minimal starter template for Workbench',
    updated_at = NOW() 
WHERE description = 'A minimal starter template for Coder';
```

### Query Users and Workspaces

```sql
-- List all users
SELECT id, username, email, created_at FROM users;

-- List all workspaces
SELECT id, name, owner_id, template_id, created_at FROM workspaces;

-- Show workspace count by template
SELECT t.name as template_name, COUNT(w.id) as workspace_count
FROM templates t
LEFT JOIN workspaces w ON t.id = w.template_id
GROUP BY t.id, t.name;
```

## Database Schema Information

### Connection Details

- **Host**: `coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com`
- **Port**: `5432`
- **Database**: `coder`
- **Username**: `coder`
- **Password**: Stored in AWS Secrets Manager (`coder-postgres-url`)

### Key Tables

- `templates` - Template definitions and metadata
- `users` - User accounts and authentication
- `workspaces` - Workspace instances
- `organizations` - Organization data
- `provisionerjobs` - Provisioning job history

## Security Considerations

### Access Control

- Database access requires ECS task execution permissions
- Connection URL is stored securely in AWS Secrets Manager
- RDS instance is isolated in VPC with security group restrictions

### Best Practices

1. **Use ECS Exec** instead of direct connections when possible
2. **Backup before modifications** - always backup before making changes
3. **Test queries** on non-production data first
4. **Use transactions** for multi-statement operations
5. **Monitor connection time** - avoid long-running connections

### Network Security

- RDS instance only accepts connections from ECS security group
- No public internet access to database
- All connections must be from within the VPC

## Troubleshooting

### Common Issues

#### "Connection refused" errors
```bash
# Check security group rules
aws ec2 describe-security-groups \
    --group-ids sg-0b2b0521f178fdb73 \
    --region us-east-1

# Verify RDS instance is running
aws rds describe-db-instances \
    --db-instance-identifier coder-postgres \
    --region us-east-1 \
    --query 'DBInstances[0].DBInstanceStatus'
```

#### "Authentication failed" errors
```bash
# Verify secret value
aws secretsmanager get-secret-value \
    --secret-id coder-postgres-url \
    --region us-east-1

# Check IAM permissions for task role
aws iam get-role-policy \
    --role-name coder-ecs-task-role \
    --policy-name ECSExecPolicy
```

#### ECS Exec not working
```bash
# Verify service has execute command enabled
aws ecs describe-services \
    --cluster coder-cluster \
    --services coder-service \
    --region us-east-1 \
    --query 'services[0].enableExecuteCommand'

# Check task role has required permissions
aws iam list-attached-role-policies \
    --role-name coder-ecs-task-role
```

### Useful Commands

```bash
# Check database connection from application logs
aws logs tail /ecs/coder --region us-east-1 --since 10m | grep -i database

# Get current database size
psql $CODER_PG_CONNECTION_URL -c "
SELECT 
    pg_size_pretty(pg_database_size('coder')) as database_size,
    pg_size_pretty(pg_total_relation_size('templates')) as templates_size,
    pg_size_pretty(pg_total_relation_size('users')) as users_size;
"

# List active connections
psql $CODER_PG_CONNECTION_URL -c "
SELECT pid, usename, application_name, client_addr, state, query_start 
FROM pg_stat_activity 
WHERE datname = 'coder' AND state = 'active';
"
```

### Advanced ECS Exec SQL Execution

For complex SQL queries with special characters, quoting can be problematic. Use base64 encoding to avoid shell escaping issues:

```bash
# Method 1: Execute simple queries directly
aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "psql \$CODER_PG_CONNECTION_URL -c \"SELECT version();\"" \
    --interactive \
    --region us-east-1

# Method 2: Use base64 encoding for complex queries
# First, encode your SQL query
echo "SELECT id, name, description FROM templates WHERE description LIKE '%Coder%';" | base64

# Then execute the base64 encoded query
aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "sh -c 'echo YOUR_BASE64_STRING | base64 -d | psql \$CODER_PG_CONNECTION_URL'" \
    --interactive \
    --region us-east-1

# Example: Update template description
# Encode: UPDATE templates SET description = 'A minimal starter template for Workbench', updated_at = NOW() WHERE id = '064143f4-2301-4291-8cd9-8facf797bf96';
# Base64: VVBEQVRFIHRlbXBsYXRlcyBTRVQgZGVzY3JpcHRpb24gPSAnQSBtaW5pbWFsIHN0YXJ0ZXIgdGVtcGxhdGUgZm9yIFdvcmtiZW5jaCcsIHVwZGF0ZWRfYXQgPSBOT1coKSBXSEVSRSBpZCA9ICcwNjQxNDNmNC0yMzAxLTQyOTEtOGNkOS04ZmFjZjc5N2JmOTYnOwo=

aws ecs execute-command \
    --cluster coder-cluster \
    --task $TASK_ARN \
    --container coder \
    --command "sh -c 'echo VVBEQVRFIHRlbXBsYXRlcyBTRVQgZGVzY3JpcHRpb24gPSAnQSBtaW5pbWFsIHN0YXJ0ZXIgdGVtcGxhdGUgZm9yIFdvcmtiZW5jaCcsIHVwZGF0ZWRfYXQgPSBOT1coKSBXSEVSRSBpZCA9ICcwNjQxNDNmNC0yMzAxLTQyOTEtOGNkOS04ZmFjZjc5N2JmOTYnOwo= | base64 -d | psql \$CODER_PG_CONNECTION_URL'" \
    --interactive \
    --region us-east-1
```

## Backup and Recovery

### Manual Backup

```bash
# Create backup
pg_dump $CODER_PG_CONNECTION_URL > coder_backup_$(date +%Y%m%d_%H%M%S).sql

# Restore from backup (BE CAREFUL!)
psql $CODER_PG_CONNECTION_URL < coder_backup_20250801_123000.sql
```

### RDS Automated Backups

- **Retention**: 7 days
- **Backup Window**: Configured in RDS settings
- **Point-in-time Recovery**: Available for last 7 days

## Support

For issues with database access:

1. Check CloudWatch logs for connection errors
2. Verify security group configurations
3. Test ECS Exec connectivity
4. Review IAM permissions for task roles
5. Check RDS instance status and performance metrics

## Change Log

- **2025-08-01**: Initial documentation created
- **2025-08-01**: Added ECS Exec setup and troubleshooting guide
- **2025-08-01**: Added advanced ECS Exec SQL execution methods with base64 encoding for complex queries
- **2025-08-01**: Updated PostgreSQL client installation notes (pre-installed in container)