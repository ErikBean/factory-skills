---
name: factory-repo-setup
description: Sets up a GitHub repo for the software factory, with a TypeScript AWS CDK app that deploys as dev, preview and prod stages, OpenSpec, a factory config, CI on pull requests, a preview deployed for each pull request, a production diff on each pull request, and a GitHub Actions workflow that runs cdk deploy to production on every merge to main. Creates the AWS roles those workflows deploy with, using GitHub OIDC rather than stored keys, under each account's permissions boundary. Works on a new repo or one with little in it yet. Use only when the human asks to set up a repo for the factory or for deploy-on-merge.
---

# Factory repo setup

You set up a repo so the factory can build in it and every merge to `main` deploys to production. Run this once per repo, before the first factory run.

The app runs in three AWS accounts, as three stages of one CDK app:

| Stage | Account | Deployed by | Stack names |
| --- | --- | --- | --- |
| `dev` | The agent account | The factory's implementer, from the developer's machine, as the agent user | Per branch, such as `<name>-dev-factory-add-login` |
| `preview` | The preview account | CI only, for each pull request from this repo | Per pull request, such as `<name>-preview-pr12` |
| `prod` | The production account | CI only, on every merge to `main` | `<name>` |

Afterwards the flow is: the factory deploys and smoke-tests the branch's `dev` stage, then opens a PR and destroys `dev`. CI checks the PR, deploys its preview and shows what it would change in production. The human merges it, GitHub Actions runs `cdk deploy` to production, and the preview is destroyed.

This skill changes GitHub and AWS. Get the human's yes on the plan before anything outside the local machine changes.

## What it sets up

| Where | What |
| --- | --- |
| Repo | A TypeScript CDK app from `cdk init`, with Jest tests, every resource tagged with the project name and stage, and every IAM role carrying the account's permissions boundary. It takes a stage, and `dev` and `preview` delete their data with their stacks |
| Repo | `openspec/` from `openspec init`, with project context covering deploys, the boundary and retained resources |
| Repo | `factory.config.yaml` with the repo's test and typecheck commands, and the commands and profile for the `dev` stage |
| Repo | `scripts/smoke.mjs`, which requests the URLs a deploy outputs, and `scripts/stack-urls.mjs`, which finds them |
| Repo | The factory's stage skills in `.agents/skills/`, linked from `.claude/skills/`, pinned to a factory-skills commit in `.agents/factory-skills.json` |
| Repo | `.github/workflows/ci.yml`: typecheck, tests, `cdk synth` and a check that every synthesized IAM role has a boundary, on every pull request |
| Repo | `.github/workflows/deploy.yml`: the CI checks, then `cdk deploy --all` of the `prod` stage on every push to `main`, saving the templates it deployed |
| Repo | `.github/workflows/preview.yml`: deploys each pull request's `preview` stage and posts its URLs, and destroys it when the pull request closes |
| Repo | `.github/workflows/prod-diff.yml`: compares each pull request's `prod` stage with the last deployed templates, with no AWS credentials, using `scripts/diff-prod.mjs` |
| Repo | `.github/aws/github-deploy-role.yaml`: the CloudFormation template for both deploy roles |
| AWS, production account | The GitHub OIDC identity provider, unless the account already has one |
| AWS, production account | A deploy role that only this repo's `main` branch can assume, that can only assume the CDK bootstrap roles, and that carries the account's boundary |
| AWS, preview account | The OIDC provider, if missing, and a preview role that only this repo's pull request workflows can assume, with the same limits |
| GitHub | Repo variables `AWS_DEPLOY_ROLE_ARN`, `AWS_PREVIEW_ROLE_ARN` and `AWS_REGION` |
| GitHub | A ruleset on `main`: changes only through a pull request whose `test` check passed |

The templates are in [templates/](templates/).

## Step 1: Gather inputs and check tools

Ask for anything the human hasn't given you:

