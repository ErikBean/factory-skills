# factory-skills

Agent skills for a multi-agent software factory. You hand an orchestrator agent a feature request. It spawns one sub agent per stage, and each sub agent has one role and uses one skill.

By default the factory uses spec-driven development with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and red-green TDD. Before the build starts, the orchestrator shows you the flow it will run and waits for your yes. You can change the flow per run, or save it in a config file.

## The factory

```text
you ── request ──► factory-orchestrator ── shows the flow, waits for your yes
                          │
                          ▼
   spec ──► [ red ──► green ] for each task group ──► review ──► verify ──► ship
                         ▲                                          │
                         └────────── confirmed blocking findings ───┘
```

| Stage | Agent | Skill | What it does |
| --- | --- | --- | --- |
| spec | `spec-writer` | [`factory-spec-writer`](skills/factory-spec-writer/SKILL.md) | Writes an OpenSpec change: proposal, spec deltas with testable scenarios, design, tasks |
| red | `test-writer` | [`factory-test-writer`](skills/factory-test-writer/SKILL.md) | Writes one failing test per scenario and proves each fails for the right reason |
| green | `implementer` | [`factory-implementer`](skills/factory-implementer/SKILL.md) | Makes the tests pass without touching them, refactors, ticks the tasks |
| review | `reviewer` | [`factory-reviewer`](skills/factory-reviewer/SKILL.md) | Read-only review against the spec, the tests, the diff and any outside requirements in the config |
| verify | `verifier` | [`factory-verifier`](skills/factory-verifier/SKILL.md) | Tries to refute one review finding; blocking findings get three verifiers and survive on two confirmations |
| ship | `releaser` | [`factory-releaser`](skills/factory-releaser/SKILL.md) | Archives the OpenSpec change, then commits, pushes and opens a PR |

Each stage runs as a sub agent with one role and one skill.

The orchestrator itself is [`factory-orchestrator`](skills/factory-orchestrator/SKILL.md). It doesn't trust handoffs: after red it runs the tests to see them fail, and after green it checks they pass and that the red tests weren't edited. Review findings are claims too, so verifiers check each one before it goes back to green, and the orchestrator counts their verdicts by fixed rules. You see what verification removed, and decide the findings the verifiers split on.

By default you're asked at three points: before the build, after the spec, and before ship. A run ends at an open pull request, and merging is yours. The orchestrator won't start a build while `ship.review_queue` factory pull requests, 3 by default, are waiting for your review.

## Install

