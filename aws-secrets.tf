# AWS Secrets Manager configuration for Coder database credentials
resource "aws_secretsmanager_secret" "coder_db_url" {
  name        = "coder-postgres-url"
  description = "PostgreSQL connection URL for Coder application"
  
  tags = {
    Name        = "Coder Database URL"
    Application = "Coder"
  }
}

resource "aws_secretsmanager_secret_version" "coder_db_url" {
  secret_id = aws_secretsmanager_secret.coder_db_url.id
  secret_string = jsonencode({
    CODER_POSTGRES_URL = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.coder_postgres.endpoint}/coder"
  })
  
  depends_on = [aws_db_instance.coder_postgres]
}

# IAM role for ECS task execution with Secrets Manager access
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "coder-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "coder-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.coder_db_url.arn
        ]
      }
    ]
  })
}

# Output the secret ARN for use in ECS task definition
output "db_secret_arn" {
  description = "ARN of the database URL secret"
  value       = aws_secretsmanager_secret.coder_db_url.arn
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}