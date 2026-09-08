# CI can read IAM configuration, but only an administrator can change it.
# See docs/deployment.md before rolling out these role and workflow changes.

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

resource "aws_iam_role" "github_actions" {
  name = "cloud-resume-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:xgfurb/cloud-resume:environment:production"
        }
      }
    }]
  })
  tags = { Project = "cloud-resume" }
}

resource "aws_iam_role" "github_actions_plan" {
  name = "cloud-resume-github-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:xgfurb/cloud-resume:pull_request"
        }
      }
    }]
  })
  tags = { Project = "cloud-resume" }
}

resource "aws_iam_role" "github_actions_frontend" {
  name = "cloud-resume-github-frontend"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:xgfurb/cloud-resume:ref:refs/heads/main"
        }
      }
    }]
  })
  tags = { Project = "cloud-resume" }
}

resource "aws_iam_role_policy" "terraform_read" {
  for_each = {
    plan  = aws_iam_role.github_actions_plan.id
    apply = aws_iam_role.github_actions.id
  }
  name = "cloud-resume-terraform-read"
  role = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCertificate"
        Effect   = "Allow"
        Action   = ["acm:DescribeCertificate", "acm:ListTagsForCertificate"]
        Resource = aws_acm_certificate.site.arn
      },
      {
        Sid      = "ReadDistribution"
        Effect   = "Allow"
        Action   = ["cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:ListTagsForResource"]
        Resource = aws_cloudfront_distribution.site.arn
      },
      {
        Sid      = "ReadOriginControl"
        Effect   = "Allow"
        Action   = ["cloudfront:GetOriginAccessControl", "cloudfront:GetOriginAccessControlConfig"]
        Resource = "arn:aws:cloudfront::481088928034:origin-access-control/${aws_cloudfront_origin_access_control.site.id}"
      },
      {
        Sid      = "ReadResponseHeaders"
        Effect   = "Allow"
        Action   = ["cloudfront:GetResponseHeadersPolicy"]
        Resource = "arn:aws:cloudfront::481088928034:response-headers-policy/*"
      },
      {
        Sid      = "ReadCounterMetadata"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeContinuousBackups", "dynamodb:DescribeTable", "dynamodb:DescribeTimeToLive", "dynamodb:ListTagsOfResource"]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        Sid      = "ReadProjectRoles"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies", "iam:ListRoleTags"]
        Resource = [aws_iam_role.lambda_role.arn, aws_iam_role.github_actions.arn, aws_iam_role.github_actions_plan.arn, aws_iam_role.github_actions_frontend.arn]
      },
      {
        Sid      = "ReadOIDC"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviderTags"]
        Resource = aws_iam_openid_connect_provider.github.arn
      },
      {
        Sid      = "ReadCounterFunction"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:GetFunctionCodeSigningConfig", "lambda:GetPolicy", "lambda:ListTags", "lambda:ListVersionsByFunction", "lambda:GetFunctionConcurrency"]
        Resource = aws_lambda_function.visitor_counter.arn
      },
      {
        Sid      = "ReadZone"
        Effect   = "Allow"
        Action   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = aws_route53_zone.main.arn
      },
      {
        Sid      = "ReadDNSChanges"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Sid      = "ReadCounterAPI"
        Effect   = "Allow"
        Action   = ["apigateway:GET"]
        Resource = ["arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.counter_api.id}", "arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.counter_api.id}/*"]
      },
      {
        Sid      = "ReadSiteBucketConfiguration"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetReplicationConfiguration", "s3:GetLifecycleConfiguration", "s3:GetAccelerateConfiguration"]
        Resource = aws_s3_bucket.site.arn
      },
      {
        Sid      = "ReadStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::czresume-terraform-state"
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::czresume-terraform-state/cloud-resume/terraform.tfstate"
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::czresume-terraform-state/cloud-resume/terraform.tfstate.tflock"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "cloud-resume-terraform-policy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteState"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::czresume-terraform-state/cloud-resume/terraform.tfstate"
      },
      {
        Sid      = "ManageSiteBucket"
        Effect   = "Allow"
        Action   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutBucketVersioning", "s3:PutBucketTagging", "s3:PutEncryptionConfiguration"]
        Resource = aws_s3_bucket.site.arn
      },
      {
        Sid      = "ManageZone"
        Effect   = "Allow"
        Action   = ["route53:DeleteHostedZone", "route53:ChangeResourceRecordSets", "route53:ChangeTagsForResource"]
        Resource = aws_route53_zone.main.arn
      },
      {
        Sid      = "ManageCertificate"
        Effect   = "Allow"
        Action   = ["acm:DeleteCertificate", "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate"]
        Resource = aws_acm_certificate.site.arn
      },
      {
        Sid      = "ManageDistribution"
        Effect   = "Allow"
        Action   = ["cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution", "cloudfront:TagResource", "cloudfront:UntagResource"]
        Resource = aws_cloudfront_distribution.site.arn
      },
      {
        Sid      = "ManageOriginControl"
        Effect   = "Allow"
        Action   = ["cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl"]
        Resource = "arn:aws:cloudfront::481088928034:origin-access-control/${aws_cloudfront_origin_access_control.site.id}"
      },
      {
        Sid      = "ManageResponseHeaders"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateResponseHeadersPolicy", "cloudfront:UpdateResponseHeadersPolicy", "cloudfront:DeleteResponseHeadersPolicy"]
        Resource = "arn:aws:cloudfront::481088928034:response-headers-policy/*"
      },
      {
        Sid      = "ManageCounterTable"
        Effect   = "Allow"
        Action   = ["dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:UpdateTable", "dynamodb:UpdateContinuousBackups", "dynamodb:TagResource", "dynamodb:UntagResource"]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        Sid      = "ManageCounterFunction"
        Effect   = "Allow"
        Action   = ["lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:AddPermission", "lambda:RemovePermission", "lambda:TagResource", "lambda:UntagResource", "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency"]
        Resource = aws_lambda_function.visitor_counter.arn
      },
      {
        Sid      = "ManageCounterAPI"
        Effect   = "Allow"
        Action   = ["apigateway:POST", "apigateway:PUT", "apigateway:DELETE", "apigateway:PATCH"]
        Resource = ["arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.counter_api.id}", "arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.counter_api.id}/*"]
      },
      {
        Sid       = "PassLambdaExecutionRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = aws_iam_role.lambda_role.arn
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "cloud-resume-deploy-policy"
  role = aws_iam_role.github_actions_frontend.id

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
      }
    ]
  })
}
