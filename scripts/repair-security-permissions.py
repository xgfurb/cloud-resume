#!/usr/bin/env python3
"""Run in administrator CloudShell before deploying this security follow-up.
Backs up existing policies locally; changes only the reviewed project grants.
"""
import datetime
import json
import os
from pathlib import Path
import subprocess

os.environ['AWS_PAGER'] = ''
ACCOUNT = '481088928034'
ROOT = Path(__file__).resolve().parents[1]


def aws(*args):
    result = subprocess.run(['aws', *args, '--output', 'json'], check=True,
                            capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def actions(statement):
    value = statement['Action']
    return value if isinstance(value, list) else [value]


identity = aws('sts', 'get-caller-identity')
if identity['Account'] != ACCOUNT or identity['Arn'].endswith(':user/cloud-resume-dev'):
    raise SystemExit('Use the project administrator CloudShell session.')
backup = Path.home() / ('cloud-resume-policy-backup-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
backup.mkdir(mode=0o700)
changes = []
for role in ['cloud-resume-github-plan', 'cloud-resume-github-actions']:
    name = 'cloud-resume-terraform-read'
    policy = aws('iam', 'get-role-policy', '--role-name', role, '--policy-name', name)['PolicyDocument']
    (backup / (role + '-read.json')).write_text(json.dumps(policy, indent=2))
    matches = [s for s in policy['Statement'] if s.get('Sid') == 'ReadSiteBucketConfiguration' and s['Resource'] == 'arn:aws:s3:::czresume.com']
    if len(matches) != 1:
        raise SystemExit('Unexpected bucket read policy; stopped before writes.')
    matches[0]['Action'] = list(dict.fromkeys(actions(matches[0]) + ['s3:ListBucket']))
    changes.append((role, name, policy))
role = 'cloud-resume-github-actions'
name = 'cloud-resume-terraform-policy'
policy = aws('iam', 'get-role-policy', '--role-name', role, '--policy-name', name)['PolicyDocument']
(backup / 'apply.json').write_text(json.dumps(policy, indent=2))
matches = [s for s in policy['Statement'] if s.get('Sid') == 'ManageCounterTable' and s['Resource'] == f'arn:aws:dynamodb:us-east-1:{ACCOUNT}:table/cloud-resume-counter']
if len(matches) != 1:
    raise SystemExit('Unexpected table policy; stopped before writes.')
matches[0]['Action'] = list(dict.fromkeys(actions(matches[0]) + ['dynamodb:UpdateContinuousBackups']))
changes.append((role, name, policy))
role = 'cloud-resume-lambda-role'
name = 'cloud-resume-lambda-dynamodb'
policy = aws('iam', 'get-role-policy', '--role-name', role, '--policy-name', name)['PolicyDocument']
(backup / 'lambda.json').write_text(json.dumps(policy, indent=2))
matches = [s for s in policy['Statement'] if set(actions(s)) == {'logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents'}]
if len(matches) != 1:
    raise SystemExit('Unexpected Lambda log policy; stopped before writes.')
matches[0]['Resource'] = f'arn:aws:logs:us-east-1:{ACCOUNT}:log-group:/aws/lambda/cloud-resume-counter:*'
changes.append((role, name, policy))
print(f'Original policies saved in {backup}')
# This existing script checks user attachments/groups and retains the previous version.
subprocess.run(['bash', str(ROOT / 'scripts/restrict-dev-access.sh'),
                str(ROOT / 'terraform/bootstrap/dev-policy.json')], check=True)
for role, name, policy in changes:
    aws('iam', 'put-role-policy', '--role-name', role, '--policy-name', name,
        '--policy-document', json.dumps(policy))
    print(f'Updated {role}/{name}')
print('Administrator permission repair complete. Rerun PR checks before deployment.')