The skills follow the [Agent Skills](https://agentskills.io) format and don't depend on one agent runtime. The orchestrator spawns each stage with the runtime's own sub agent tool and tells it which skill to use.

There are two places to install them, and they work together:

- **On your machine, for every project.** Link each folder in `skills/` into the shared `~/.agents/skills/` folder, and from there into your agent's folder, such as `~/.claude/skills/`. Link to a clone you keep on `main`, so edits and `git pull` take effect everywhere at once.

  ```bash
  for s in ~/path/to/factory-skills/skills/*/; do
    n=$(basename "$s")
    ln -s "${s%/}" ~/.agents/skills/"$n"
    ln -s ../../.agents/skills/"$n" ~/.claude/skills/"$n"
  done
  ```

- **In each project, pinned.** `factory-repo-setup` copies the stage skills into the project's `.agents/skills/`, links them from `.claude/skills/`, and records the factory-skills commit in `.agents/factory-skills.json`. CI, teammates and cloud sessions then run the version the project was built with. To move a project to a newer version, run `scripts/sync-factory-skills.sh <factory-skills checkout>` in it and commit the result. So the pin doesn't go stale unnoticed, `scripts/check-factory-skills.mjs` says when a pinned skill has changed on factory-skills `main`. The project's CI runs it on every pull request as a warning that doesn't fail the build, and the orchestrator runs it before each build and shows the result in its plan.

In Claude Code, skills in `~/.claude/skills/` take precedence over a project's skills with the same name. With both installed, your machine runs your linked copy and everyone else runs the pinned one.

### Prerequisites in the project being built

- The OpenSpec CLI, set up with `openspec init`. The orchestrator offers to set it up if it's missing.
- A test command the agents can run.
- Git, plus `gh` if you ship as a PR.

## Start a new project

[`factory-repo-setup`](skills/factory-repo-setup/SKILL.md) is the skill to invoke first. Ask for it by name to set up a new repo, or one with little in it yet:

- A TypeScript AWS CDK app, OpenSpec and a `factory.config.yaml`. The app deploys as three stages: `dev` per branch in an agent account, `preview` per pull request in a preview account, and `prod` in production. `dev` and `preview` delete their data with their stacks.
- CI that typechecks, tests and runs `cdk synth` on every pull request, and fails if any IAM role the app creates has no permissions boundary.
- A GitHub Actions workflow that runs `cdk deploy` to production on every merge to `main`.
- On every pull request, a preview deployed to the preview account with its URLs posted on the pull request, and destroyed when it closes along with the branch's `dev` stacks. Also a diff against the last production deploy, made without AWS credentials.
- Rulesets on `main`, so changes only land through a pull request that passed CI and that you approved as its code owner. Agents can't approve their own pull requests, so only you can merge. A Claude Code hook also refuses agents' merge, approve and push-to-`main` commands, so an attempt fails fast with an explanation.
- Three AWS roles that GitHub Actions assumes through OIDC, so no AWS keys are stored in GitHub. Only the repo's `main` branch can assume the production deploy role, and only its own pull requests the preview role; each can only assume CDK's bootstrap roles. A cleanup role in the agent account can only delete the app's `dev` stacks, and only the cleanup workflow on `main` can assume it.
- Each AWS account's permissions boundary on every role: the deploy roles, and every role the app creates. The skill won't deploy to an account whose CDK bootstrap has no boundary.

If the target AWS account is an organization's management account, where organization policies don't apply, it stops and asks you to confirm that's on purpose, that the agent's builder role is denied Identity Center, budget and trail changes, and that the agent user is separate from yours. It shows you the plan and waits for your yes before it creates anything on GitHub or AWS. By default it hands you the admin commands to run yourself, on AWS with your admin profile and on GitHub with your own login: creating the repo, adding it to the agents' GitHub App installation, setting its variables and adding its ruleset. So agents never hold admin credentials, and push and open pull requests only with their own narrower GitHub access.

After that, use the factory in the new repo. The factory deploys and smoke-tests the branch's `dev` stage and opens a pull request. CI checks the pull request and deploys its preview, merging it deploys to production, and closing it destroys the preview and `dev`.

## Use

In the project you want to build in, ask for something like:

```text
Use the factory to add dark mode with a toggle in the header.
```

The orchestrator restates the request, shows the flow and asks before it starts:

```text
Feature:     Add a dark mode toggle to the header
Change:      openspec change `add-dark-mode` on branch factory/add-dark-mode
Flow:        spec → red → green → review → ship (PR)
TDD:         red-green, one cycle per task group; tests run with `npm test`
Checkpoints: before build (now), after spec, before ship
Config:      defaults (no factory.config.yaml)
```

## Configure

Put a `factory.config.yaml` at the root of the project being built. Every key is optional:

```yaml
workflow:
  spec: openspec        # openspec | none
  tests: red-green      # red-green | tests-with-code | none
tdd:
  batch: group          # group | task | change
confirm:
  before_build: true    # set false to start without asking; the flow is still printed
  after_spec: true
  before_ship: true
ship:
  mode: pr              # pr | commit | none
```

[`references/config.md`](skills/factory-orchestrator/references/config.md) documents every key. Stages hand off to each other in the format in [`references/handoff.md`](skills/factory-orchestrator/references/handoff.md).

## Observe the factory

[`factory-observer`](skills/factory-observer/SKILL.md) takes notes on how factory runs and repo setups go: what worked, what failed, and where an agent or the human hit friction. It writes them as findings and questions in an OKF (Open Knowledge Format) bundle outside the project repo. It never changes the run or the skills. A change it would make to a skill becomes a question for you to decide.

The orchestrator and `factory-repo-setup` spawn it after each stage or step. At the end, it asks you a few retro questions and writes up the run.

It's on while `~/.config/factory/observer.yaml` exists, and you can also ask for it on a single run. Start from [the template](skills/factory-observer/templates/observer.yaml):

```yaml
remote: git@github.com:<you>/research.git  # empty: local bundle in ~/.local/share/factory-observer/
bundle: knowledge
topic: projects/factory-skills
```

With no `remote`, notes go to a local git repo on the machine that ran the factory. With a `remote`, the observer commits to that repo's default branch and pushes. If the repo has an `AGENTS.md`, the observer follows its rules for the bundle.

## Develop

`scripts/check.sh` lints the `factory-repo-setup` templates with shellcheck, `node --check`, cfn-lint and actionlint, and runs the tests in `tests/`. CI runs it on every pull request, and `main` only takes changes through a pull request that passed it. It needs `node` on the PATH, plus the linters pinned in `tests/requirements.txt`:

```bash
python3 -m venv .venv && .venv/bin/pip install -r tests/requirements.txt
PATH="$PWD/.venv/bin:$PATH" scripts/check.sh
```

## Status

This is an early version and hasn't run end to end yet. Expect the skills to change as real runs show what's missing.
