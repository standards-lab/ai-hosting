# The `hosting` suite

One root command, `hosting <group> <verb> [args]`, runs `hosting-<group>-<verb>` from the clone
and lists the commands from their `# hosting:summary=` lines. A usage error goes to stderr and
exits 2. The `hosts` task builds the suite from spike-model-engines' dispatcher
([engines](engines.md)).

**Install.** `mise run install` links one file, `~/.local/bin/hosting`, to the dispatcher; the
dispatcher resolves its own path, so every command runs from the clone. `mise run uninstall`
removes that link only when it points into this clone.

## Host classes

The class list is closed, `gb10` and `strix-halo`, and shared by the
[profile](host-classes.md), the detection function, and `HOSTING_CLASS`.

- One detection function sets the class from a positive probe of each class and refuses a host
  that matches neither. `HOSTING_CLASS` overrides it and is checked against the list.
- Only a command that differs by class detects, once per call, and then calls its private
  per-class function: the image repository and device options, the preflight (the GB10's CDI
  spec), GPU memory, and model prune.
- Uninstall never detects.
- The preflight refuses unless `net.ipv4.ip_nonlocal_bind` is 1, pointing at the runbook's step.
  No command needs sudo.

## Groups and verbs

The suite's groups are `engine`, `model`, `profile`, `gateway`, and `key`.

| Command | What it does | Task |
| --- | --- | --- |
| `engine install <alias>...` | Starts each named row from the class profile, and records the aliases on the host, outside git; runs `model pull` for the row's model first, and builds the row's image when it names one | hosts |
| `engine update [<alias>]` | Pulls or builds first, then replaces a row whose image ID or command differs from its running container; installs a row that is absent; removes the superseded build; runs `model pull` first. With no alias, acts on the recorded aliases | hosts |
| `engine uninstall [<alias>]` | Removes the row's container, found by its row label. With no alias, acts on the recorded aliases | hosts |
| `engine status` | Each labeled row's container state and health, and the stranded-container check: a running container with no published port or no network, printing `docker network connect bridge <container>` | hosts |
| `engine models` | The model a row serves, from its `/v1/models` | hosts |
| `engine metrics <alias>` | A summary of the row's `/metrics` | hosts |
| `engine memory` | GPU memory per process, per class | hosts |
| `model list` | The models in the host's store, their size, and which rows use them | hosts |
| `model pull <repo>` | Downloads a model with hf, using the token when `hf auth whoami` succeeds, else unauthenticated; fails clearly only on a gated repository | hosts |
| `model prune [--yes]` | Lists the models no row of the class profile uses and incomplete downloads; deletes them only with `--yes` | hosts |
| `profile validate` | Validates the host-class profiles; the check runs it over every committed profile | hosts |
| `profile render <alias>` | Prints the `vllm serve` command and container settings a row runs; install and update call the same function | hosts |
| `profile set <alias> <field>=<value>` | Edits the committed profile, validating before it writes | hosts |
| `gateway render`, `validate`, `up`, `down`, `reset`, `status` | The gateway stack ([gateway](gateway.md)) | gateway |
| `key issue <consumer>`, `key revoke <consumer>`, `key list` | A consumer's gateway key ([gateway](gateway.md)) | gateway |

hf's token stays in the host's `~/.cache/huggingface`.

Every row is an alias, checked against the class profile before Docker is touched. Each
container carries a label with its row's id, and every listing reads the label. Where the
`engine` verbs come from is in [engines](engines.md).
