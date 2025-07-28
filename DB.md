# Database Persistence Issues with Coder on ECS

## Problem Identified

When deploying Coder on AWS ECS Fargate without proper database configuration, **data loss occurs** during deployments. Here's what happens:

### Current Situation
- **No `CODER_POSTGRES_URL` environment variable** in task definition
- Coder defaults to **embedded SQLite database** stored in container's local filesystem
- Database is stored in **ephemeral container storage**
- When ECS updates the service (new task definition), it:
  1. Creates a new task instance with new container
  2. Terminates old task once new one is healthy
  3. **All SQLite data is lost** because it was in the old container

### IP Address Changes
- New task instances get **new public IP addresses**
- This is normal ECS Fargate behavior
- Each deployment creates a fresh container instance

## Solutions

### Option 1: External PostgreSQL Database (Recommended)

Add RDS PostgreSQL database and configure connection:

```json
{
  "environment": [
    {
      "name": "CODER_HTTP_ADDRESS",
      "value": "0.0.0.0:3000"
    },
    {
      "name": "CODER_POSTGRES_URL",
      "value": "postgresql://username:password@rds-endpoint:5432/coder"
    }
  ]
}
```

### Option 2: EFS Persistent Storage

Mount EFS volume to persist SQLite database:

```json
{
  "volumes": [
    {
      "name": "coder-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-xxxxxxxx",
        "rootDirectory": "/coder-data"
      }
    }
  ],
  "containerDefinitions": [
    {
      "mountPoints": [
        {
          "sourceVolume": "coder-data",
          "containerPath": "/home/coder/.config/coderv2"
        }
      ]
    }
  ]
}
```

### Option 3: Use Secrets Manager

Store database credentials securely:

```json
{
  "secrets": [
    {
      "name": "CODER_POSTGRES_URL",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:account:secret:coder-db-url"
    }
  ]
}
```

## Best Practices

1. **Always use external database** for production deployments
2. **Use AWS Secrets Manager** for database credentials
3. **Set up database backups** with RDS automated backups
4. **Configure proper VPC security groups** for database access
5. **Use Application Load Balancer** for consistent endpoint (eliminates IP changes)

## Migration Steps

To migrate from current setup to persistent database:

1. **Export current data** (if any exists before next deployment)
2. **Set up RDS PostgreSQL instance**
3. **Update task definition** with database URL
4. **Update security groups** to allow ECS → RDS communication
5. **Test deployment** with persistent storage
6. **Import data** if needed

## Important Notes

- **Data loss is permanent** once old task is terminated
- **Each deployment without persistent storage** creates a fresh Coder instance
- **Users, workspaces, and settings** are all lost during updates
- **This explains why database appears "wiped out"** after deployments

## Immediate Action Required

Current deployments will continue to lose data until persistent database is configured. Consider this a **high priority** issue for production use.

---

# Database Persistence Debugging - Next Steps

## Current Status (After Troubleshooting)

### ✅ Issues Fixed:
1. **Database URL Format**: Fixed malformed URL in Terraform (removed duplicate `:5432`)
2. **Secret ARN Configuration**: Updated ECS task definition with full ARN and suffix
3. **Secret Key Format**: Corrected format to `arn:secret-id:key::` for JSON extraction

### ❌ Still Not Working:
- Application continues to use "built-in PostgreSQL" instead of external RDS
- Logs show: `Using built-in PostgreSQL (/home/coder/.config/coderv2/postgres)`

## Next Steps to Debug Database Connection

### 1. Verify Secret Retrieval in Container

Test if the secret is being properly injected:

```bash
# Get current task ARN
TASK_ARN=$(aws ecs list-tasks --cluster coder-cluster --service-name coder-service --region us-east-1 --query 'taskArns[0]' --output text)

# Enable ECS exec on the service
aws ecs update-service --cluster coder-cluster --service coder-service --enable-execute-command --region us-east-1

# Execute into the container to check environment variables
aws ecs execute-command --cluster coder-cluster --task $TASK_ARN --container coder --command "/bin/sh" --interactive --region us-east-1
```

