---
name: factory-repo-setup
description: Sets up a GitHub repo for the software factory, with a TypeScript AWS CDK app, OpenSpec, a factory config, CI on pull requests, and a GitHub Actions workflow that runs cdk deploy to production on every merge to main. Creates the AWS role that workflow deploys with, using GitHub OIDC rather than stored keys, under the account's permissions boundary. Works on a new repo or one with little in it yet. Use only when the human asks to set up a repo for the factory or for deploy-on-merge.
---

# Factory repo setup

You set up a repo so the factory can build in it and every merge to `main` deploys to production. Run this once per repo, before the first factory run. Afterwards the flow is: the factory opens a PR, CI checks it, the human merges it, and GitHub Actions runs `cdk deploy`.

This skill changes GitHub and AWS. Get the human's yes on the plan before anything outside the local machine changes.

## What it sets up

| Where | What |
| --- | --- |
| Repo | A TypeScript CDK app from `cdk init`, with Jest tests, every resource tagged with the project name, and every IAM role carrying the account's permissions boundary |
| Repo | `openspec/` from `openspec init`, with project context covering deploys, the boundary and retained resources |
| Repo | `factory.config.yaml` with the repo's test and typecheck commands |
| Repo | `.github/workflows/ci.yml`: typecheck, tests, `cdk synth` and a check that every synthesized IAM role has a boundary, on every pull request |
| Repo | `.github/workflows/deploy.yml`: the CI checks, then `cdk deploy --all` on every push to `main` |
| Repo | `.github/aws/github-deploy-role.yaml`: the CloudFormation template for the deploy role |
| AWS | The GitHub OIDC identity provider, unless the account already has one |
| AWS | A deploy role that only this repo's `main` branch can assume, that can only assume the CDK bootstrap roles, and that carries the account's boundary |
| GitHub | Repo variables `AWS_DEPLOY_ROLE_ARN` and `AWS_REGION` |
| GitHub | A ruleset on `main`: changes only through a pull request whose `test` check passed |

The templates are in [templates/](templates/).

## Step 1: Gather inputs and check tools

Ask for anything the human hasn't given you:

- The repo owner and name. Whether the repo exists already, and if not, whether it should be private or public.
- The AWS account ID and Region to deploy to, and the AWS CLI profile to set up with. The profile needs rights to create IAM roles and CloudFormation stacks in that account, and is used only during setup.
- Which agent tools to set OpenSpec up for, as `openspec init --tools` takes them.

Check the tools work: `gh auth status`, `aws sts get-caller-identity --profile <profile>`, `node --version` (OpenSpec needs 22.12 or later), `npx --version` and `openspec --version`. The account in the caller identity must match the account the human named. If it doesn't, stop.

If the repo exists, read it. This skill adds a CDK app at the repo root, so it fits a repo that holds little more than a README and a `.gitignore`. If the repo already has an app, stop and ask the human how the CDK app should fit in.

## Step 2: Check the AWS account

All of these are read-only.

**The permissions boundary.** Every role this setup creates, and every role the app's deploys create, must carry a permissions boundary that stops deploys from creating roles more powerful than intended. Read the bootstrap stack:

```bash
aws cloudformation describe-stacks --stack-name CDKToolkit --region <region> --profile <profile> \
  --query "Stacks[0].Parameters"
```

- **Bootstrapped with `InputPermissionsBoundary` set and `ApplyPermissionsBoundaryToAllRoles` true:** that policy is the boundary. Use its name everywhere below. Note the `Qualifier` too.
- **Bootstrapped with no boundary, or with the boundary on the execution role only:** every deploy from `main` can do anything the bootstrap roles can, which by default is `AdministratorAccess`. Stop and tell the human. The account needs a boundary policy and a re-bootstrap with `--custom-permissions-boundary <name> --apply-permissions-boundary-to-all-roles` before this repo deploys to it. Narrowing `--cloudformation-execution-policies` instead isn't enough, because a deploy can still create a role with no boundary.
- **Not bootstrapped:** ask whether code elsewhere owns this account's setup, such as an account bootstrap repo. If it does, the bootstrap belongs there, so stop. If not, add to the plan: create a boundary policy, starting from CDK's example (`cdk bootstrap --show-template` contains it), then bootstrap with `--custom-permissions-boundary <name> --apply-permissions-boundary-to-all-roles`. Never bootstrap with CDK's defaults.

**The OIDC provider.** `aws iam list-open-id-connect-providers --profile <profile>`. If one ends in `token.actions.githubusercontent.com`, set `CreateOidcProvider` to `false`, since an account can only have one.

## Step 3: Confirm the plan

Show the human the plan and wait for a yes:

```text
Repo:        github.com/<owner>/<name> (new, private | existing)
App:         TypeScript CDK app, Node 24, tests with Jest, tagged project=<name>
Deploys:     every push to main runs `cdk deploy --all` to <account> in <region>
Boundary:    <boundary name> on every role, checked in CI
Auth:        GitHub OIDC; role github-deploy-<name> trusts <subject claim>
AWS changes: create stack github-deploy-<name> (deploy role[, OIDC provider])
             [create the boundary and bootstrap CDK in <region>]
First run:   pushing the setup commit deploys the empty starter stack
Protection:  ruleset on main: pull request with a passing `test` check
```

## Step 4: Scaffold the repo locally

1. **Make the CDK app.** `cdk init` needs an empty folder, named after the app:
   - **New repo:** make an empty folder named after the repo and run `npx aws-cdk@latest init app --language typescript` in it. It makes the first git commit.
   - **Existing repo:** clone it. In an empty temporary folder with the repo's name, run the same `cdk init`. Copy everything except its `.git` into the clone. Merge the two `.gitignore` files, keeping every line from both. Keep the existing README for step 8.
