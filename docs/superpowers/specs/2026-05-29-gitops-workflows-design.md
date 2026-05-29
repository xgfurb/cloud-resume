# GitOps Workflows Design

**Date:** 2026-05-29
**Status:** Approved

## Overview

Add a complete GitOps pipeline to the cloud resume project. Deployment workflows for frontend and backend already exist; this design adds PR validation workflows for both, plus a full Terraform plan/apply pipeline with manual approval.

## Workflow Structure

Six workflow files total. Three existing, three new.

| File | Trigger | Purpose |
|---|---|---|
| `frontend-pr.yml` | PR touching `frontend/**` | HTML linting with htmlhint |
| `frontend.yml` | Merge to `main` touching `frontend/**` | Deploy to S3 + CloudFront invalidation *(existing, unchanged)* |
| `backend-pr.yml` | PR touching `backend/**` | Run pytest |
| `backend.yml` | Merge to `main` touching `backend/**` | Test + deploy Lambda *(existing, unchanged)* |
| `terraform-plan.yml` | PR touching `terraform/**` (excl. bootstrap) | fmt check + validate + plan + post PR comment |
| `terraform-apply.yml` | Merge to `main` touching `terraform/**` (excl. bootstrap) | Apply with manual approval gate |

## Terraform Plan Workflow (`terraform-plan.yml`)

**Trigger:** `pull_request` on `terraform/**`, excluding `terraform/bootstrap/**`

**Permissions:** `id-token: write`, `contents: read`, `pull-requests: write`

**Steps:**
1. Checkout
2. Setup Terraform
3. Configure AWS credentials via OIDC (`vars.AWS_ROLE_ARN`)
4. `terraform init` against the S3 backend
5. `terraform fmt -check` — fails if any file is not formatted
6. `terraform validate` — catches syntax and config errors
7. `terraform plan -no-color` — runs real plan against live state
8. Post plan output as a PR comment via `actions/github-script`

The PR comment is **created on first run and updated on subsequent pushes** to the same PR — one comment per PR, not one per push. This keeps the PR timeline clean.

## Terraform Apply Workflow (`terraform-apply.yml`)

**Trigger:** `push` to `main` on `terraform/**`, excluding `terraform/bootstrap/**`

**Permissions:** `id-token: write`, `contents: read`

**Environment:** `production` (GitHub Environment with required reviewer)

**Steps:**
1. Checkout
2. Setup Terraform
3. Configure AWS credentials via OIDC
4. `terraform init`
5. `terraform apply -auto-approve`

The `production` environment pauses the workflow and sends a notification before the apply job runs. The human approval is the gate; `-auto-approve` suppresses the interactive CLI prompt.

Apply runs a fresh plan-and-apply (does not reuse the PR plan artifact). Safe for a single-developer project and simpler to reason about.

## Frontend PR Workflow (`frontend-pr.yml`)

**Trigger:** `pull_request` on `frontend/**`

**Permissions:** `contents: read`

**Steps:**
1. Checkout
2. Run `npx htmlhint frontend/**/*.html`

`htmlhint` catches missing doctype, unclosed tags, duplicate IDs, missing alt attributes. No Node project setup required — single npx call.

## Backend PR Workflow (`backend-pr.yml`)

**Trigger:** `pull_request` on `backend/**`

**Permissions:** `contents: read`

**Steps:**
1. Checkout
2. Set up Python 3.12
3. Install `boto3`, `moto`, `pytest`
4. Run `pytest backend/counter/test_counter.py -v`

Mirrors the test step in `backend.yml`. Duplication is intentional — test failures block the PR rather than being caught post-merge.

## Branch Protection

Branch protection rules on `main` enforce the PR checks as merge requirements. Without this, direct pushes to `main` bypass all validation.

**Required status checks:**
- `frontend-pr` / htmlhint
- `backend-pr` / pytest
- `terraform-plan` / plan

**Additional rules:**
- Require a pull request before merging
- Require status checks to pass before merging
- Do not allow bypassing the above settings

Configured in: GitHub repo → Settings → Branches → Add rule for `main`.

## One-Time GitHub Setup

Before workflows are active, two things must be configured manually in GitHub:

1. **`production` environment** — Settings → Environments → New environment → name it `production` → add yourself as a required reviewer
2. **Branch protection rule** — Settings → Branches → Add branch protection rule for `main` → enable required status checks (listed above) and require PRs before merging

## Variables Required

These GitHub Actions variables are already in use by existing workflows and carry over:

| Variable | Value |
|---|---|
| `vars.AWS_ROLE_ARN` | ARN of the `cloud-resume-github-actions` IAM role |
| `vars.S3_BUCKET_NAME` | Name of the frontend S3 bucket |
| `vars.CLOUDFRONT_DISTRIBUTION_ID` | CloudFront distribution ID |
