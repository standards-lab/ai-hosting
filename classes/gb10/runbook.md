# The gb10 runbook

How a GB10 host, DGX OS on an NVIDIA GB10, comes to serve its rows: the root steps, the suite's
install, and each row's commands. gb10-1 serves `agent` and gb10-2 serves `vision`. Each row's
settings live in the class's [profile](profile.toml), whose keys [the schema](../README.md)
defines; this runbook names them and restates no value.

The architect runs the root steps, the commands with `sudo`. The rest run as the account that
serves the rows, which the suite runs as; no `hosting` command needs `sudo`.

## Root steps

Run them once on each host, before its first `hosting engine install`, from the clone
([Install the suite](#install-the-suite)). `hosting engine install` and `update` refuse a host
without the nonlocal bind, or whose CDI spec names a missing driver file, pointing here.

### Docker without sudo

The account joins the `docker` group, so the suite runs Docker without `sudo`; the group takes
effect at the next login:

```sh
sudo usermod -aG docker "$(id -un)"
```

### The nonlocal bind

Each row publishes its port on the host's tailnet address only. Docker starts its containers at
boot before Tailscale holds that address, so the kernel must let a socket bind an address the host
doesn't hold yet. Set it now and at every boot:

```sh
echo 'net.ipv4.ip_nonlocal_bind = 1' | sudo tee /etc/sysctl.d/90-nonlocal-bind.conf
sudo sysctl --system
sysctl net.ipv4.ip_nonlocal_bind
```

The last command prints `net.ipv4.ip_nonlocal_bind = 1`.

### The model store

Every row's container mounts the class's model store, the profile's `store`, as its Hugging Face
cache. Create it, owned by the account, since the containers write it as that account, not as
root:

```sh
store=$(mise exec -- yq -p toml -oy '.store' classes/gb10/profile.toml)
sudo install -d -o "$(id -un)" -g "$(id -gn)" "$store"
```

### The CDI spec

The NVIDIA Container Toolkit mounts the driver's libraries into a GPU container from a CDI spec it
generates at boot. A driver upgrade without a reboot leaves the spec naming a library that is
gone, and every GPU container then fails to start with `failed to fulfil mount request`.
`hosting engine install` and `update` refuse such a host, printing the spec's path; regenerate it
after every upgrade that moves the driver, with the path the refusal prints:

```sh
sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml
```

A reboot regenerates it too.

## Install the suite

In a clone of ai-hosting, with mise's tools on PATH (`mise activate`), install the pinned tools,
then link the suite's one command, `~/.local/bin/hosting`, into the clone:

```sh
mise trust
mise install
mise run install
hosting
```

`hosting` with no arguments lists every command. `mise run uninstall` removes the link.

A row whose model is gated needs a Hugging Face token on the host, which hf keeps in
`~/.cache/huggingface`; the suite downloads every other model without one:

```sh
mise exec -- hf auth login
```

## The rows

`hosting profile render <alias>` prints the `docker run` command a row runs, without running it.
`hosting engine install` pulls the row's model into the store and its image, starts its container,
and records the alias on the host; `hosting engine update` and `uninstall` with no alias act on
every recorded row.

### agent

gb10-1's row.

```sh
hosting profile render agent
hosting engine install agent
hosting engine update agent
hosting engine metrics agent
hosting engine uninstall agent
```

### vision

gb10-2's row.

```sh
hosting profile render vision
hosting engine install vision
hosting engine update vision
hosting engine metrics vision
hosting engine uninstall vision
```

### Every row

Read-only, on any host:

```sh
hosting engine status
hosting engine models
hosting engine memory
hosting model list
hosting model prune
```

`hosting model prune --yes` deletes what `hosting model prune` lists: the models no recorded row
serves, and incomplete downloads.

Replacing a row's model is `hosting profile set <alias> model=<repository>`, then
`hosting model pull <repository>`, then `hosting engine update <alias>`, then a commit of the
profile ([host-classes.md](../../context/host-classes.md), "Replacing a model").

## Reboots

A GB10 reboots unattended, and can be rebooted remotely: each row's container restarts by itself
with `--restart unless-stopped`, and the nonlocal bind lets it publish before Tailscale is up. A
row is serving again once `hosting engine status` shows it healthy; the agent's start, which loads
its weights from a cold page cache, takes the longest.