Inside the container, check:
```bash
echo $CODER_POSTGRES_URL
env | grep CODER
```

### 2. Test Database Connectivity

From within the container, test if the database is reachable:

```bash
# Install psql if not available
apk add postgresql-client

# Test connection
psql "postgresql://coder:xR7pf7MPgZyIChIXWqwO3srnp0GflgHwG7dMC7gvdHI=@coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com:5432/coder"
```

### 3. Check IAM Permissions

Verify the ECS task execution role has proper permissions:

```bash
# Check current IAM policies
aws iam list-attached-role-policies --role-name coder-ecs-task-execution-role --region us-east-1

# Verify Secrets Manager access
aws iam get-role-policy --role-name coder-ecs-task-execution-role --policy-name coder-ecs-secrets-policy --region us-east-1
```

### 4. Check Network Configuration

Verify security groups allow ECS → RDS communication:

```bash
# Get ECS security group rules
aws ec2 describe-security-groups --group-ids sg-0b2b0521f178fdb73 --region us-east-1

# Get RDS security group rules
aws ec2 describe-security-groups --group-ids sg-05d9fac2bef4eff35 --region us-east-1
```

### 5. Test Secret Retrieval Manually

Verify the secret can be retrieved with the exact ARN format:

```bash
aws secretsmanager get-secret-value --secret-id "arn:aws:secretsmanager:us-east-1:132880019009:secret:coder-postgres-url-PO7CI7" --region us-east-1
```

### 6. Check Coder Configuration

Coder may have additional configuration requirements:

```bash
# Check Coder help for database options
coder server --help | grep -i postgres
coder server --help | grep -i database
```

### 7. Alternative Secret Format

Try storing the secret as a plain string instead of JSON:

```bash
# Update secret to plain string format
aws secretsmanager update-secret --secret-id "coder-postgres-url" --secret-string "postgresql://coder:xR7pf7MPgZyIChIXWqwO3srnp0GflgHwG7dMC7gvdHI=@coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com:5432/coder" --region us-east-1
```

Then update task definition to use plain secret:
```json
{
  "name": "CODER_POSTGRES_URL",
  "valueFrom": "arn:aws:secretsmanager:us-east-1:132880019009:secret:coder-postgres-url-PO7CI7"
}
```

### 8. Check Database Initialization

Coder may need the database to be initialized:

```bash
# Connect to RDS and check if database exists
psql "postgresql://coder:xR7pf7MPgZyIChIXWqwO3srnp0GflgHwG7dMC7gvdHI=@coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com:5432/coder"

# Check if coder database exists
\l

# Check if any tables exist
\dt
```

### 9. Enable Debug Logging

Add debug environment variables to see more detailed logs:

```json
{
  "environment": [
    {
      "name": "CODER_VERBOSE",
      "value": "true"
    },
    {
      "name": "CODER_LOG_LEVEL",
      "value": "debug"
    }
  ]
}
```

### 10. Check Database URL Format

Verify the URL format is exactly what Coder expects:

```bash
# Test if URL needs to be URL-encoded
python3 -c "
import urllib.parse
url = 'postgresql://coder:xR7pf7MPgZyIChIXWqwO3srnp0GflgHwG7dMC7gvdHI=@coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com:5432/coder'
print('Original:', url)
print('Encoded:', urllib.parse.quote(url, safe=':/?#[]@!$&\'()*+,;='))
"
```

## Priority Order

1. **Step 1**: Check environment variables in container
2. **Step 7**: Try plain string secret format
3. **Step 2**: Test database connectivity
4. **Step 3**: Verify IAM permissions
5. **Step 4**: Check network security groups

## Expected Outcome

Once working, logs should show:
```
Started HTTP listener at http://0.0.0.0:3000
Using PostgreSQL database at coder-postgres.cunxsqwqr7rg.us-east-1.rds.amazonaws.com:5432
```

Instead of:
```
Using built-in PostgreSQL (/home/coder/.config/coderv2/postgres)
```