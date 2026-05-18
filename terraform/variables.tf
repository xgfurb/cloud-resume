# ============================================================
# VARIABLES
# ============================================================
# Variables make your Terraform config reusable and keep
# environment-specific values (domain name, region, etc.)
# out of the resource definitions.
#
# Each variable has:
#   - description: what it's for (shown in CLI prompts)
#   - type: the data type (string, number, list, etc.)
#   - default: optional fallback value
#
# Variables without defaults MUST be provided at runtime
# (via terraform.tfvars, CLI flags, or environment variables).
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Root domain name for the resume site"
  type        = string
  default     = "czresume.com"
}

# This controls the S3 bucket name. S3 bucket names are
# globally unique across ALL AWS accounts, so we include
# the domain to avoid collisions.
variable "bucket_name" {
  description = "S3 bucket name for the static site"
  type        = string
  default     = "czresume.com"
}
