# Cloud Resume Challenge

A serverless resume website built as part of the [Cloud Resume Challenge](https://cloudresumechallenge.dev), extended with a production-grade GitOps pipeline and security hardening.

Live at: [czresume.com](https://czresume.com)

## Stack

| Layer | Technology |
|---|---|
| Frontend | HTML/CSS on S3, served via CloudFront |
| Backend | Python Lambda + API Gateway |
| Database | DynamoDB (visitor counter) |
| DNS | Route 53 + ACM (TLS) |
| Email | SimpleLogin aliases via Route 53 DNS |
| IaC | Terraform (remote state in S3) |
| CI/CD | GitHub Actions with OIDC keyless auth |

## Architecture

```
                          ┌─────────────────────────────────────┐
                          │           GitHub Actions             │
  Developer               │                                      │
  opens PR ──────────────▶│  terraform-plan   → posts plan as   │
                          │                     PR comment       │
                          │  backend-pr       → pytest           │
                          │  frontend-pr      → htmlhint         │
                          └──────────────────────────────────────┘
                                       │
                              PR merged to main
                                       │
                          ┌────────────▼─────────────────────────┐
                          │           GitHub Actions             │
                          │                                      │
                          │  frontend  → S3 sync + CDN purge     │
                          │  backend   → pytest → Lambda deploy  │
                          │  terraform → manual approval → apply │
                          └──────────────┬───────────────────────┘
                                         │ OIDC (keyless auth)
                                         ▼
                          ┌──────────────────────────────────────┐
                          │                 AWS                  │
                          │                                      │
                          │  S3 ◀── CloudFront ◀── Route 53     │
                          │  API Gateway ◀── Lambda ◀── DynamoDB│
                          └──────────────────────────────────────┘
```

## CI/CD Pipeline

Every change goes through a pull request. No one pushes directly to `main`.

**On pull request:**
- `terraform/**` → Terraform fmt, validate, plan — plan output posted as a PR comment
- `backend/**` → pytest
- `frontend/**` → htmlhint

**On merge to main:**
- `frontend/**` → sync to S3, invalidate CloudFront cache
- `backend/**` → run tests, zip, deploy to Lambda
- `terraform/**` → pause for manual approval, then `terraform apply`

Authentication between GitHub Actions and AWS uses OpenID Connect (OIDC) — no long-lived credentials stored anywhere.

## Repository Structure

```
.
├── frontend/               # HTML/CSS resume
├── backend/
│   └── counter/            # Lambda function + tests
├── terraform/
│   ├── bootstrap/          # One-time setup: S3 state bucket, DynamoDB lock table, dev IAM user
│   ├── main.tf             # S3 site bucket, Route 53
│   ├── backend.tf          # DynamoDB visitor counter, Lambda, API Gateway
│   ├── cicd.tf             # GitHub Actions OIDC provider + IAM role
│   ├── email.tf            # SimpleLogin DNS records
│   └── providers.tf        # AWS provider + S3 remote backend config
└── .github/workflows/
    ├── frontend.yml        # Deploy frontend on push to main
    ├── backend.yml         # Test and deploy backend on push to main
    ├── frontend-pr.yml     # Lint frontend on pull request
    ├── backend-pr.yml      # Test backend on pull request
    ├── terraform-plan.yml  # Plan on pull request, post as PR comment
    └── terraform-apply.yml # Apply on merge to main (manual approval required)
```

## Local Development

**Prerequisites:** AWS CLI configured, Terraform >= 1.0, Python 3.12

```bash
# Run backend tests
pip install boto3 moto pytest
pytest backend/counter/test_counter.py -v

# Lint frontend
npx htmlhint 'frontend/**/*.html'

# Terraform (main infrastructure)
cd terraform
terraform init
terraform plan

# Terraform (bootstrap — run once, requires admin credentials)
cd terraform/bootstrap
terraform init
terraform apply
```

## Security

- **No stored credentials** — GitHub Actions authenticates via OIDC; temporary credentials expire after 1 hour
- **Least privilege** — GitHub Actions role scoped to deploy actions only; dev IAM user scoped to project resources
- **State protection** — Terraform state bucket has versioning, encryption, public access block, and an explicit Deny on destructive operations
- **Branch protection** — all changes require a PR; `terraform plan` must pass before merging
- **Manual gate** — infrastructure changes require explicit approval before `terraform apply` runs
