# GitOps Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PR validation workflows for frontend and backend, plus a full Terraform plan/apply pipeline with manual approval gate, completing a GitOps setup for the cloud resume project.

**Architecture:** Three new workflow files alongside the two existing deploy workflows (which are unchanged). PR workflows validate on every pull request; Terraform apply pauses for manual approval via a GitHub `production` environment before running. A `.htmlhintrc` config makes HTML linting rules explicit.

**Tech Stack:** GitHub Actions, `hashicorp/setup-terraform@v3`, `aws-actions/configure-aws-credentials@v4`, `actions/github-script@v7`, `htmlhint`, `actionlint` (local validation tool), pytest, moto

---

## File Map

| Action | Path |
|---|---|
| Create | `.github/workflows/backend-pr.yml` |
| Create | `.github/workflows/frontend-pr.yml` |
| Create | `.github/workflows/terraform-plan.yml` |
| Create | `.github/workflows/terraform-apply.yml` |
| Create | `.htmlhintrc` |

Existing `.github/workflows/frontend.yml` and `.github/workflows/backend.yml` are **not modified**.

---

## Task 1: Install actionlint for local workflow validation

`actionlint` is a static analysis tool for GitHub Actions workflow files. It catches type errors, invalid expressions, and schema violations before you push.

- [ ] **Step 1: Install actionlint**

```bash
curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
sudo mv actionlint /usr/local/bin/
```

- [ ] **Step 2: Verify installation**

```bash
actionlint --version
```

Expected output: `actionlint 1.x.x`

---

## Task 2: Create backend PR validation workflow

Runs pytest on every pull request that touches `backend/`.

- [ ] **Step 1: Create `.github/workflows/backend-pr.yml`**

```yaml
name: Backend PR Checks

on:
  pull_request:
    paths:
      - 'backend/**'

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: pip install boto3 moto pytest

      - name: Run tests
        run: pytest backend/counter/test_counter.py -v
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/backend-pr.yml
```

Expected output: no errors (silent = pass)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/backend-pr.yml
git commit -m "ci: add backend PR validation workflow"
```

---

## Task 3: Create frontend PR validation workflow

Runs `htmlhint` on every pull request that touches `frontend/`. A `.htmlhintrc` makes the rule set explicit and version-controlled.

- [ ] **Step 1: Create `.htmlhintrc` in the repo root**

```json
{
  "tagname-lowercase": true,
  "attr-lowercase": true,
  "attr-value-double-quotes": true,
  "doctype-first": true,
  "tag-pair": true,
  "id-unique": true,
  "src-not-empty": true,
  "attr-no-duplication": true,
  "title-require": true,
  "alt-require": true,
  "spec-char-escape": false
}
```

> `spec-char-escape` is disabled because resume content often uses characters like `&` in plain text that are not security-relevant in a static context. Enable it if you want strict escaping.

- [ ] **Step 2: Test htmlhint locally to confirm no false positives**

```bash
npx --yes htmlhint 'frontend/**/*.html'
```

Expected: no errors. If errors appear, adjust `.htmlhintrc` to turn off rules that flag intentional patterns in your HTML before continuing.

- [ ] **Step 3: Create `.github/workflows/frontend-pr.yml`**

```yaml
name: Frontend PR Checks

on:
  pull_request:
    paths:
      - 'frontend/**'

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run htmlhint
        run: npx --yes htmlhint 'frontend/**/*.html'
```

- [ ] **Step 4: Validate with actionlint**

```bash
actionlint .github/workflows/frontend-pr.yml
```

Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/frontend-pr.yml .htmlhintrc
git commit -m "ci: add frontend PR validation workflow"
```

---

## Task 4: Create Terraform plan workflow

Runs `fmt -check`, `validate`, and `plan` on every PR touching `terraform/` (excluding `bootstrap/`). Posts the plan output as a PR comment — updated on each push, not duplicated.

- [ ] **Step 1: Create `.github/workflows/terraform-plan.yml`**