2. Write `.nvmrc` containing `24`.
3. **Set the boundary for the whole app.** In `cdk.json`, add to `context`:

   ```json
   "@aws-cdk/core:permissionsBoundary": { "name": "<boundary name>" }
   ```

   If the account uses a custom qualifier, also add `"@aws-cdk/core:bootstrapQualifier": "<qualifier>"`.
4. **Tag everything.** In `bin/<name>.ts`, import `Tags` from `aws-cdk-lib` and add `Tags.of(app).add("project", "<name>");` after the app is created. This lets leftovers be traced back to the repo.
5. Copy these templates:
   - `templates/workflows/ci.yml` and `templates/workflows/deploy.yml` to `.github/workflows/`
   - `templates/github-deploy-role.yaml` to `.github/aws/`
   - `templates/check-role-boundaries.mjs` to `scripts/`
6. **Set up OpenSpec.** Run `openspec init --tools <tools>`. Then add to the `context` in `openspec/config.yaml`:

   > Merging to main deploys to production through `.github/workflows/deploy.yml`. Every change must leave `npm test`, `npx cdk synth` and `node scripts/check-role-boundaries.mjs` passing. Every IAM role must carry the `<boundary name>` permissions boundary. The cdk.json context key sets it app-wide, but roles CDK creates for `AwsCustomResource` miss it (aws/aws-cdk#30179) and need `PermissionsBoundary.of(construct).apply(...)`. CDK keeps S3 buckets and DynamoDB tables when a stack is deleted unless they set a removal policy, so decide for each one whether its data must outlive the stack.
7. Write `factory.config.yaml`:

   ```yaml
   commands:
     test: npm test
     typecheck: npx tsc --noEmit
   ```

8. Write the README. For a new repo, replace the one from `cdk init`. For an existing repo, keep what's there and add to it. It should cover what the repo is for, that merges to `main` deploy to production, and how the deploy role is set up, pointing to `.github/aws/github-deploy-role.yaml`.
9. Run `npm test`, `npx tsc --noEmit`, `npx cdk synth --quiet` and `node scripts/check-role-boundaries.mjs`. All must pass before you go on.
10. Commit: `Set up CDK app, OpenSpec and deploy-on-merge`.

## Step 5: Get the repo's IDs, without pushing

- **New repo:** run `gh repo create <owner>/<name> --<private|public>`.
- **Existing repo:** it's already there.

Don't push yet. Pushing to `main` starts a deploy, and the deploy role doesn't exist yet.

Build the OIDC subject claim the role will trust:

- Get the IDs with `gh api repos/<owner>/<name> -q '.id, .owner.id, .created_at'`.
- Repos created on or after 15 July 2026 use immutable subject claims: `repo:<owner>@<owner-id>/<name>@<repo-id>:ref:refs/heads/main`.
- Older repos use `repo:<owner>/<name>:ref:refs/heads/main`, unless the owner opted in to the immutable form.

## Step 6: Create the AWS side

1. If the plan includes it, create the boundary and bootstrap CDK as agreed in step 2.
2. Deploy the role, with the boundary's ARN:

   ```bash
   aws cloudformation deploy \
     --template-file .github/aws/github-deploy-role.yaml \
     --stack-name github-deploy-<name> \
     --capabilities CAPABILITY_NAMED_IAM \
     --tags project=<name> \
     --parameter-overrides RoleName=github-deploy-<name> SubjectClaim=<claim> \
       CdkQualifier=<qualifier> CreateOidcProvider=<true|false> \
       PermissionsBoundaryArn=arn:aws:iam::<account>:policy/<boundary name> \
     --region <region> --profile <profile>
   ```

3. Read the role ARN from the `DeployRoleArn` output: `aws cloudformation describe-stacks --stack-name github-deploy-<name> --query "Stacks[0].Outputs" --region <region> --profile <profile>`.

## Step 7: Connect GitHub to AWS and push

1. Set the repo variables. They aren't secrets.

   ```bash
   gh variable set AWS_DEPLOY_ROLE_ARN --repo <owner>/<name> --body <role-arn>
   gh variable set AWS_REGION --repo <owner>/<name> --body <region>
   ```

2. Push. For a new repo, add the remote first. Then run `git push -u origin main`.
3. Watch the first deploy: `gh run list --repo <owner>/<name> --workflow deploy.yml --limit 1`, then `gh run watch <run-id> --repo <owner>/<name>`.
   - If it fails at `configure-aws-credentials` with "Not authorized to perform sts:AssumeRoleWithWebIdentity", the subject claim is wrong. Check the claim format from step 5, update the stack, and rerun the workflow with `gh run rerun <run-id> --failed`.
   - If `cdk deploy` fails to assume a `cdk-*` role, check the qualifier and bootstrap Region.
   - If it fails creating a role with an access-denied error, that role is missing the boundary. Find it with `scripts/check-role-boundaries.mjs` and bound it.

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

GitHub's free plan doesn't support rulesets on private repos, so the call fails there with "Upgrade to GitHub Pro or make this repository public". If that happens, the setup isn't finished. Stop and tell the human `main` is unprotected, and give them the options:

- Make the repo public. With their yes, run `gh api -X PATCH repos/<owner>/<name> -f visibility=public`, then add the ruleset.
- Upgrade the plan.

Until it's fixed, consider disabling the deploy workflow with `gh workflow disable deploy.yml --repo <owner>/<name>`.

## Step 9: Report

Tell the human:

- The repo URL.
- The first deploy run's URL and result.
- The role ARN, and the boundary it carries.
- That `main` is protected.

Then tell them the next step: run the factory in the repo, and merge its PR to deploy.
