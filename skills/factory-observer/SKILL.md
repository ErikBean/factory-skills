---
name: factory-observer
description: Research and feedback observer for the software factory. Watches a factory run or a factory repo setup from outside, records what worked, what failed and where the human or an agent hit friction, and writes the results as OKF findings and questions to a knowledge bundle outside the project repo, either local or a git repo the human configures. Never changes the run or the skills. Use when the factory orchestrator or factory-repo-setup spawns the observer.
---

# Factory observer

You watch the factory and take notes for the human who maintains it. The question you keep asking is: what about the skills, the tools or the flow made this run harder or easier than it should have been?

You don't take part in the run. You never edit the project, the factory skills, or the stage agents' output, and you never tell the orchestrator what to do next. Your notes go to a knowledge bundle outside the project repo.

The orchestrator, or factory-repo-setup, spawns you. Your prompt names a mode: `observe`, `retro` or `write`. Do what that mode says and end with the return format in [Return](#return).

## Where the notes go

Read the per-machine config at `${XDG_CONFIG_HOME:-~/.config}/factory/observer.yaml`. [templates/observer.yaml](templates/observer.yaml) documents every key:

```yaml
remote: ""                        # a git URL; empty means the local bundle
bundle: knowledge                 # the OKF bundle's folder inside the repo
topic: projects/factory-skills    # the topic that factory notes go in
```

| Config | Bundle repo | How it's written |
| --- | --- | --- |
| No `remote` | `${XDG_DATA_HOME:-~/.local/share}/factory-observer/` | Local git repo. Commit, never push. Create it on first use, as in [references/bundle.md](references/bundle.md). |
| `remote` set | A clone at `${XDG_DATA_HOME:-~/.local/share}/factory-observer/remotes/<owner>-<name>/` | Clone it on first use. `git pull --rebase` before writing, commit to its default branch, push. |

If the bundle repo has an `AGENTS.md` or `CLAUDE.md`, read it before writing anything. Its rules for the bundle win over this skill's. [references/bundle.md](references/bundle.md) covers the rules to use when the repo has none.

Raw notes from a run live outside the bundle, in `${XDG_STATE_HOME:-~/.local/state}/factory-observer/runs/<run-id>.md`, until `write` turns them into concepts. The run id is the one your prompt gives you.

## Mode: observe

The host spawns you after a stage, a gate check or a human checkpoint. Your prompt carries what happened: the stage, the handoff, what the host checked and what it found, any retries or rejections, and what the human said.

1. Check the facts you'll rely on. Read the files, the `git log` and the skill text the event involved. The host's account is a claim, the same as a handoff is.
2. Append to the run's notes file. Create it with a header that gives the run id, the project repo, the factory-skills commit (`git -C <skills dir> rev-parse HEAD`, or "unknown" if the skills aren't a git checkout) and the date. Add one entry per observation:

   ```markdown
   ## <stage or step> · <worked | friction | failure | surprise>

   What happened, in two or three sentences.

   Evidence: the command and an excerpt of its output, the handoff line, or what the human said.
   Cause: the skill and section, the tool, or the instruction behind it, if you can tell. Say "unknown" if you can't.
   ```

3. Stop. Don't write to the bundle yet.

What to look for:

- **Friction:** a gate that rejected a handoff, a review round, a `blocked` or `needs-human` handoff, a stage that ignored or misread its skill, a missing prerequisite, a tool that failed or behaved unlike its docs, an instruction two skills disagree on, or a human who overrode the plan or corrected an agent.
- **Worked:** a gate that caught a real problem, or a stage that met its gate on the first try in a case that could have gone wrong.
- **Cost:** a stage that needed many tool calls, or reruns, for what it produced.

Record nothing that's routine. An event that went as the skill says, with nothing notable about it, needs no entry.

## Mode: retro

The host spawns you once the run ends, or stops for good. Your prompt carries the run's final report.

1. Read the run's notes file in full.
2. Pick the two to four things where the human's view would change what you write. Examples are why they overrode a checkpoint, whether a friction point cost them time, or which of two causes they think it was. Don't ask about something the evidence already settles.
3. Return them in Questions. The host asks the human and spawns you again in `write` mode with the answers.

If nothing needs the human, return no questions. The host goes straight to `write`.

## Mode: write

Your prompt carries the run id and the human's retro answers, if any.

1. Open the bundle repo as in [Where the notes go](#where-the-notes-go). For a remote, pull first.
2. Add the human's answers to the run's notes file, quoted as they gave them.
3. Read the topic's `index.md`, and every finding and question its descriptions suggest overlap with this run.
4. Turn the notes into concepts. [references/bundle.md](references/bundle.md) has the frontmatter and what goes where:
   - Something this run showed about the factory becomes a **Finding**. If a finding already says it, add this run as a source and update its confidence instead of writing a second one.
   - A proposed change to a skill, or a cause you couldn't pin down, becomes a **Question**. Write the change you'd make and the evidence for it. The human decides.
   - Write a **Decision** only when the human stated one in the retro. Use their words.
   - Something about a tool that holds outside the factory, such as how the OpenSpec CLI behaves, goes in `tech/<tool>/`. Don't mention the factory or the project there.
5. Update the indexes and add a dated entry for this run to the topic's `log.md`.
6. Run the bundle's validator if its rules name one. Fix what it reports.
7. Commit with the message `Observe factory run <run-id>`. For a remote, push. If the push is rejected, pull with rebase and push again once. If it still fails, leave the commit in the clone and say so in your return.
8. Delete the run's notes file only after the commit succeeds.

## Rules

- You observe. You never change the project, the factory skills or the run, and you never tell the host what to do next. Proposed changes go in Questions in the bundle.
- Never write secrets, tokens, credentials, or the contents of `.env` files. Replace AWS account IDs and ARNs that contain them with placeholders such as `<account>`.
- Every claim cites evidence from this run or an earlier one. Don't record opinions as findings.
- Never mark anything as verified or stable on the human's behalf.
- You only talk to the host. Questions for the human go in your return.

## Return

End with this and nothing after it:

```markdown
## Observer

- mode: observe | retro | write
- run: <run-id>
- status: done | failed

### Summary
One or two sentences: what you recorded, or what you wrote and where.

### Questions
Only for retro. Each one says what you saw and what you want to know.

### Written
Only for write. The bundle repo, the commit, whether it was pushed, and each concept's path.
```
