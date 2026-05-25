# ============================================================
# BOOTSTRAP — Remote State Backend
# ============================================================
# This standalone Terraform config creates the S3 bucket and
# DynamoDB table used to store Terraform state remotely.
#
# WHY THIS EXISTS SEPARATELY:
# Terraform can't manage the backend that stores its own state
# (chicken-and-egg problem). So we create the backend
# resources in this bootstrap project, which uses local state.
# The main project then references these resources in its
# backend config.
#
# THIS IS RUN ONCE. After the bucket and table exist, you
# rarely (if ever) touch this config again.
#
# USAGE:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   # Then configure the main project's backend block
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}


# ────────────────────────────────────────────────────────────
# S3 BUCKET — State file storage
# ────────────────────────────────────────────────────────────
# Stores the terraform.tfstate file. This is the single
# source of truth for what infrastructure Terraform manages.
#
# Security measures:
#   - Versioning: keeps history of every state change so you
#     can recover from corruption or accidental deletion
#   - Server-side encryption: state files can contain
#     sensitive data (resource IDs, ARNs, etc.)
#   - Public access blocked: state should never be public
# ────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = "czresume-terraform-state"

  # Prevent accidental deletion of this bucket. If you ever
  # need to destroy it, you must first set this to false
  # and apply, then destroy.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project = "cloud-resume"
  }
}

# Enable versioning — every state file update creates a new
# version. If state gets corrupted, you can roll back to a
# previous version in the S3 console.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest using AES-256 (SSE-S3). This is
# AWS-managed encryption — no KMS key needed, no extra cost.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files should never be
# publicly accessible under any circumstances.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# ────────────────────────────────────────────────────────────
# DYNAMODB TABLE — State locking
# ────────────────────────────────────────────────────────────
# Prevents concurrent terraform apply runs from corrupting
# state. When Terraform starts an apply, it writes a lock
# entry to this table. If another apply tries to run, it
# sees the lock and waits (or errors out).
#
# The table uses a single partition key "LockID" — this is
# the format Terraform's S3 backend expects. Don't change it.
# ────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "czresume-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = "cloud-resume"
  }
}


# ────────────────────────────────────────────────────────────
# OUTPUTS
# ────────────────────────────────────────────────────────────
# These values are needed when configuring the backend block
# in the main Terraform project.
# ────────────────────────────────────────────────────────────

output "state_bucket_name" {
  description = "S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}