```yaml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '!terraform/bootstrap/**'

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Format Check
        working-directory: terraform
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        working-directory: terraform
        run: terraform validate

      - name: Terraform Plan
        id: plan
        working-directory: terraform
        run: terraform plan -no-color 2>&1 | tee /tmp/plan.txt
        continue-on-error: true

      - name: Post Plan as PR Comment
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('/tmp/plan.txt', 'utf8');
            const truncated = plan.length > 65000
              ? plan.slice(0, 65000) + '\n...(output truncated)'
              : plan;
            const body = [
              '#### Terraform Plan',
              '<details><summary>Show Plan</summary>',
              '',
              '```',
              truncated,
              '```',
              '</details>',
            ].join('\n');

            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });

            const existing = comments.find(c => c.body.includes('#### Terraform Plan'));

            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: existing.id,
                body,
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body,
              });
            }

      - name: Fail if plan failed
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

> The `continue-on-error: true` on the plan step ensures the comment is always posted even when the plan fails. The final step re-raises the failure after the comment is posted.

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/terraform-plan.yml
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/terraform-plan.yml
git commit -m "ci: add Terraform plan workflow with PR comment"
```

---

## Task 5: Create Terraform apply workflow

Runs `terraform apply` on merge to `main` for any `terraform/` changes. Pauses for manual approval via the `production` GitHub Environment before applying.

- [ ] **Step 1: Create `.github/workflows/terraform-apply.yml`**

```yaml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'
      - '!terraform/bootstrap/**'

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Apply
        working-directory: terraform
        run: terraform apply -auto-approve
```

> `environment: production` is what triggers the approval gate. GitHub pauses the job here and sends a notification. The job won't proceed until a required reviewer approves it in the GitHub Actions UI.

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/terraform-apply.yml
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/terraform-apply.yml
git commit -m "ci: add Terraform apply workflow with manual approval gate"
```

---

## Task 6: One-time GitHub setup (manual, in the browser)

These two steps cannot be done in code — they are GitHub UI configurations that give the workflows their power.

- [ ] **Step 1: Create the `production` environment with a required reviewer**

1. Go to your repo on GitHub → **Settings** → **Environments** → **New environment**
2. Name it exactly `production` (matches `environment: production` in the workflow)
3. Under **Environment protection rules**, enable **Required reviewers**
4. Add your GitHub username as a required reviewer
5. Click **Save protection rules**

- [ ] **Step 2: Enable branch protection on `main`**

1. Go to **Settings** → **Branches** → **Add branch protection rule**
2. Branch name pattern: `main`
3. Enable **Require a pull request before merging**
4. Enable **Require status checks to pass before merging**
5. In the status checks search box, add each of these (they appear after the workflows have run at least once — push the branch first if they don't show yet):
   - `test` (from `backend-pr.yml`)
   - `lint` (from `frontend-pr.yml`)
   - `plan` (from `terraform-plan.yml`)
6. Enable **Do not allow bypassing the above settings**
7. Click **Create**

---

## Task 7: Push branch and open PR to verify end-to-end

- [ ] **Step 1: Push the current branch**

```bash
git push origin security/fix-oidc-thumbprint
```

- [ ] **Step 2: Open a pull request on GitHub**

Navigate to the repo and open a PR from `security/fix-oidc-thumbprint` → `main`.

- [ ] **Step 3: Confirm the PR workflows trigger**

In the PR's **Checks** tab, verify:
- `Backend PR Checks` triggers (if any `backend/` files changed) or is skipped (correct — path filter)
- `Frontend PR Checks` triggers (if any `frontend/` files changed) or is skipped
- `Terraform Plan` triggers and posts a plan comment on the PR

- [ ] **Step 4: Merge the PR and confirm apply triggers with approval gate**

After all checks pass, merge the PR. Navigate to **Actions** → **Terraform Apply** run. Confirm the job pauses at the `production` environment and shows a **Review deployments** button before running `apply`.
