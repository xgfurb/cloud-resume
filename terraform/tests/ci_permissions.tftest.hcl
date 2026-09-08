mock_provider "aws" {
  override_during = plan
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-1:481088928034:table/cloud-resume-counter" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:481088928034:function:cloud-resume-counter" }
  }
  mock_resource "aws_route53_zone" {
    defaults = { arn = "arn:aws:route53:::hostedzone/TEST" }
  }
  mock_resource "aws_cloudfront_origin_access_control" {
    defaults = { id = "TEST" }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = { id = "TEST", execution_arn = "arn:aws:execute-api:us-east-1:481088928034:TEST" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::czresume.com" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::481088928034:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = { arn = "arn:aws:cloudfront::481088928034:distribution/TEST" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::481088928034:role/cloud-resume-lambda-role" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn                       = "arn:aws:acm:us-east-1:481088928034:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = []
    }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:us-east-1:481088928034:certificate/00000000-0000-0000-0000-000000000000" }
  }
}

run "ci_permissions" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.github_actions.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:xgfurb/cloud-resume:environment:production"
    error_message = "Infrastructure writes must require the production environment."
  }
  assert {
    condition     = jsondecode(aws_iam_role.github_actions_plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:xgfurb/cloud-resume:pull_request"
    error_message = "The plan role must only trust PR subjects."
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.github_actions_terraform.policy).Statement : alltrue([for a in try(tolist(s.Action), [s.Action]) : !startswith(a, "iam:") || a == "iam:PassRole"])])
    error_message = "CI must not modify IAM roles, policies, or the OIDC provider."
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.terraform_read["plan"].policy).Statement : alltrue([for a in try(tolist(s.Action), [s.Action]) : can(regex(":(Get|List|Describe|GET)", a)) || (s.Sid == "StateLock" && contains(["s3:PutObject", "s3:DeleteObject"], a))])])
    error_message = "The plan role may only read infrastructure and manage its lockfile."
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.github_actions_terraform.policy).Statement : !contains(try(tolist(s.Action), [s.Action]), "s3:PutObject") || !contains(try(tolist(s.Resource), [s.Resource]), "*")])
    error_message = "S3 object writes must not be account-wide."
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.terraform_read["plan"].policy).Statement : !contains(try(tolist(s.Resource), [s.Resource]), "*") && !contains(try(tolist(s.Action), [s.Action]), "dynamodb:GetItem")])
    error_message = "PR planning must not read arbitrary account resources or application data."
  }
  assert {
    condition     = aws_lambda_function.visitor_counter.reserved_concurrent_executions == 2 && aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 1
    error_message = "Public counter execution and request rates must be bounded."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.terraform_read["plan"].policy).Statement : contains(try(tolist(statement.Action), [statement.Action]), "s3:ListBucket") if statement.Sid == "ReadSiteBucketConfiguration"])
    error_message = "The PR role needs bucket-scoped ListBucket so HeadBucket does not produce a false deletion plan."
  }
  assert {
    condition     = contains([for statement in jsondecode(file("${path.module}/bootstrap/dev-policy.json")).Statement : contains(try(tolist(statement.Action), [statement.Action]), "s3:ListBucket") if statement.Sid == "ReadSiteBucketConfiguration"], true)
    error_message = "Developer refresh must retain the site bucket existence check."
  }

}
