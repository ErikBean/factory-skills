# Writing to the bundle

The observer writes OKF v0.2 concepts: Markdown files whose frontmatter has a `type`. If the bundle repo has an `AGENTS.md` or `CLAUDE.md`, its rules win over this file. Otherwise use these.

## Creating the local bundle

On first use, with no `remote`, make the bundle repo and run `git init` in it:

```text
${XDG_DATA_HOME:-~/.local/share}/factory-observer/
└── knowledge/
    ├── index.md      # okf_version frontmatter and a list of sections
    ├── log.md        # dated changes to the bundle as a whole
    └── projects/
        ├── index.md
        └── factory-skills/
            ├── index.md
            └── log.md
```

The root `knowledge/index.md`:

```markdown
---
okf_version: "0.2"
---

# Factory observations

- [Projects](/projects/index.md): what the factory's runs showed.
```

Add a `tech/index.md` section the first time a `tech/` topic is created.

## Topic layout

| Path | `type` | Holds |
| --- | --- | --- |
| `index.md` | | Lists the topic's concepts, each with its `description` |
| `log.md` | | Dated changes to the topic, newest first |
| `findings/` | `Finding` | One claim about how the factory behaves, with evidence |
| `questions/` | `Question` | One open thread, such as a proposed skill change |
| `decisions/` | `Decision` | One choice the human made, and why |

If the topic doesn't exist yet, create its `index.md` and `log.md`, add it to its parent's `index.md`, and note the new topic in the bundle's root `log.md`. Create a folder when it gets its first file. Name files after the claim in kebab case, such as `red-stage-misses-helper-imports.md`. Link with bundle-relative paths: `/projects/factory-skills/findings/<file>.md`. `index.md` files have no frontmatter, except the root's `okf_version`.

## Frontmatter

Every concept:

```yaml
---
type: Finding
title: The claim stated as a sentence
description: One line that tells an agent whether to open this file
tags: [factory, red-stage]
status: draft
generated: { by: <tool>/<model>, at: <ISO 8601 time with offset> }
---
```

`generated.by` names the agent that wrote the file, such as `claude-code/claude-opus-5-5`.

Findings also need:

- `confidence`:
  - `low`: one run showed it.
  - `medium`: two or more runs showed it, or one run plus the skill text or a tool's docs explain it.
  - `high`: a primary source, such as a tool's docs or source code, states the cause, and a run showed it.
- `sources`: entries with `id` and `resource`, cited in the body as `[^id]`. Use links that will still work later:
  - A factory skill at the commit the run used: `https://github.com/<owner>/factory-skills/blob/<sha>/skills/<skill>/SKILL.md`.
  - The project's PR, commit or Actions run, if the project repo is on GitHub.
  - A tool's docs or changelog.
  - The run itself, as `run:<run-id>`, for evidence that only the run had, such as the output of a command. Quote that evidence in the body, since the run's notes file is deleted once it's written.
- `stale_after`, for claims about a tool version or a preview feature: about 3 months ahead.

## Updating a concept

- To add a run to an existing finding, add a source, cite it, and update `confidence`. That changes the content, so remove any machine `verified` entry.
- Don't edit a concept that has a `human:` entry in `verified`. Write a new one that links to it.
- Don't delete a concept that turned out wrong. Set `status: deprecated` and link to its replacement.
- Never add a `human:` entry to `verified`, and never set `status: stable`.

## The topic log

One entry per run, newest first, under a date heading:

```markdown
## 2026-11-06

Observed run 2026-11-06-add-dark-mode in acme/web-app. Added a finding that the red stage misses helper imports, and opened a question on batching red per task.
```
