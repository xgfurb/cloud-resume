# ============================================================
# BACKEND INFRASTRUCTURE — Phase 3
# ============================================================
# This file defines the visitor counter backend:
#   1. DynamoDB table (stores the count)
#   2. IAM role (permissions for Lambda)
#   3. Lambda function (reads/increments the count)
#   4. API Gateway (exposes Lambda as HTTPS endpoint)
#   5. CORS configuration (restricts access to your domain)
# ============================================================


# ────────────────────────────────────────────────────────────
# DYNAMODB TABLE
# ────────────────────────────────────────────────────────────
# DynamoDB is a NoSQL key-value database. For a visitor
# counter, we only need:
#   - A table with one item
#   - A partition key to identify the item
#   - A numeric attribute for the count
#
# billing_mode = "PAY_PER_REQUEST" means you pay per read/write
# instead of provisioning capacity. For low-traffic use cases
# this is cheaper and simpler — no capacity planning needed.
#
# hash_key is the partition key — the primary way DynamoDB
# identifies items. Think of it like a primary key in SQL.
# ────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "visitor_counter" {
  name         = "cloud-resume-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # attribute defines the schema for the partition key only.
  # DynamoDB is schemaless — other attributes (like "visits")
  # don't need to be declared here, they're added at runtime.
  attribute {
    name = "id"
    type = "S"    # S = String, N = Number, B = Binary
  }

  tags = {
    Project = "cloud-resume"
  }
}

# Seed the table with an initial counter item.
# This creates: { id: "visitors", visit_count: 0 }
# 
# aws_dynamodb_table_item uses Terraform's DynamoDB JSON
# format, which explicitly declares the type of each value:
#   "S" = string, "N" = number (as a string — DynamoDB quirk)
resource "aws_dynamodb_table_item" "initial_count" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key   = aws_dynamodb_table.visitor_counter.hash_key

  item = <<ITEM
{
  "id": {"S": "visitors"},
  "visit_count": {"N": "0"}
}
ITEM

  # lifecycle ignore_changes prevents Terraform from resetting
  # the counter back to 0 on every apply. Without this,
  # terraform apply would overwrite the live count.
  lifecycle {
    ignore_changes = [item]
  }
}


# ────────────────────────────────────────────────────────────
# IAM ROLE FOR LAMBDA
# ────────────────────────────────────────────────────────────
# Lambda functions need an IAM role to operate. The role has
# two parts:
#   1. Trust policy (assume_role_policy) — WHO can use this role
#      Answer: the Lambda service
#   2. Permission policies (attached below) — WHAT the role can do
#      Answer: read/write DynamoDB, write CloudWatch logs
#
# This is the principle of least privilege — Lambda gets
# exactly the permissions it needs and nothing more.
# ────────────────────────────────────────────────────────────

# The role itself — defines that Lambda can assume it
resource "aws_iam_role" "lambda_role" {
  name = "cloud-resume-lambda-role"

  # Trust policy: allows the Lambda service to assume this role.
  # "AssumeRole" is how AWS services authenticate — Lambda says
  # "I want to act as this role" and AWS checks this policy.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "cloud-resume"
  }
}

# Permission policy: what the Lambda function can actually do.
# We scope it to ONLY the visitor counter table, not all
# DynamoDB tables in the account.
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "cloud-resume-lambda-dynamodb"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # DynamoDB permissions — scoped to the counter table only
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",      # read the counter
          "dynamodb:UpdateItem",   # increment the counter
        ]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        # CloudWatch Logs — Lambda needs this to write logs.
        # Without it, you can't debug your function.
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}


# ────────────────────────────────────────────────────────────
# LAMBDA FUNCTION
# ────────────────────────────────────────────────────────────
# The actual code that runs when the API is called.
#
# Lambda expects a .zip file containing your code. The
# data "archive_file" block below zips the Python file
# automatically so you don't have to do it manually.
#
# handler = "lambda_function.handler" means:
#   - File: lambda_function.py
#   - Function: handler()
#
# environment variables pass the table name to the code
# so it's not hardcoded — if you rename the table, you
# only change it in Terraform, not in Python.
# ────────────────────────────────────────────────────────────

# Automatically zip the Lambda code for deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/counter/lambda_function.py"
  output_path = "${path.module}/../backend/counter/lambda_function.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "cloud-resume-counter"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 10          # seconds — default is 3, which can be tight

  # source_code_hash tells Terraform to redeploy the function
  # whenever the code changes. Without it, Terraform wouldn't
  # detect code changes — only config changes.
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables available to the Python code
  # via os.environ["TABLE_NAME"]
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }

  tags = {
    Project = "cloud-resume"
  }
}


# ────────────────────────────────────────────────────────────
# API GATEWAY (HTTP API)
# ────────────────────────────────────────────────────────────
# API Gateway gives your Lambda an HTTPS URL.
#
# We're using the HTTP API type (v2), not REST API (v1).
# HTTP API is simpler, cheaper, and has built-in CORS
# support — REST API is overkill for a single endpoint.
#
# CORS (Cross-Origin Resource Sharing) controls which
# websites can call your API. We restrict it to your
# domain only — without this, anyone could call your
# counter API from their own website.
# ────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "counter_api" {
  name          = "cloud-resume-counter-api"
  protocol_type = "HTTP"

  # CORS configuration — restricts which origins can call the API
  cors_configuration {
    allow_origins = [
      "https://${var.domain_name}",
      "https://www.${var.domain_name}"
    ]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type"]
    max_age       = 3600    # browser caches CORS preflight for 1 hour
  }

  tags = {
    Project = "cloud-resume"
  }
}

# Integration connects API Gateway to Lambda.
# AWS_PROXY means API Gateway passes the full HTTP request
# to Lambda and returns Lambda's response directly —
# no request/response transformation needed.
resource "aws_apigatewayv2_integration" "counter_integration" {
  api_id                 = aws_apigatewayv2_api.counter_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  payload_format_version = "2.0"    # v2 format — simpler event structure
}

# Route defines which HTTP path/method triggers the integration.
# "GET /count" means: when someone makes a GET request to /count,
# trigger the Lambda function.
resource "aws_apigatewayv2_route" "counter_route" {
  api_id    = aws_apigatewayv2_api.counter_api.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.counter_integration.id}"
}

# Stage is a deployment environment (like dev, staging, prod).
# "$default" is a special stage that doesn't add a path prefix
# to your URL — so it's /count, not /prod/count.
#
# auto_deploy = true means every change is live immediately
# without a manual deployment step.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.counter_api.id
  name        = "$default"
  auto_deploy = true

  # Throttling prevents abuse — limits how many requests
  # per second your API will accept.
  default_route_settings {
    throttling_burst_limit = 10    # max concurrent requests
    throttling_rate_limit  = 5     # sustained requests per second
  }

  tags = {
    Project = "cloud-resume"
  }
}

# Permission grant: allows API Gateway to invoke the Lambda
# function. Without this, API Gateway gets "Access Denied"
# when it tries to trigger your function.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.counter_api.execution_arn}/*/*"
}
