mock_provider "aws" {
  override_during = plan
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
}
