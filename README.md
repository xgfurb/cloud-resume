# Cloud Resume Challenge

A serverless resume website built as part of the [Cloud Resume Challenge](https://cloudresumechallenge.dev).

## Stack
- **Frontend:** HTML/CSS hosted on AWS S3, served via CloudFront
- **Backend:** AWS Lambda (Python) + API Gateway
- **Database:** AWS DynamoDB (visitor counter)
- **IaC:** Terraform
- **CI/CD:** GitHub Actions

## Architecture
- Static site deployed to S3 on every push to `main`
- Visitor counter API via Lambda + DynamoDB
- CloudFront for HTTPS and custom domain

## Status
🚧 In progress
