#!/usr/bin/env bash
# Run from an administrator's AWS CloudShell session after reviewing dev-policy.json.
# Updates only the existing dev managed policy; retains the previous version for rollback.
set -euo pipefail
export AWS_PAGER=""
policy_file=${1:?Usage: restrict-dev-access.sh /path/to/dev-policy.json}
account=481088928034
user=cloud-resume-dev
policy_arn="arn:aws:iam::$account:policy/cloud-resume-dev-policy"
identity=$(aws sts get-caller-identity --output json)
if [ "$(jq -r .Account <<< "$identity")" != "$account" ] || [ "$(jq -r .Arn <<< "$identity")" = "arn:aws:iam::$account:user/$user" ]; then
  echo 'Use the administrator session in the project account, not the dev identity.' >&2
  exit 1
fi
jq -e '.Version == "2012-10-17" and (.Statement | length > 0)' "$policy_file" >/dev/null
attached=$(aws iam list-attached-user-policies --user-name "$user" --output json)
inline=$(aws iam list-user-policies --user-name "$user" --output json)
groups=$(aws iam list-groups-for-user --user-name "$user" --output json)
if ! jq -e --arg arn "$policy_arn" '.AttachedPolicies | length == 1 and .[0].PolicyArn == $arn' <<< "$attached" >/dev/null ||
   ! jq -e '.PolicyNames | length == 0' <<< "$inline" >/dev/null ||
   ! jq -e '.Groups | length == 0' <<< "$groups" >/dev/null; then
  echo 'Unexpected additional developer permissions. Stop and review policies/groups before proceeding.' >&2
  exit 1
fi
versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" --output json)
if [ "$(jq '.Versions | length' <<< "$versions")" -ge 5 ]; then
  echo 'Policy has five versions. Review and remove an obsolete non-default version before retrying.' >&2
  exit 1
fi
previous=$(jq -r '.Versions[] | select(.IsDefaultVersion) | .VersionId' <<< "$versions")
aws iam create-policy-version --policy-arn "$policy_arn" --policy-document "file://$policy_file" --set-as-default --query 'PolicyVersion.VersionId' --output text
printf 'Developer policy restricted. Previous policy version retained: %s\n' "$previous"
printf 'Administrative rollback if needed: aws iam set-default-policy-version --policy-arn %s --version-id %s\n' "$policy_arn" "$previous"
