# ============================================================
# PROVIDER CONFIGURATION
# ============================================================
# The "provider" block tells Terraform which cloud platform
# to talk to and how to authenticate. We're using AWS.
#
# Terraform doesn't know how to create AWS resources on its
# own — it downloads a "provider plugin" (like a driver) that
# translates your .tf files into AWS API calls.
#
# Authentication: Terraform automatically reads credentials
# from ~/.aws/credentials (set up via `aws configure`).
# We never hardcode keys in .tf files.
# ============================================================

terraform {
  # required_providers tells Terraform which provider plugin
  # to download and from where (the HashiCorp registry)
  required_providers {
    aws = {
      source  = "hashicorp/aws"   # official AWS provider
      version = "~> 5.0"          # any 5.x version — the ~> means
                                   # "compatible with 5.0, up to but
                                   # not including 6.0"
    }
  }

  # minimum Terraform version required to use this config
  required_version = ">= 1.0"
}

# The provider block configures the AWS plugin itself.
# region determines where resources are created by default.
# us-east-1 is required for CloudFront + ACM certificates.
provider "aws" {
  region = var.aws_region
}
