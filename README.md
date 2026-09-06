# Cloud Resume Challenge

A serverless resume website built as part of the [Cloud Resume Challenge](https://cloudresumechallenge.dev), with a GitOps pipeline and security hardening.

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
                          │  backend   → tests → Terraform apply   │
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
- `terraform/**`, `backend/**` → Terraform fmt, validate, policy tests, plan — plan output posted as a PR comment
- `backend/**` → pytest
- `frontend/**` → htmlhint and desktop/mobile browser tests

**On merge to main:**
- `frontend/**` → sync to S3, invalidate CloudFront cache
- `backend/**` → production approval, run tests, deploy Lambda through Terraform
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
    ├── frontend-pr.yml     # Lint frontend on pull request
    ├── backend-pr.yml      # Test backend on pull request and main
    ├── terraform-plan.yml  # Plan on pull request, post as PR comment
    └── terraform-apply.yml # Apply on merge to main (manual approval required)
```

## Local Development

**Prerequisites:** AWS CLI configured, Terraform 1.15.4, Python 3.12, Node.js with npm

```bash
# Run backend tests
pip install -r backend/requirements-test.txt
pytest backend/counter/test_counter.py -v

# Lint frontend
npm ci
npm run lint
npx playwright install chromium
npm test

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
- **Separated CI roles** — PR planning, frontend deployment, and infrastructure deployment use distinct roles; CI cannot modify IAM permissions
- **State protection** — Terraform state bucket has versioning, encryption, public access block, and S3 lockfile locking
- **Branch protection** — configure GitHub to require PRs and passing checks before merging
- **Manual gate** — configure the production environment to require approval and allow main only before enabling infrastructure deployments

See [deployment and IAM rollout](docs/deployment.md) for the required migration, GitHub variables, and validation commands.
