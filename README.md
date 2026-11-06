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

The orchestrator itself is [`factory-orchestrator`](skills/factory-orchestrator/SKILL.md). It doesn't trust handoffs: after red it runs the tests to see them fail, and after green it checks they pass and that the red tests weren't edited.

By default you're asked at three points: before the build, after the spec, and before ship.

## Install

### As a Claude Code plugin

```text
/plugin marketplace add ErikBean/factory-skills
/plugin install factory-skills@factory-skills
```

This installs the six skills and the five stage agents. Each agent preloads its stage's skill.

### By copying

Copy `skills/*` into your project's `.claude/skills/` and `agents/*` into `.claude/agents/`. The skills follow the [Agent Skills](https://agentskills.io) format, so you can also use them in other runtimes that support it. There, the orchestrator spawns a general sub agent and tells it which skill to use.

### Prerequisites in the project being built

- The OpenSpec CLI, set up with `openspec init`. The orchestrator offers to set it up if it's missing.
- A test command the agents can run.
- Git, plus `gh` if you ship as a PR.

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

## Status

This is an early version and hasn't run end to end yet. Expect the skills to change as real runs show what's missing.
