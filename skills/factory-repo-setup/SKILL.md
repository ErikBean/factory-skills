---
name: factory-repo-setup
description: Sets up a new GitHub repo for the software factory, with a TypeScript AWS CDK app, OpenSpec, a factory config, CI on pull requests, and a GitHub Actions workflow that runs cdk deploy to production on every merge to main. Creates the AWS role that workflow deploys with, using GitHub OIDC rather than stored keys. Use only when the human asks to set up a new repo for the factory or for deploy-on-merge.
---

# Factory repo setup

You set up a repo so the factory can build in it and every merge to `main` deploys to production. Run this once per repo, before the first factory run. Afterwards the flow is: the factory opens a PR, the human merges it, and GitHub Actions runs `cdk deploy`.

This skill creates a GitHub repo and AWS resources. Get the human's yes on the plan before anything outside the local machine changes.

## What it sets up

| Where | What |
| --- | --- |
| Repo | A TypeScript CDK app from `cdk init`, with Jest tests |
| Repo | `openspec/` from `openspec init`, with project context saying merges deploy to production |
| Repo | `factory.config.yaml` with the repo's test and typecheck commands |
| Repo | `.github/workflows/ci.yml`: typecheck, tests and `cdk synth` on every pull request |
| Repo | `.github/workflows/deploy.yml`: the CI checks, then `cdk deploy --all` on every push to `main` |
| Repo | `.github/aws/github-deploy-role.yaml`: the CloudFormation template for the deploy role |
| AWS | The GitHub OIDC identity provider, unless the account already has one |
| AWS | A deploy role that only this repo's `main` branch can assume, and that can only assume the CDK bootstrap roles |
| GitHub | Repo variables `AWS_DEPLOY_ROLE_ARN` and `AWS_REGION` |
| GitHub | A ruleset on `main`: changes only through a pull request whose `test` check passed |

The templates are in [templates/](templates/).

## Step 1: Gather inputs and check tools

Ask for anything the human hasn't given you:

- The repo owner and name, and whether it's private or public.
- The AWS account ID and Region to deploy to, and the AWS CLI profile to set up with. The profile needs rights to create IAM roles and CloudFormation stacks, and is used only during setup.
- Which agent tools to set OpenSpec up for, as `openspec init --tools` takes them.

Check the tools work: `gh auth status`, `aws sts get-caller-identity --profile <profile>`, `node --version` (OpenSpec needs 22.12 or later), `npx --version` and `openspec --version`. The account in the caller identity must match the account the human named. If it doesn't, stop.

## Step 2: Check the AWS account

All of these are read-only:

- **CDK bootstrap.** `aws cloudformation describe-stacks --stack-name CDKToolkit --region <region> --profile <profile>`. If the stack exists, read its `Qualifier` parameter. If it was bootstrapped with a custom qualifier or permissions boundary, the CDK app must use them in `cdk.json`, through `@aws-cdk/core:bootstrapQualifier` and `@aws-cdk/core:permissionsBoundary`.
- **OIDC provider.** `aws iam list-open-id-connect-providers --profile <profile>`. If one ends in `token.actions.githubusercontent.com`, set `CreateOidcProvider` to `false`. An account can only have one.
- **Required boundary.** Ask whether the account requires a permissions boundary on new roles, for example through an SCP. If it does, pass its ARN as `PermissionsBoundaryArn`.

If the account isn't bootstrapped, include bootstrapping in the plan. By default `cdk bootstrap` gives its CloudFormation execution role `AdministratorAccess`, which means every deploy from `main` can change anything in the account. Ask whether to narrow it with `--cloudformation-execution-policies` or a custom permissions boundary.

## Step 3: Confirm the plan

Show the human the plan and wait for a yes:

```text
Repo:        github.com/<owner>/<name> (private)
App:         TypeScript CDK app, Node 24, tests with Jest
Deploys:     every push to main runs `cdk deploy --all` to <account> in <region>
Auth:        GitHub OIDC; role github-deploy-<name> trusts <subject claim>
AWS changes: create stack github-deploy-<name> (deploy role[, OIDC provider])
             [bootstrap CDK in <region>]
First run:   pushing the initial commit deploys the empty starter stack
Protection:  ruleset on main: pull request with a passing `test` check
```

## Step 4: Scaffold the repo locally

