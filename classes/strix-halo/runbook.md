# The strix-halo runbook

How a Strix Halo host, Omarchy on an AMD Strix Halo whose GPU is gfx1151, comes to serve its rows:
the root steps, the suite's install, and each row's commands. The Framework, `framework`, serves
`audio` and `embedding` beside each other. Each row's settings live in the class's
[profile](profile.toml), whose keys [the schema](../README.md) defines; this runbook names them and
restates no value.

Commands with `sudo` are root steps, the architect's. The rest run as the account that serves the
rows, which the suite runs as; no `hosting` command needs `sudo`.

## Root steps

Run them once a host, before its first `hosting engine install`, from the clone
([Install the suite](#install-the-suite)). `hosting engine install` and `update` refuse a host
that lacks the nonlocal bind, pointing here.

### Docker without sudo

The account joins the `docker` group, so the suite runs Docker without `sudo`, and Docker starts
now and at every boot; the group takes effect at the next login:

```sh
sudo usermod -aG docker "$(id -un)"
sudo systemctl enable --now docker
```

The GPU's device files, `/dev/kfd` and `/dev/dri`, are open to every account on this host, so a
row's container reaches the GPU as the account, with no `--group-add`.

### The nonlocal bind

Each row publishes its port on the host's tailnet address only. Docker starts its containers at
boot before Tailscale holds that address, so the kernel must let a socket bind an address the host
doesn't hold yet. Set it now and at every boot:

```sh
echo 'net.ipv4.ip_nonlocal_bind = 1' | sudo tee /etc/sysctl.d/90-nonlocal-bind.conf
sudo sysctl --system
sysctl net.ipv4.ip_nonlocal_bind
```

The last command prints `net.ipv4.ip_nonlocal_bind = 1`. A host that already sets it in another
file under `/etc/sysctl.d` needs no second one.

### The model store

Every row's container mounts the class's model store, the profile's `store`, as its Hugging Face
cache. Create it, owned by the account, since the containers write it as that account, not as
root:

```sh
store=$(mise exec -- yq -p toml -oy '.store' classes/strix-halo/profile.toml)
sudo install -d -o "$(id -un)" -g "$(id -gn)" "$store"
```

The root filesystem is the subvolume Omarchy snapshots before every update, so a model deleted
from the store frees its space only once the last snapshot holding it ages out.

### The GTT limit

The GPU shares the host's RAM: the firmware carves out 512 MiB as its own, and the GPU reaches the
rest as GTT, system memory it maps on demand. The kernel's TTM limit caps the GTT, and defaults to
half of RAM. Set it to 112 GiB, which leaves about 13 GiB of the 125 GiB for the host; `amd-ttm`
writes `options ttm pages_limit=29360128` to `/etc/modprobe.d/ttm.conf`. Answer `n` when it offers
to reboot, since the boot images carry the option only once rebuilt:

```sh
sudo amd-ttm --set 112
sudo limine-mkinitcpio
sudo reboot
```

amdgpu's own `gttsize` option is deprecated and unset: `/etc/modprobe.d/amdgpu.conf` holds none.
After the reboot, TTM's limit, in 4 KiB pages, prints `29360128`, and the GTT the GPU reports, in
bytes, prints `120259084288`:

```sh
cat /sys/module/ttm/parameters/pages_limit
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

### The ufw rules

Omarchy runs ufw with ufw-docker, which drops routed traffic to a container's published port: a
request over the tailnet to a row's port times out though the row answers on the host. Allow the
routed traffic that arrives over the tailnet to each row's port, the profile's `port`:

```sh
for port in $(mise exec -- yq -p toml -oy '.rows[].port' classes/strix-halo/profile.toml); do
  sudo ufw route allow in on tailscale0 proto tcp to any port "$port"
done
sudo ufw status verbose
```

Each port is listed as `<port>/tcp ALLOW FWD Anywhere on tailscale0`, and again with `(v6)`. The
rules name a port, not a container, so they hold through every update. A row whose port changes in
the profile needs its new port's rule.

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
`hosting engine install` pulls the row's model into the store, builds or pulls its image, starts
its container, and records the alias on the host; `hosting engine update` and `uninstall` with no
alias act on every recorded row. The two rows stand together: `engine install` refuses rows whose
fractions sum over 1.

### audio

The row runs the profile's `image`, `ai-hosting/vllm-openai-rocm-audio`, which `engine install` and
`update` build on the host from
[`images/vllm-openai-rocm-audio`](../../images/vllm-openai-rocm-audio/Dockerfile)
([engines.md](../../context/engines.md), "The audio image").

```sh
hosting profile render audio
hosting engine install audio
hosting engine update audio
hosting engine metrics audio
hosting engine uninstall audio
```

### embedding

```sh
hosting profile render embedding
hosting engine install embedding
hosting engine update embedding
hosting engine metrics embedding
hosting engine uninstall embedding
```

### Every row

Read-only:

```sh
hosting engine status
hosting engine models
hosting engine memory
hosting model list
hosting model prune
```

`hosting engine memory` reads `amdgpu_top -p` and the GTT. `hosting model prune --yes` deletes
what `hosting model prune` lists: the models no recorded row serves, and incomplete downloads.

Replacing a row's model is `hosting profile set <alias> model=<repository>`, then
`hosting model pull <repository>`, then `hosting engine update <alias>`, then a commit of the
profile ([host-classes.md](../../context/host-classes.md), "Replacing a model").

## Reboots

The Framework's root filesystem is LUKS-encrypted. A reboot waits at the disk-unlock prompt until
a person enters the passphrase at its console, so the Framework neither returns unattended nor can
be rebooted remotely, as the GB10s can. Reboot it only with someone at its console. Once it is
unlocked, each row's container restarts by itself with `--restart unless-stopped`, and the
nonlocal bind lets it publish before Tailscale is up; a row is serving again once
`hosting engine status` shows it healthy.
