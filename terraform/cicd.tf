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
        Sid    = "ReadInfrastructure"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate",
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:ListDistributions",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:ListTagsForResource",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:GetItem",
          "dynamodb:ListTables",
          "dynamodb:ListTagsOfResource",
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListOpenIDConnectProviderTags",
          "iam:ListOpenIDConnectProviders",
          "iam:ListRolePolicies",
          "iam:ListRoleTags",
          "lambda:GetFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetPolicy",
          "lambda:ListTags",
          "lambda:ListVersionsByFunction",
          "route53:GetChange",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
          "apigateway:GET",
        ]
        Resource = "*"
      },
      {
        Sid      = "ReadSiteBucketConfiguration"
        Effect   = "Allow"
        Action   = ["s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetReplicationConfiguration", "s3:GetLifecycleConfiguration", "s3:GetAccelerateConfiguration"]
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
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::czresume-terraform-state/cloud-resume/terraform.tfstate"
      },
      {
        Sid    = "SiteBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation", "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock", "s3:GetBucketVersioning",
          "s3:GetBucketTagging", "s3:GetEncryptionConfiguration",
          "s3:GetBucketWebsite", "s3:GetBucketCORS", "s3:GetBucketACL",
          "s3:GetBucketLogging", "s3:GetBucketRequestPayment",
          "s3:GetAccelerateConfiguration", "s3:GetBucketObjectLockConfiguration",
          "s3:GetReplicationConfiguration", "s3:GetLifecycleConfiguration",
          "s3:ListBucket",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject"
        ]
        Resource = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
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
        Resource = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
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
        Sid      = "DynamoDBList"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables"]
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
          "lambda:GetFunctionCodeSigningConfig", "lambda:ListVersionsByFunction"
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
        Sid      = "PassLambdaExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.lambda_role.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
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