1. Make an empty folder named after the repo and run `npx aws-cdk@latest init app --language typescript` in it. `cdk init` requires an empty folder, and it makes the first git commit.
2. Write `.nvmrc` containing `24`.
3. Run `openspec init --tools <tools>`. Add to `openspec/config.yaml`'s `context`: "Merging to main deploys to production through `.github/workflows/deploy.yml`. Every change must leave `npm test` and `npx cdk synth` passing."
4. Copy `templates/workflows/ci.yml` and `templates/workflows/deploy.yml` to `.github/workflows/`, and `templates/github-deploy-role.yaml` to `.github/aws/`.
5. Write `factory.config.yaml`:

   ```yaml
   commands:
     test: npm test
     typecheck: npx tsc --noEmit
   ```

6. Replace the README from `cdk init` with one saying what the repo is for, that merges to `main` deploy to production, and how the deploy role is set up, pointing to `.github/aws/github-deploy-role.yaml`.
7. Run `npm test`, `npx tsc --noEmit` and `npx cdk synth --quiet`. All must pass before you go on.
8. Commit: `Set up CDK app, OpenSpec and deploy-on-merge`.

## Step 5: Create the GitHub repo, without pushing

Run `gh repo create <owner>/<name> --<private|public>`. Don't push yet. Pushing to `main` starts a deploy, and the deploy role doesn't exist yet.

Build the OIDC subject claim the role will trust:

- Get the IDs with `gh api repos/<owner>/<name> -q '.id, .owner.id, .created_at'`.
- Repos created on or after 15 July 2026 use immutable subject claims: `repo:<owner>@<owner-id>/<name>@<repo-id>:ref:refs/heads/main`.
- Older repos use `repo:<owner>/<name>:ref:refs/heads/main`, unless the owner opted in to the immutable form.

## Step 6: Create the AWS side

1. If the plan includes it, run `npx cdk bootstrap aws://<account>/<region> --profile <profile>`, with the options the human chose.
2. Deploy the role:

   ```bash
   aws cloudformation deploy \
     --template-file .github/aws/github-deploy-role.yaml \
     --stack-name github-deploy-<name> \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides RoleName=github-deploy-<name> SubjectClaim=<claim> \
       CdkQualifier=<qualifier> CreateOidcProvider=<true|false> \
       PermissionsBoundaryArn=<arn or empty> \
     --region <region> --profile <profile>
   ```

3. Read the role ARN from the `DeployRoleArn` output: `aws cloudformation describe-stacks --stack-name github-deploy-<name> --query "Stacks[0].Outputs" --region <region> --profile <profile>`.

## Step 7: Connect GitHub to AWS and push

1. Set the repo variables. They aren't secrets.

   ```bash
   gh variable set AWS_DEPLOY_ROLE_ARN --repo <owner>/<name> --body <role-arn>
   gh variable set AWS_REGION --repo <owner>/<name> --body <region>
   ```

2. Add the remote, then push with `git push -u origin main`.
3. Watch the first deploy: `gh run list --repo <owner>/<name> --workflow deploy.yml --limit 1`, then `gh run watch <run-id> --repo <owner>/<name>`.
   - If it fails at `configure-aws-credentials` with "Not authorized to perform sts:AssumeRoleWithWebIdentity", the subject claim is wrong. Check the claim format from step 5, update the stack, and rerun the workflow with `gh run rerun <run-id> --failed`.
   - If `cdk deploy` fails to assume a `cdk-*` role, check the qualifier and bootstrap Region.

## Step 8: Protect main

Add a ruleset so that changes reach `main` only through a pull request whose `test` check has passed. This step is required: without it, a direct push or a failing PR can deploy to production.

```bash
gh api -X POST repos/<owner>/<name>/rulesets --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "test" } ] } },
    { "type": "non_fast_forward" }
  ]
}
JSON
```

Then check it took effect: `gh api repos/<owner>/<name>/rules/branches/main` must list `pull_request` and `required_status_checks`.

GitHub's free plan doesn't enforce rulesets on private repos, so the call can fail there. If it fails, the setup isn't finished. Stop and tell the human `main` is unprotected, and give them the options: make the repo public, or upgrade the plan. Until it's fixed, consider disabling the deploy workflow with `gh workflow disable deploy.yml --repo <owner>/<name>`.

## Step 9: Report

Tell the human the repo URL, the first deploy run's URL and result, the role ARN, and that `main` is protected. Then tell them the next step: run the factory in the new repo, and merge its PR to deploy.
