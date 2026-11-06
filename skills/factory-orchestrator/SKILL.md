---
name: factory-orchestrator
description: Runs a multi-agent software factory that takes a feature request through spec, failing tests, implementation, review and ship, spawning one sub agent per stage. Defaults to spec-driven development with OpenSpec and red-green TDD, and confirms the flow with the human before the build starts. Use when asked to build or ship a feature "with the factory", to run the factory, or to resume a factory run.
---

# Factory orchestrator

You run the factory. You are the only one who talks to the human. You don't write specs, tests or code yourself: you spawn one sub agent per stage, check its work, and decide what runs next.

Run this skill in the main conversation, not in a sub agent. Sub agents can't spawn sub agents.

## The stages

| Stage | Agent | Skill | Produces | Gate you check before moving on |
| --- | --- | --- | --- | --- |
| spec | `spec-writer` | `factory-spec-writer` | An OpenSpec change: proposal, spec deltas, design, tasks | `openspec validate <id> --strict` passes, and the human approves if `confirm.after_spec` |
| red | `test-writer` | `factory-test-writer` | Failing tests, one per scenario in the batch | You run the tests: the new ones fail for the stated reason, the old ones still pass |
| green | `implementer` | `factory-implementer` | Code that passes the tests, then a refactor | You run the tests: all pass, and the red tests are unchanged |
| review | `reviewer` | `factory-reviewer` | Findings against the spec and the diff | No blocking findings, or loop back to green |
| ship | `releaser` | `factory-releaser` | Tasks ticked, change archived, commit or PR | The human approves if `confirm.before_ship` |

## Step 1: Resolve the flow

1. Read `factory.config.yaml` at the repo root if it exists, and merge it over the defaults in [references/config.md](references/config.md). With no file, use the defaults: OpenSpec, red-green TDD batched per task group, human checkpoints before the build, after the spec and before ship, ship as a PR.
2. Check prerequisites for that flow:
   - `workflow.spec: openspec`: `openspec --version` works and the repo has an `openspec/` folder. If either is missing, tell the human and offer to run `openspec init --tools <tool>`. Don't install or initialize anything without their yes.
   - `commands.test`: if empty, detect it from the project (`package.json` scripts, `pyproject.toml`, `go.mod`, `Cargo.toml`, a `Makefile`). If you can't tell, ask.
   - Git: a clean working tree. Plan to work on a branch named `<branch_prefix><change-id>`.
3. If the request is ambiguous in ways that change what gets built, list your questions now. Spec time is too late to discover the human meant something else.

## Step 2: Confirm the flow with the human

If `confirm.before_build` is true, which is the default, show the plan and wait for an answer before spawning anything:

```text
Feature:     <one-line restatement of the request>
Change:      openspec change `add-<name>` on branch factory/add-<name>
Flow:        spec → red → green → review → ship (PR)
TDD:         red-green, one cycle per task group; tests run with `npm test`
Checkpoints: before build (now), after spec, before ship
Config:      defaults (no factory.config.yaml)
```

Then ask whether to run it as shown, change something, or change it and save the result as `factory.config.yaml`. Use the runtime's question tool if it has one. If they change anything, show the updated plan and ask again.

If `confirm.before_build` is false, print the plan and continue without waiting. If the config can't be read, treat `confirm.before_build` as true.

## Step 3: Run the stages

Spawn each stage's agent:

- **Claude Code:** the Agent tool with `subagent_type` set to the stage agent. It's `factory-skills:<agent>` when this repo is installed as a plugin, and `<agent>` when the agent files were copied into `.claude/agents/`.
- **Other runtimes:** a general sub agent whose prompt starts with "Use the `<stage skill>` skill."

Sub agents start with none of your context, so each prompt must carry everything the stage needs. That includes the stage name, the change id, the feature request as confirmed, the resolved config, the test command, the batch to work on, summaries of earlier handoffs, and any findings to fix. Paste in the handoff format from [references/handoff.md](references/handoff.md), which every stage ends its run with.

Run the stages in this order, one agent at a time:

1. **spec.** Skip it if `workflow.spec` is `none`. In that case, write the acceptance criteria in the chat yourself and get the human's approval. They stand in for scenarios in later stages.
   - Pass the spec writer's questions to the human, then send the answers back to it.
   - If `confirm.after_spec`, show the human the change's paths, its requirements and scenarios, and its task groups, and wait for approval.
2. **red, then green, for each batch.** `tdd.batch` sets the batch size: `group` (each numbered group in `tasks.md`), `task`, or `change`. If `workflow.tests` isn't `red-green`, skip red and tell the implementer to write tests along with the code.
3. **review.** On blocking findings, spawn the implementer with the findings, then review again. After `review.max_rounds` rounds, stop and ask the human.
4. **ship.** If `confirm.before_ship`, show the human what will be committed, archived and pushed, and wait for a yes. Tell the releaser in its prompt that the human approved.

## Step 4: Check every handoff yourself

Handoffs are claims. Check them before the next stage starts:

- **spec:** run `openspec validate <id> --strict`.
- **red:** run the test command. Every new test must fail, and its failure output must show missing behavior, not a broken test such as a syntax error or a bad import of a test helper. Tests that existed before must still pass. If it holds, commit: `test(<id>): red for <batch>`.
- **green:** run the test command, which must pass in full. Run `git diff HEAD --stat -- <red test files>`, which must be empty. If the implementer edited a red test, reject the handoff and send it back. If the implementer says a test is wrong, take it to the human. If it holds, commit: `feat(<id>): green for <batch>`.
- **review:** read the findings. You decide whether a should-fix finding goes back to green.
- Any `blocked` or `needs-human` handoff: take it to the human with the options the stage gave.

Never fix a stage's output yourself. Send it back to the stage that owns it.

## Step 5: Report

End with the change id, the stages that ran and any that were skipped, the number of tests added, the number of review rounds, and the commit or PR link.

## Resuming a run

Run `openspec list --json` and `openspec instructions apply --change <id> --json`. Ticked tasks are batches that went green, and the git log shows the red and green commits. Confirm the flow with the human again, then continue from the first unfinished stage.

## Rules

- Only you talk to the human. Stage agents raise questions in their handoffs.
- One stage agent at a time. Red and green for a batch never overlap.
- Don't push, open a PR or archive the change until the human has approved, when `confirm.before_ship` is on.
