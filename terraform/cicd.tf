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
