# Factory config

The orchestrator reads `factory.config.yaml` at the root of the project being built, then `factory.config.local.yaml` if it exists, and merges the second over the first. Keep the local file out of git. It is for settings that mustn't be published, such as paths to private notes. Every key is optional. Missing keys take the defaults below, and with no file at all the factory runs on the defaults. [../templates/factory.config.yaml](../templates/factory.config.yaml) is a copy to start from.

## Defaults

```yaml
workflow:
  spec: openspec        # openspec | none
  tests: red-green      # red-green | tests-with-code | none

tdd:
  batch: group          # group | task | change

confirm:
  before_build: true    # show the flow and wait for a yes before any stage runs
  after_spec: true      # human reviews the OpenSpec change before tests are written
  before_ship: true     # human approves the commit, archive and push

commands:
  test: ""              # detected from the project when empty
  lint: ""              # run by green and ship when set
  typecheck: ""         # run by green and ship when set
  deploy_dev: ""        # deploys the branch's dev stage; green runs it when set
  smoke_dev: ""         # smoke-tests the deployed dev stage
  destroy_dev: ""       # destroys the branch's dev stage by hand; CI does it when a PR closes

dev:
  profile: ""           # AWS CLI profile the dev commands run with

review:
  max_rounds: 2         # review → fix loops before the human is asked
  verify: true          # verifiers check blocking and should-fix findings before anyone acts on them
  requirements: []      # outside sources the change must agree with; see below
  checks: []            # extra commands whose output the reviewer uses as evidence

ship:
  mode: pr              # pr | commit | none
  branch_prefix: factory/
  archive: true         # run `openspec archive` as part of ship
```

## Keys

### `workflow.spec`

- `openspec`: the spec stage writes an OpenSpec change, and later stages work from its scenarios and tasks.
- `none`: no spec stage. The orchestrator writes acceptance criteria in the chat and gets the human's approval. They stand in for scenarios.

### `workflow.tests`

- `red-green`: a red stage writes failing tests before each green stage.
- `tests-with-code`: no red stage. The implementer writes the tests along with the code.
- `none`: no tests are written. The reviewer flags this as a risk on every run.

### `tdd.batch`

The size of each red-green cycle:

- `group`: one cycle per numbered group in `tasks.md`.
- `task`: one cycle per checkbox. This is the closest to classic TDD, but it spawns the most agents.
- `change`: one cycle for the whole change.

### `confirm.*`

These are the human checkpoints. Turning `before_build` off lets the factory start without asking, but it still prints the flow it's using. Leave `before_ship` on unless the run can't reach anything shared, because ship can push and open a PR.

### `commands.deploy_dev`, `commands.smoke_dev`, `commands.destroy_dev` and `dev.profile`

For an app with a `dev` stage in a sandbox account, such as one `factory-repo-setup` set up. When `deploy_dev` is set, green ends by deploying the branch's `dev` stage and running `smoke_dev` against it, and review checks the result. The `dev` stage stays up while the pull request is open, and the repo's CI destroys it when the pull request merges or closes. `destroy_dev` is for removing it by hand, such as when ship didn't open a pull request.

The commands run with `AWS_PROFILE` set to `dev.profile`, which must be a profile for the agent account, never an admin profile or one for production. `deploy_dev` needs `dev.profile`; with `deploy_dev` set and no profile, green stops with `needs-human`.

### `review.verify`

With `verify` on, the orchestrator spawns verifiers that try to refute each finding before it goes to the implementer or the human. Each blocking finding gets three verifiers and survives on two confirmations. Each should-fix finding gets one. Nits aren't verified. Severity can be lowered by verification but never raised. Turn it off for a quick run where review cost matters more than false findings.

### `review.requirements`

Sources outside the change's own OpenSpec change that it must agree with, such as specs in another repo, recorded decisions, or the templates the repo was set up from. The reviewer reads each one and reports where the change contradicts it. When sources disagree, findings list them all, ranked: the change's own spec and `spec` sources, then `decision`, then `template`, then general practice.

Each entry has:

- `name`: how findings refer to it.
- `kind`: `spec`, `decision` or `template`.
- `path` or `url`: a file or folder on disk, or a page the reviewer can fetch. In a `url`, `{pinned}` stands for the factory-skills commit in `.agents/factory-skills.json`.
- `private`: `true` if it must not be quoted, linked or named in the repo or a pull request. Findings then state what it requires as a plain requirement. Put private entries in `factory.config.local.yaml`, so their paths aren't published either.

```yaml
review:
  requirements:
    - name: account specs
      kind: spec
      url: https://github.com/example/account-setup/tree/main/openspec/specs
    - name: repo setup templates
      kind: template
      url: https://github.com/example/factory-skills/tree/{pinned}/skills/factory-repo-setup/templates
```

### `review.checks`

Commands the reviewer runs in addition to the tests, lint and typecheck, whose output it treats as evidence, such as a workflow scanner. A check's warning becomes a finding only when the reviewer can say what it breaks. The commands must be installed where the factory runs.

```yaml
review:
  checks:
    - zizmor --offline .github/workflows
```

### `ship.mode`

- `pr`: commit, push the branch and open a pull request.
- `commit`: commit to the branch and don't push.
- `none`: leave the changes uncommitted for the human.

## Examples

A quick local run with no checkpoints between stages:

```yaml
confirm:
  after_spec: false
ship:
  mode: commit
```

A project that doesn't use OpenSpec:

```yaml
workflow:
  spec: none
```
