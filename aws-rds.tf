# RDS PostgreSQL instance for Coder persistent storage
# Variables
variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
  default     = null # Will use default VPC if not specified
}

variable "subnet_ids" {
  description = "List of subnet IDs for RDS (private subnets recommended)"
  type        = list(string)
  default     = null # Will auto-discover if not specified
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "coder"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# Data sources to get default VPC and subnets if not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_ids == null ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  vpc_id     = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = var.subnet_ids != null ? var.subnet_ids : data.aws_subnets.default[0].ids
}

# DB subnet group
resource "aws_db_subnet_group" "coder_db_subnet_group" {
  name       = "coder-db-subnet-group"
  subnet_ids = local.subnet_ids

  tags = {
    Name = "Coder DB subnet group"
  }
}

# Security group for RDS
resource "aws_security_group" "coder_rds_sg" {
  name_prefix = "coder-rds-"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.coder_ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Coder RDS Security Group"
  }
}

# Security group for ECS (to be referenced in ECS service)
resource "aws_security_group" "coder_ecs_sg" {
  name_prefix = "coder-ecs-"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Coder ECS Security Group"
  }
}

# RDS PostgreSQL instance
resource "aws_db_instance" "coder_postgres" {
  identifier = "coder-postgres"

  # Engine configuration
  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  # Storage configuration
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type         = "gp2"
  storage_encrypted    = true

  # Database configuration
  db_name  = "coder"
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.coder_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.coder_rds_sg.id]
  publicly_accessible   = false

  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # Operational configuration
  skip_final_snapshot       = false
  final_snapshot_identifier = "coder-postgres-final-snapshot"
  deletion_protection       = true

  tags = {
    Name = "Coder PostgreSQL Database"
  }
}

# Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.coder_postgres.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.coder_postgres.port
}

output "database_url" {
  description = "PostgreSQL connection URL for Coder"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.coder_postgres.endpoint}/coder"
  sensitive   = true
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS service"
  value       = aws_security_group.coder_ecs_sg.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS instance"
  value       = aws_security_group.coder_rds_sg.id
}
