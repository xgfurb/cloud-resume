# ============================================================
# GITHUB ACTIONS OIDC — Phase 5
# ============================================================
# This file sets up keyless authentication between GitHub
# Actions and AWS using OpenID Connect (OIDC).
#
# Instead of storing AWS access keys in GitHub Secrets,
# GitHub Actions presents a short-lived JWT token to AWS.
# AWS verifies the token came from your specific repo and
# grants temporary credentials that expire in 1 hour.
#
# Benefits:
#   - No long-lived credentials stored anywhere
#   - Credentials auto-expire — no rotation needed
#   - Scoped to your specific repo and branches
#   - If GitHub is compromised, there are no keys to steal
# ============================================================


# ────────────────────────────────────────────────────────────
# OIDC IDENTITY PROVIDER
# ────────────────────────────────────────────────────────────
# This tells AWS "trust tokens issued by GitHub's OIDC
# provider." It's a one-time setup per AWS account — even
# if you had 10 repos, you'd only need one provider.
#
# The thumbprint_list is a hash of GitHub's TLS certificate.
# AWS uses it to verify the connection to GitHub is authentic.
# ────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint — SHA-1 of GitHub's OIDC TLS certificate.
  # Published at https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aca2"]

  tags = {
    Project = "cloud-resume"
  }
}


# ────────────────────────────────────────────────────────────
# IAM ROLE FOR GITHUB ACTIONS
# ────────────────────────────────────────────────────────────
# This role is what GitHub Actions "assumes" when it needs
# to interact with AWS. The trust policy restricts it to:
#   - Only tokens from GitHub's OIDC provider
#   - Only your specific repository
#   - Only the main branch
#
# The permission policy (below) limits what the role can do
# to only the actions needed for deployment.
# ────────────────────────────────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name = "cloud-resume-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # aud = audience — must match the client_id above
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # sub = subject — restricts to your repo only.
            # Wildcard allows both push-to-main and pull_request events,
            # which have different sub claims (ref:refs/heads/main vs pull_request).
            "token.actions.githubusercontent.com:sub" = "repo:xgfurb/cloud-resume:*"
          }
        }
      }
    ]
  })

  tags = {
    Project = "cloud-resume"
  }
}


# ────────────────────────────────────────────────────────────
# PERMISSIONS FOR GITHUB ACTIONS ROLE
# ────────────────────────────────────────────────────────────
# Scoped to only what the CI/CD pipeline needs:
#   - S3: sync frontend files to the bucket
#   - CloudFront: invalidate cache after deploy
#   - Lambda: update the function code
#
# This is least privilege — if these credentials were somehow
# compromised, the attacker could only update your site and
# Lambda function, not create new resources or access billing.
# ────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────
# TERRAFORM OPERATIONS POLICY
# ────────────────────────────────────────────────────────────
# Additional permissions needed by the terraform-plan and
# terraform-apply workflows: state backend access and full
# read/write on all project-managed resources.
# ────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "cloud-resume-terraform-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration", "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::czresume-terraform-state",
          "arn:aws:s3:::czresume-terraform-state/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:481088928034:table/czresume-terraform-locks"
      },
      {
        Sid    = "S3ReadAll"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation", "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock", "s3:GetBucketVersioning",
          "s3:GetBucketTagging", "s3:GetEncryptionConfiguration",
          "s3:GetBucketWebsite", "s3:GetBucketCORS", "s3:GetBucketACL",
          "s3:GetBucketLogging", "s3:GetBucketRequestPayment",
          "s3:GetAccelerateConfiguration", "s3:GetBucketObjectLockConfiguration",
          "s3:GetReplicationConfiguration", "s3:GetLifecycleConfiguration",
          "s3:ListBucket", "s3:ListAllMyBuckets",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Manage"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket",
          "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:PutBucketPublicAccessBlock", "s3:PutBucketVersioning",
          "s3:PutBucketTagging", "s3:PutEncryptionConfiguration"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone", "route53:DeleteHostedZone",
          "route53:GetHostedZone", "route53:ListHostedZones",
          "route53:ListHostedZonesByName", "route53:ChangeResourceRecordSets",
          "route53:GetChange", "route53:ListResourceRecordSets",
          "route53:ListTagsForResource", "route53:ChangeTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ACM"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate", "acm:DeleteCertificate",
          "acm:DescribeCertificate", "acm:ListCertificates",
          "acm:ListTagsForCertificate", "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontManage"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution", "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution", "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig", "cloudfront:ListDistributions",
          "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl", "cloudfront:GetOriginAccessControl",
          "cloudfront:GetOriginAccessControlConfig", "cloudfront:ListOriginAccessControls",
          "cloudfront:ListTagsForResource", "cloudfront:TagResource",
          "cloudfront:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBList"
        Effect = "Allow"
        Action = ["dynamodb:ListTables"]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable", "dynamodb:DeleteTable",
          "dynamodb:DescribeTable", "dynamodb:UpdateTable",
          "dynamodb:ListTagsOfResource", "dynamodb:TagResource",
          "dynamodb:UntagResource", "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:UpdateItem", "dynamodb:DeleteItem",
          "dynamodb:DescribeContinuousBackups", "dynamodb:DescribeTimeToLive"
        ]
        Resource = [
          "arn:aws:dynamodb:us-east-1:481088928034:table/cloud-resume-*",
          "arn:aws:dynamodb:us-east-1:481088928034:table/czresume-*"
        ]
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:GetFunction", "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration", "lambda:AddPermission",
          "lambda:RemovePermission", "lambda:GetPolicy",
          "lambda:ListTags", "lambda:TagResource", "lambda:UntagResource",
          "lambda:GetFunctionCodeSigningConfig"
        ]
        Resource = "arn:aws:lambda:us-east-1:481088928034:function:cloud-resume-*"
      },
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = [
          "apigateway:GET", "apigateway:POST",
          "apigateway:PUT", "apigateway:DELETE", "apigateway:PATCH"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags"
        ]
        Resource = [
          "arn:aws:iam::481088928034:role/cloud-resume-*",
          "arn:aws:iam::481088928034:policy/cloud-resume-*"
        ]
      },
      {
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::481088928034:role/cloud-resume-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["lambda.amazonaws.com", "apigateway.amazonaws.com"]
          }
        }
      },
      {
        Sid      = "IAMOIDCList"
        Effect   = "Allow"
        Action   = ["iam:ListOpenIDConnectProviders"]
        Resource = "*"
      },
      {
        Sid    = "IAMOIDCProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags"
        ]
        Resource = "arn:aws:iam::481088928034:oidc-provider/token.actions.githubusercontent.com"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "cloud-resume-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3: upload and delete files in the site bucket
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        # CloudFront: invalidate cached files after deploy
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation"
        ]
        Resource = aws_cloudfront_distribution.site.arn
      },
      {
        # Lambda: update the function code
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode"
        ]
        Resource = aws_lambda_function.visitor_counter.arn
      }
    ]
  })
}
