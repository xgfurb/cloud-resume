# Deployment and IAM rollout

Terraform is the only owner of the Lambda package. Backend changes trigger the
same production Terraform workflow as infrastructure changes, including backend
tests and production environment approval. Frontend files use their own role.

## One-time migration

Coordinate this rollout with an administrator before merging the workflow changes.
The existing CI role cannot install the final IAM policies after its write access
has been removed. Use an AWS identity with the specific IAM permissions required by the reviewed plan. The current project dev identity has those permissions.

1. Pause frontend, backend, and infrastructure deployment workflows in GitHub and
   finish or cancel older deployment runs. Keep deployments paused through the
   migration; the old frontend/backend workflows use the role being restricted.
2. Configure the GitHub `production` environment to require your account as reviewer, allow
   self-review for this sole-administrator project, and permit deployments from
   **main only**. Disable administrator bypass. The OIDC environment subject does not itself encode a
   branch, so the environment's branch restriction is required.
3. From the reviewed checkout, use an administrator's short-lived AWS credentials:

   ```bash
   terraform -chdir=terraform init -lockfile=readonly
   terraform -chdir=terraform plan -out=/tmp/cloud-resume-migration.tfplan
   terraform -chdir=terraform apply /tmp/cloud-resume-migration.tfplan
   ```

   Review the plan before applying. It should create two roles, restrict the
   existing role, move the frontend deploy policy to its new role, and create the
   shared read policies. Stop if the plan unexpectedly replaces application
   resources. The full apply also reconciles application changes in this checkout.
   The plan contains state information; keep it private and delete it after use.
4. Set these GitHub Actions variables using the Terraform outputs:

   | Variable | Terraform output | Role access |
   |---|---|---|
   | `AWS_PLAN_ROLE_ARN` | `github_plan_role_arn` | PR infrastructure reads, state read, lockfile writes |
   | `AWS_APPLY_ROLE_ARN` | `github_actions_role_arn` | Production infrastructure writes, no IAM mutation |
   | `AWS_FRONTEND_ROLE_ARN` | `github_frontend_role_arn` | Main branch site sync and CDN invalidation |

   Prefer storing `AWS_APPLY_ROLE_ARN` on the production environment. Keep
   `S3_BUCKET_NAME` and `CLOUDFRONT_DISTRIBUTION_ID` unchanged. The old
   `AWS_ROLE_ARN` variable is no longer used after all workflow changes are merged.
5. Run the new PR checks, merge the reviewed changes, then enable the frontend and
   Terraform deployment workflows. The old `Deploy Backend` workflow is removed.
   Dispatch `Terraform Apply` from main to verify deployment using the restricted
   role. Observe the next frontend deployment and confirm the visitor badge works.

## Ongoing operation

Changes to IAM roles, role policies, the OIDC provider, and bootstrap infrastructure
must be reviewed and applied by an administrator. CI deliberately has no IAM
mutation permission; it can pass only the existing Lambda execution role to Lambda.
Those resources remain in this Terraform state, so IAM changes will appear in PR
plans, but an ordinary CI apply cannot execute them. Apply such changes through
an administrator before running the corresponding production workflow.

The apply role still manages infrastructure within the configured AWS services;
it is a privileged role. Some control-plane permissions remain service-wide.
The separate plan role can read project state, which can contain sensitive values;
only trusted repository contributors should be allowed to run credentialed PRs.
Fork PRs receive static validation without AWS access. A maintainer must review
and plan their changes on a trusted branch before merging.

Runs are serialized per deployment target. A queued run fails if newer main
changes affect that target, preventing an older commit from rolling it back.
Unrelated documentation or frontend changes do not block a backend deployment.
Terraform saves and applies one plan within a run. Production approval gates the
job before planning; it is not approval of the exact saved plan. Review the PR
plan and inspect deployment logs for the final plan.

## Validation

```bash
python -m pip install -r backend/requirements-test.txt
python -m pytest backend/counter/test_counter.py -v
npm ci
npm run lint
npx playwright install chromium
npm test
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
```