- The repo owner and name. Whether the repo exists already, and if not, whether it should be private or public.
- The Region, and the IDs of the three accounts: production, preview and the agent account. If the human has no separate preview or agent account, stop and ask how they want to run without one, since this setup assumes all three.
- The AWS CLI profile the factory deploys `dev` with: the agent user's builder profile in the agent account, such as `agent-builder`. Never an admin profile.
- Who will make the AWS changes in step 6. They need rights to create IAM roles and CloudFormation stacks in the production and preview accounts. If you're an agent, you should be signed in as an identity that can't do that, and the human shouldn't stay signed in as an admin while agents run. So by default you prepare the step 6 commands and the human runs them in their own terminal, with their own admin profile. Only run them yourself if the human says the profile you have is meant for this.
- The AWS CLI profiles to use for the read-only checks in steps 1 and 2, one per account. A read-only profile, such as the agent user's read-only profile in the preview account, is enough for most of them.
- Which agent tools to set OpenSpec up for, as `openspec init --tools` takes them.

Check the tools work: `gh auth status`, `aws sts get-caller-identity --profile <profile>` with each read-only profile and with the `dev` profile, `node --version` (OpenSpec needs 22.12 or later), `npx --version` and `openspec --version`. Each caller identity's account must match the account the human named for it, and the `dev` profile must be in the agent account. If one doesn't, stop.

If the repo exists, read it. This skill adds a CDK app at the repo root, so it fits a repo that holds little more than a README and a `.gitignore`. If the repo already has an app, stop and ask the human how the CDK app should fit in.

## Step 2: Check the AWS accounts

All of these are read-only. Run the boundary and management-account checks for each of the three accounts, and the OIDC provider check for the production and preview accounts.

**The permissions boundary.** Every role this setup creates, and every role the app's deploys create, must carry a permissions boundary that stops deploys from creating roles more powerful than intended. Read the bootstrap stack:

```bash
aws cloudformation describe-stacks --stack-name CDKToolkit --region <region> --profile <profile> \
  --query "Stacks[0].Parameters"
```

- **Bootstrapped with `InputPermissionsBoundary` set and `ApplyPermissionsBoundaryToAllRoles` true:** that policy is the boundary. Use its name everywhere below. Note the `Qualifier` too.
- **Bootstrapped with no boundary, or with the boundary on the execution role only:** every deploy from `main` can do anything the bootstrap roles can, which by default is `AdministratorAccess`. Stop and tell the human. The account needs a boundary policy and a re-bootstrap with `--custom-permissions-boundary <name> --apply-permissions-boundary-to-all-roles` before this repo deploys to it. Narrowing `--cloudformation-execution-policies` instead isn't enough, because a deploy can still create a role with no boundary.
- **Not bootstrapped:** ask whether code elsewhere owns this account's setup, such as an account bootstrap repo. If it does, the bootstrap belongs there, so stop. If not, add to the plan: create a boundary policy, starting from CDK's example (`cdk bootstrap --show-template` contains it), then bootstrap with `--custom-permissions-boundary <name> --apply-permissions-boundary-to-all-roles`. Never bootstrap with CDK's defaults.

**Not the management account.** Service control policies, resource control policies and budget actions don't restrict an organization's management account, so a repo that deploys there runs without those guardrails. Check:

```bash
aws organizations describe-organization --profile <profile> --query "Organization.MasterAccountId"
```

If it returns the target account ID, stop and tell the human to deploy to a member account instead. If the account isn't in an organization, the call fails with `AWSOrganizationsNotInUseException`; tell the human the account has no organization guardrails and ask whether to go on.

**A resource control policy on the account.** A member account can't read its organization's policies, so ask the human whether the account has an identity-perimeter RCP, such as AWS's `identity_perimeter_rcp.json` from the data-perimeter examples. If it limits `sts:AssumeRoleWithWebIdentity` to trusted OIDC providers or tenants, GitHub Actions can't assume the deploy or preview role until the RCP trusts this repo's GitHub owner. In that case, add to the step 6 commands an update to the RCP, in the management account, with a statement like this:

```json
{
  "Sid": "EnforceTrustedGitHubOwner",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Resource": "*",
  "Condition": {
    "StringNotEqualsIfExists": {
      "token.actions.githubusercontent.com:repository_owner_id": "<owner-id>"
    },
    "Null": { "token.actions.githubusercontent.com:repository_owner_id": "false" }
  }
}
```

