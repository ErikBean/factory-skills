# factory-skills

Agent skills for a multi-agent software factory. You hand an orchestrator agent a feature request. It spawns one sub agent per stage, and each sub agent has one role and uses one skill.

By default the factory uses spec-driven development with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and red-green TDD. Before the build starts, the orchestrator shows you the flow it will run and waits for your yes. You can change the flow per run, or save it in a config file.

## The factory

```text
you ── request ──► factory-orchestrator ── shows the flow, waits for your yes
                          │
                          ▼
   spec ──► [ red ──► green ] for each task group ──► review ──► ship
                         ▲                              │
                         └──── blocking findings ───────┘
```

| Stage | Agent | Skill | What it does |
| --- | --- | --- | --- |
| spec | `spec-writer` | [`factory-spec-writer`](skills/factory-spec-writer/SKILL.md) | Writes an OpenSpec change: proposal, spec deltas with testable scenarios, design, tasks |
| red | `test-writer` | [`factory-test-writer`](skills/factory-test-writer/SKILL.md) | Writes one failing test per scenario and proves each fails for the right reason |
| green | `implementer` | [`factory-implementer`](skills/factory-implementer/SKILL.md) | Makes the tests pass without touching them, refactors, ticks the tasks |
| review | `reviewer` | [`factory-reviewer`](skills/factory-reviewer/SKILL.md) | Read-only review against the spec, the tests and the diff |
| ship | `releaser` | [`factory-releaser`](skills/factory-releaser/SKILL.md) | Archives the OpenSpec change, then commits, pushes and opens a PR |

Each stage runs as a sub agent with one role and one skill.

The orchestrator itself is [`factory-orchestrator`](skills/factory-orchestrator/SKILL.md). It doesn't trust handoffs: after red it runs the tests to see them fail, and after green it checks they pass and that the red tests weren't edited.

By default you're asked at three points: before the build, after the spec, and before ship.

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

- **In each project, pinned.** `factory-repo-setup` copies the stage skills into the project's `.agents/skills/`, links them from `.claude/skills/`, and records the factory-skills commit in `.agents/factory-skills.json`. CI, teammates and cloud sessions then run the version the project was built with. To move a project to a newer version, run `scripts/sync-factory-skills.sh <factory-skills checkout>` in it and commit the result.

In Claude Code, skills in `~/.claude/skills/` take precedence over a project's skills with the same name. With both installed, your machine runs your linked copy and everyone else runs the pinned one.

### Prerequisites in the project being built

- The OpenSpec CLI, set up with `openspec init`. The orchestrator offers to set it up if it's missing.
- A test command the agents can run.
- Git, plus `gh` if you ship as a PR.

## Start a new project

[`factory-repo-setup`](skills/factory-repo-setup/SKILL.md) is the skill to invoke first. Ask for it by name to set up a new repo, or one with little in it yet:

- A TypeScript AWS CDK app, OpenSpec and a `factory.config.yaml`.
- CI that typechecks, tests and runs `cdk synth` on every pull request, and fails if any IAM role the app creates has no permissions boundary.
- A GitHub Actions workflow that runs `cdk deploy` to production on every merge to `main`.
- A ruleset on `main`, so changes only land through a pull request that passed CI.
- An AWS deploy role that GitHub Actions assumes through OIDC, so no AWS keys are stored in GitHub. Only the repo's `main` branch can assume it, and it can only assume CDK's bootstrap roles.
- The AWS account's permissions boundary on every role: the deploy role, and every role the app creates. The skill won't deploy to an account whose CDK bootstrap has no boundary.

It shows you the plan and waits for your yes before it creates anything on GitHub or AWS.

After that, use the factory in the new repo. The factory opens a pull request, CI checks it, and merging it deploys to production.

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

## Develop

`scripts/check.sh` lints the `factory-repo-setup` templates with shellcheck, `node --check`, cfn-lint and actionlint, and runs the tests in `tests/`. CI runs it on every pull request, and `main` only takes changes through a pull request that passed it. It needs `node` on the PATH, plus the linters pinned in `tests/requirements.txt`:

```bash
python3 -m venv .venv && .venv/bin/pip install -r tests/requirements.txt
PATH="$PWD/.venv/bin:$PATH" scripts/check.sh
```

## Status

This is an early version and hasn't run end to end yet. Expect the skills to change as real runs show what's missing.
