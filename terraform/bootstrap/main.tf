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


# ────────────────────────────────────────────────────────────
# DEV IAM USER
# ────────────────────────────────────────────────────────────
# The local development user used to run terraform plan/apply.
# Managed here so permissions are version-controlled and
# applied by an admin rather than configured ad-hoc in the
# AWS console.
#
# IMPORT EXISTING USER BEFORE FIRST APPLY:
#   terraform import aws_iam_user.dev cloud-resume-dev
# ────────────────────────────────────────────────────────────

resource "aws_iam_user" "dev" {
  name = "cloud-resume-dev"

  tags = {
    Project = "cloud-resume"
  }
}

resource "aws_iam_policy" "dev" {
  name        = "cloud-resume-dev-policy"
  description = "Permissions for the cloud-resume-dev user to manage all project infrastructure"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:DeleteBucketTagging",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketLogging",
          "s3:GetBucketCORS",
          "s3:GetBucketACL",
          "s3:GetBucketWebsite",
          "s3:GetBucketRequestPayment",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:ListBucket",
          "s3:ListAllMyBuckets",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
          "route53:ChangeTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ACM"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DeleteCertificate",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:ListDistributions",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:CreateInvalidation",
          "cloudfront:ListTagsForResource",
          "cloudfront:TagResource",
          "cloudfront:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:ListTables",
          "dynamodb:ListTagsOfResource",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive"
        ]
        Resource = "*"
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:ListTags",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:GetFunctionCodeSigningConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMOIDCProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "dev" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev.arn
}