Get `<owner-id>` with `gh api users/<owner> -q .id`. Use the immutable `repository_owner_id`, which AWS recommends for resource control policies, rather than a name in `sub`, because names can be freed and claimed by someone else. Two things are untested: that an RCP sees this key, and that it holds the user's ID for a personal account. So the first preview or deploy in step 7 is the test. If it fails at `configure-aws-credentials` with an access-denied error after the trust policy checks out, this statement is the likely cause.

**The OIDC provider.** `aws iam list-open-id-connect-providers --profile <profile>`, in the production and preview accounts. Where one ends in `token.actions.githubusercontent.com`, set `CreateOidcProvider` to `false` for that account's role, since an account can only have one. If the read-only profile can't list providers, ask the human to run this check.

## Step 3: Confirm the plan

Show the human the plan and wait for a yes:

```text
Repo:        github.com/<owner>/<name> (new, private | existing)
App:         TypeScript CDK app, Node 24, tests with Jest, tagged project=<name>
Stages:      dev per branch in <agent account>, deployed by the factory as <dev profile>
             preview per pull request in <preview account>, deployed by CI
             prod in <production account>, in <region>
Deploys:     every push to main runs `cdk deploy --all` of prod
Skills:      factory stage skills copied in, pinned to factory-skills <short commit>
Boundary:    <boundary name> on every role, checked in CI
Auth:        GitHub OIDC; role github-deploy-<name> trusts <subject claim>;
             role github-preview-<name> trusts this repo's pull requests
PR checks:   test, a preview with its URLs, and the production diff
AWS changes: create stack github-deploy-<name> in production and
             github-preview-<name> in preview (role[, OIDC provider]),
             run by <you | the human, in their own terminal>
             [create the boundary and bootstrap CDK in <region>]
First run:   pushing the setup commit deploys the empty starter stack to production
Protection:  ruleset on main: pull request with a passing `test` check
```

## Step 4: Scaffold the repo locally

1. **Make the CDK app.** `cdk init` needs an empty folder, named after the app:
   - **New repo:** make an empty folder named after the repo and run `npx aws-cdk@latest init app --language typescript` in it. It makes the first git commit.
   - **Existing repo:** clone it. In an empty temporary folder with the repo's name, run the same `cdk init`. Copy everything except its `.git` into the clone. Merge the two `.gitignore` files, keeping every line from both. Keep the existing README for step 9.
2. Write `.nvmrc` containing `24`.
3. **Set the boundary for the whole app.** In `cdk.json`, add to `context`:

   ```json
   "@aws-cdk/core:permissionsBoundary": { "name": "<boundary name>" }
   ```

   If the account uses a custom qualifier, also add `"@aws-cdk/core:bootstrapQualifier": "<qualifier>"`.
4. Copy these templates:
   - `templates/workflows/*.yml` to `.github/workflows/`
   - `templates/github-deploy-role.yaml` to `.github/aws/`
   - `templates/stage.ts` to `lib/`
   - `templates/*.mjs` and `templates/sync-factory-skills.sh` to `scripts/`, keeping the sync script executable
5. **Add the stages and tags.** In `bin/<name>.ts`, after the app is created:

   ```ts
   import { App, RemovalPolicies, Tags } from "aws-cdk-lib";
   import { stageFromContext } from "../lib/stage";

   const stage = stageFromContext(app);
   new <Name>Stack(app, "<Name>Stack", { stackName: `<name>${stage.suffix}`, stage });
   Tags.of(app).add("project", "<name>");
   Tags.of(app).add("stage", stage.name);
   if (stage.ephemeral) RemovalPolicies.of(app).destroy();
   ```

   Add `stage: Stage` to the stack's props, so its constructs can read `stage.ephemeral`. The tags let leftovers be traced back to the repo and stage. Every command that synthesizes now needs `-c stage=...`. Then:
   - Add `@aws-cdk/cloudformation-diff` to the dev dependencies, for `scripts/diff-prod.mjs`.
   - Add these to `package.json` scripts. npm runs them with `sh`, so the branch is read when they run:

     ```json
     "dev:deploy": "cdk deploy --all --require-approval never -c stage=dev -c branch=$(git branch --show-current) --outputs-file cdk-outputs.dev.json",
     "dev:smoke": "node scripts/smoke.mjs cdk-outputs.dev.json",
     "dev:destroy": "cdk destroy --all --force -c stage=dev -c branch=$(git branch --show-current)"
     ```

   - Add `cdk-outputs.*.json` to `.gitignore`.
