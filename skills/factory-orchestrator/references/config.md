# Factory config

The orchestrator reads `factory.config.yaml` at the root of the project being built. Every key is optional. Missing keys take the defaults below, and with no file at all the factory runs on the defaults. [../templates/factory.config.yaml](../templates/factory.config.yaml) is a copy to start from.

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
