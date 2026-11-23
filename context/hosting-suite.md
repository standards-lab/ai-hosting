# The `hosting` suite

One root command, `hosting <group> <verb> [args]`, runs `bin/hosting-<group>-<verb>` from the clone
and, with no arguments, lists the commands from their `# hosting:summary=` lines. A usage error
goes to stderr and exits 2. The shared functions live in `lib/`, sourced through `lib/hosting.sh`.

**Install.** `mise run install` links one file, `~/.local/bin/hosting`, to `bin/hosting`, which
resolves its own path, so every command runs from the clone. `mise run uninstall` removes that link
only when it points into this clone. Each class's runbook gives the install steps.

## Host classes

The class list is closed, `gb10` and `strix-halo`, and shared by the profiles, the class probe,
and `HOSTING_CLASS` ([host-classes.md](host-classes.md), "Class detection").

- Only a command that differs by class detects it, once per call, and then calls its private
  per-class function: the image repository and device options, the preflight (the GB10's CDI
  spec), and GPU memory.
- Uninstall never detects.
- The preflight refuses unless `net.ipv4.ip_nonlocal_bind` is 1, pointing at the runbook's step.
  No command uses sudo.

## Groups and verbs

The suite's groups are `engine`, `model`, `profile`, `gateway`, and `key`. The `hosts` task built
the first three; the `gateway` task builds the other two.

| Command | What it does |
| --- | --- |
| `engine install <alias>...` | Checks the aliases, the fraction sum, and the preflight before touching Docker. Before changing anything, refuses an alias whose container name a container without the row label holds, running or stopped, or whose port a running one publishes, alone or inside a range, naming the container and the `docker rm -f` that removes it. Then runs `model pull` for each row's model, builds or pulls its image, starts its labeled container on the host's tailnet address, and records the alias |
| `engine update [<alias>]` | Checks and refuses each alias as install does, then pulls or builds, then replaces a row whose image ID or command differs from its running container, installs a row that is absent, and removes the superseded build if the host still has it; with nothing changed, does nothing. With no alias, acts on the recorded aliases |
| `engine uninstall [<alias>]` | Removes the row's labeled container, then its image if no other container uses it, and drops the alias from the record. With no alias, acts on the recorded aliases |
| `engine status` | Each labeled row's container state and health, and each recorded alias with no container. Flags a stranded row, a running container that is reachable at no address, with the command that recovers it: `docker network connect bridge <container>` for one on no network, and `docker restart <container>` for one on a network that publishes no port |
| `engine models` | The model each running row serves, from its `/v1/models` |
| `engine metrics <alias>` | A summary of the row's vLLM `/metrics` |
| `engine memory` | The GPU memory each row's processes hold, then each GPU process no row holds by its PID, then the pool the rows share: on gb10, nvidia-smi's per-process `used_memory` joined to each container's PIDs, with `MemAvailable`; on strix-halo, `amdgpu_top -p`'s VRAM and GTT, with amdgpu's GTT and `MemAvailable` |
| `model list` | The models in the host's store, their sizes, the recorded rows serving each, and the profile's other rows serving it |
| `model pull <repo>` | Downloads a model with hf, using the token when `hf auth whoami` succeeds, else unauthenticated; fails clearly only on a gated repository |
| `model prune [--yes]` | Lists the models no recorded row serves and incomplete downloads; deletes them only with `--yes` |
| `profile validate` | Validates every class profile, or the files given; the check runs it |
| `profile render <alias>` | Prints the full `docker run` command a row runs, one argument a line; install and update run the same command |
| `profile set <alias> <field>=<value>` | Edits the committed profile in place, validating first and writing nothing when validation fails |
| `gateway render`, `validate`, `up`, `down`, `reset`, `status` | Planned: the gateway stack ([gateway](gateway.md)) |
| `key issue <consumer>`, `key revoke <consumer>`, `key list` | Planned: a consumer's gateway key ([gateway](gateway.md)) |

The host's install record, `$XDG_STATE_HOME/hosting/aliases`, lists the aliases it stands on.
`model prune` keeps only the models those rows serve, so a host holds only what its rows serve.

hf's token stays in the host's `~/.cache/huggingface`.

Every row is an alias, checked against the class profile before Docker is touched. Each
container carries the label `ai-hosting.row`, its value the row's alias, and every listing reads
the label. Where the `engine` verbs come from is in [engines](engines.md).