6. **Copy in the factory's skills.** This way the repo's agents, CI, teammates and cloud sessions all run the same version of the factory, whatever is installed on their machine. Find the factory-skills checkout this skill was loaded from: resolve symlinks on this skill's folder, and the checkout is two levels up. If that folder isn't a git checkout, clone `https://github.com/ErikBean/factory-skills` into a temporary folder and use that. Then run `scripts/sync-factory-skills.sh <checkout>`. It refuses a checkout with uncommitted changes under `skills/`. If it does, tell the human and ask whether to commit them first or pin the last commit from a fresh clone.
7. **Set up OpenSpec.** Run `openspec init --tools <tools>`. Then add to the `context` in `openspec/config.yaml`:

   > Merging to main deploys to production through `.github/workflows/deploy.yml`. The CDK app deploys as three stages, chosen with `-c stage=dev|preview|prod` (see `lib/stage.ts`): `dev` per branch in the agent account, `preview` per pull request in the preview account, and `prod`. Nothing in `prod` may depend on a resource in another stage. Every change must leave `npm test`, `npx cdk synth -c stage=prod` and `node scripts/check-role-boundaries.mjs` passing. Every IAM role must carry the `<boundary name>` permissions boundary. The cdk.json context key sets it app-wide, but roles CDK creates for `AwsCustomResource` miss it (aws/aws-cdk#30179) and need `PermissionsBoundary.of(construct).apply(...)`. CDK keeps S3 buckets and DynamoDB tables when a stack is deleted unless they set a removal policy. In `dev` and `preview`, `RemovalPolicies.of(app).destroy()` deletes them with the stack, and every bucket sets `removalPolicy: stage.ephemeral ? RemovalPolicy.DESTROY : RemovalPolicy.RETAIN` and `autoDeleteObjects: stage.ephemeral`, since deleting a bucket that still has objects fails. For `prod`, decide for each one whether its data must outlive the stack. Each stack that serves something outputs its URL with a `CfnOutput` whose id starts with `Url`, so the smoke test and the preview comment find it. The account's organization policies may deny some Regions, services or resource types outright, such as EC2 instances, NAT gateways or load balancers, so check what the account allows before designing around a service.
8. Write `factory.config.yaml`:

   ```yaml
   commands:
     test: npm test
     typecheck: npx tsc --noEmit
     deploy_dev: npm run dev:deploy
     smoke_dev: npm run dev:smoke
     destroy_dev: npm run dev:destroy

   dev:
     profile: <dev profile>
   ```

9. Write the README. For a new repo, replace the one from `cdk init`. For an existing repo, keep what's there and add to it. It should cover what the repo is for, the three stages and where each runs, that merges to `main` deploy to production, and how the deploy and preview roles are set up, pointing to `.github/aws/github-deploy-role.yaml`. Also say that the factory's skills are pinned in `.agents/skills/`, and that `scripts/sync-factory-skills.sh <factory-skills checkout>` updates them.
10. Run `npm test`, `npx tsc --noEmit`, `npx cdk synth --quiet -c stage=prod` and `node scripts/check-role-boundaries.mjs`. All must pass before you go on. Also check that `npx cdk synth --quiet -c stage=dev -c branch=main` and `-c stage=preview -c pr=1` synthesize.
11. Commit: `Set up CDK app, OpenSpec and deploy-on-merge`.

## Step 5: Get the repo's IDs, without pushing

- **New repo:** run `gh repo create <owner>/<name> --<private|public>`.
- **Existing repo:** it's already there.

Don't push yet. Pushing to `main` starts a deploy, and the deploy role doesn't exist yet.

Get the IDs with `gh api repos/<owner>/<name> -q '.id, .owner.id, .created_at'`. Both roles trust the immutable repository and owner IDs.

The preview role needs no subject claim: it trusts any subject ending in `:pull_request` from this repository. Build the one the deploy role trusts:

- Repos created on or after 15 July 2026 use immutable subject claims: `repo:<owner>@<owner-id>/<name>@<repo-id>:ref:refs/heads/main`.
- Older repos use `repo:<owner>/<name>:ref:refs/heads/main`, unless the owner opted in to the immutable form.

## Step 6: Create the AWS side

Unless the human said in step 1 that your profile is meant for these changes, don't run this step yourself. Give the human the exact commands below, filled in, to run in their own terminal with their admin profile. Wait for them to confirm, and for the role ARN, before step 7. Remind them to sign out of the admin session afterwards with `aws sso logout`.

1. If the plan includes it, create the boundary and bootstrap CDK as agreed in step 2.
2. Deploy the production deploy role, with the production account's admin profile and boundary:

   ```bash
   aws cloudformation deploy \
     --template-file .github/aws/github-deploy-role.yaml \
     --stack-name github-deploy-<name> \
     --capabilities CAPABILITY_NAMED_IAM \
     --tags project=<name> \
     --parameter-overrides RoleName=github-deploy-<name> Trust=main SubjectClaim=<claim> \
       RepositoryId=<repo-id> RepositoryOwnerId=<owner-id> \
       CdkQualifier=<qualifier> CreateOidcProvider=<true|false> \
       PermissionsBoundaryArn=arn:aws:iam::<production account>:policy/<boundary name> \
     --region <region> --profile <production admin profile>
   ```

3. Deploy the preview role the same way, with the preview account's admin profile and boundary:

   ```bash
   aws cloudformation deploy \
     --template-file .github/aws/github-deploy-role.yaml \
     --stack-name github-preview-<name> \
     --capabilities CAPABILITY_NAMED_IAM \
     --tags project=<name> \
     --parameter-overrides RoleName=github-preview-<name> Trust=pull_request \
       RepositoryId=<repo-id> RepositoryOwnerId=<owner-id> \
       CdkQualifier=<qualifier> CreateOidcProvider=<true|false> \
       PermissionsBoundaryArn=arn:aws:iam::<preview account>:policy/<boundary name> \
     --region <region> --profile <preview admin profile>
   ```

4. Read each role's ARN from its stack's `DeployRoleArn` output: `aws cloudformation describe-stacks --stack-name <stack> --query "Stacks[0].Outputs" --region <region> --profile <profile>`.

## Step 7: Connect GitHub to AWS and push

1. Set the repo variables. They aren't secrets.

   ```bash
   gh variable set AWS_DEPLOY_ROLE_ARN --repo <owner>/<name> --body <deploy role arn>
   gh variable set AWS_PREVIEW_ROLE_ARN --repo <owner>/<name> --body <preview role arn>
   gh variable set AWS_REGION --repo <owner>/<name> --body <region>
   ```

2. Push. For a new repo, add the remote first. Then run `git push -u origin main`.
3. Watch the first deploy: `gh run list --repo <owner>/<name> --workflow deploy.yml --limit 1`, then `gh run watch <run-id> --repo <owner>/<name>`.
   - If it fails at `configure-aws-credentials` with "Not authorized to perform sts:AssumeRoleWithWebIdentity", the subject claim or an ID is wrong. Check the claim format from step 5, update the stack, and rerun the workflow with `gh run rerun <run-id> --failed`. If the claim is right and the account has a resource control policy, check its GitHub owner statement from step 2.
   - If `cdk deploy` fails to assume a `cdk-*` role, check the qualifier and bootstrap Region.
   - If it fails creating a role with an access-denied error, that role is missing the boundary. Find it with `scripts/check-role-boundaries.mjs` and bound it.
   - If an error says the action is denied by an explicit deny in a service control policy, the organization doesn't allow that Region, service or resource in this account. Change the app to fit, or ask the human whether the policy should change. Don't work around it. A budget action can also apply such a deny when the account goes over its monthly budget.

4. **Check the preview.** Open a small pull request, such as a README fix, from a branch in this repo. Its `Preview` run must deploy and comment on the pull request, its `Production diff` run must show no changes, and closing it must destroy the preview. This is the first test of the preview role's trust, and of the RCP's GitHub statement if the account has one. If the preview fails at `configure-aws-credentials`, check the IDs and the RCP as above.

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
- The two role ARNs, and the boundary each carries.
- The test pull request's preview result.
- The factory-skills commit the repo's skills are pinned to.
- That `main` is protected.

Then tell them the next step: run the factory in the repo, and merge its PR to deploy. The factory deploys `dev` as `<dev profile>`, so they need to be signed in with it, and not with an admin profile, while it runs.