Use Python 3.12 for parity with Lambda and Terraform 1.15.4 for parity with CI.
Terraform tests mock AWS and do not create cloud resources. Browser tests fulfill
all network requests locally, including the counter, and never increment the live
counter. To use an installed Chromium, set `CHROMIUM_PATH=/path/to/chromium`.

The Python requirements and npm lockfile pin test dependencies. Track the Terraform
provider lockfile; update it deliberately with `terraform init -upgrade`, then
review the resulting changes and rerun validation. Mock tests check policy contents,
not AWS's effective authorization or GitHub environment settings; verify those
through the first deployment after migration.

## Security hardening follow-up

The required PR gate is `checks`. It waits for reusable Terraform, frontend,
backend, and security workflows; a failed or cancelled job blocks merging.
All PRs run application/security checks, while Terraform still skips live
operations when no relevant infrastructure files changed. Weekly security scans
and Dependabot updates supplement secret scanning and push protection.

The Terraform plan role no longer has application-data reads or account-wide
read access. Infrastructure mutations target the existing project resources.
Creating a new hosted zone, certificate, distribution, or API is an administrative
operation; the CI role is intended to maintain this existing deployment.

CloudFront applies the policy in `terraform/security-headers.json`, including
CSP, HSTS, framing protection, MIME sniffing protection, and a referrer policy.
The counter API hostname in CSP must be updated if the API is replaced. Browser
tests use these same headers. Frontend JavaScript is in local files so CSP can
block inline script execution. Deploy that frontend before approving the first
headers rollout, then verify the live response headers and page behavior.

API Gateway permits a sustained one request per second with a burst of five.
Lambda reserves two concurrent executions. These controls limit execution rate;
they do not authenticate visitors or create a hard dollar spending limit.

### Final developer-policy restriction (administrator required)

`terraform/bootstrap/dev-policy.json` is the reviewed read-only developer policy,
with only Terraform lockfile writes. The bootstrap resource reads this file so
future bootstrap applies preserve the restriction. Its existing AWS policy name
and description remain unchanged to avoid replacing the managed policy.

The current dev identity cannot update its own managed policy. Use the account's
administrator session in AWS CloudShell; no new root access keys are needed.
Review the policy and run:

```bash
bash scripts/restrict-dev-access.sh terraform/bootstrap/dev-policy.json
```

The script checks the account and existing user policies/groups, stops on
unexpected grants, sets a new managed policy version, and retains the old version
for administrative rollback. Do this after the CI migration is verified. Future
IAM/bootstrap changes must use the administrator session. The developer identity
will no longer be able to publish files, mutate infrastructure, or edit IAM roles.

### Security follow-up: bucket refresh and recovery

The administrator completed the developer restriction and detached the legacy
`cloud-resume-terraform-policy` managed policy from the developer user. Root MFA,
no active root access keys, and enabled billing alerts were confirmed by the
account owner on 2026-09-08; these account settings were not independently read
with the restricted developer identity.

The follow-up restores `s3:ListBucket` on the site bucket for developer/PR
refreshes. AWS requires it for `HeadBucket`; without it Terraform can incorrectly
plan to recreate the existing bucket. It does not grant object contents or writes.
It also scopes Lambda logs to its own log group, enables site object versioning,
and enables counter point-in-time recovery. Version storage and backups can add
small usage-based charges.

Before merging/deploying this follow-up, run from a checkout of this revision in
administrator CloudShell:

```bash
python3 scripts/repair-security-permissions.py
```

The script checks the AWS account and expected policy statements, backs up the
four original role policies under `~/cloud-resume-policy-backup-*`, updates the
developer managed policy while retaining its prior version, then updates the
specific role grants. If an API call fails, earlier successful changes remain;
use the printed backups and inspect the failure before retrying. The script does
not delete policy versions automatically.

Rerun PR checks and review a fresh plan after this step. Do not apply the earlier
local plan that incorrectly proposed recreating the site bucket. The earlier
security-header/counter-limit deployment is still pending; deploy the latest
reviewed main revision after this fix is merged.

API/CloudFront access logging and Lambda log retention remain follow-up work;
they require deliberate log destinations, retention, and administrative setup.
State-bucket protections and account-wide audit/credential status remain
unverified by the restricted developer identity.
