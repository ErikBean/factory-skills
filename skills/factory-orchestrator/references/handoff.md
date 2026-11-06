# Stage handoff

Every stage agent ends its run with a handoff in this format and nothing after it. The orchestrator reads it, checks the claims, and decides what runs next.

```markdown
## Handoff

- stage: spec | red | green | review | ship
- status: done | blocked | needs-human
- change: <openspec change id>
- batch: <task group, task, or "change">

### Summary
Two or three sentences on what this stage did.

### Artifacts
- path/to/file: what it is

### Evidence
The commands you ran to check your work, and an excerpt of what they printed.

### Questions
Only for needs-human. Each question gives the options and your recommendation.

### Notes for the next stage
Anything the next agent needs that isn't in the artifacts.
```

## Status

- `done`: the stage's gate is met, and the evidence shows it.
- `blocked`: the stage can't finish for a reason the orchestrator might fix, such as a missing tool or a failing pre-existing test. Say what would unblock it.
- `needs-human`: the stage needs a decision only the human can make. Put the decision in Questions.

Stage agents never ask the human directly, and never guess at decisions that change what gets built.
