# The strix-halo runbook

How a Strix Halo host, Omarchy on an AMD Strix Halo whose GPU is gfx1151, comes to serve its rows:
the suite's install, the root steps, and each row's commands. The Framework, `framework`, serves
`audio` and `embedding` beside each other. Each row's settings live in the class's
[profile](profile.toml), whose keys [the schema](../README.md) defines; this runbook names them and
restates no value.

The architect runs the root steps, the commands with `sudo`. The rest run as the account that
serves the rows, which the suite runs as; no `hosting` command needs `sudo`.

## Install the suite

Clone ai-hosting into the serving account's home as `~/ai-hosting`. In the clone, with mise's
tools on PATH (`mise activate`), install the pinned tools, then link the suite's one command,
`~/.local/bin/hosting`, into the clone:

```sh
git clone https://github.com/standards-lab/ai-hosting.git ~/ai-hosting
cd ~/ai-hosting
mise trust
mise install
mise run install
hosting
```

`hosting` with no arguments lists every command. `mise run uninstall` removes the link.

Over non-interactive ssh, run the suite from the clone, where mise puts its tools on PATH:
`ssh <host> 'cd ~/ai-hosting && hosting engine status'`. On a host whose non-interactive shell
doesn't activate mise or put `~/.local/bin` on PATH, run it through mise instead:
`ssh <host> 'cd ~/ai-hosting && mise exec -- bin/hosting engine status'`.

A row whose model is gated needs a Hugging Face token on the host, which hf keeps in
`~/.cache/huggingface`; the suite downloads every other model without one:

```sh
mise exec -- hf auth login
```

## Root steps

Run them once on each host, in order, from the clone, after
[Install the suite](#install-the-suite) and before its first `hosting engine install`.
`hosting engine install` and `update` refuse a host that lacks the nonlocal bind, pointing here.

### The AMD tools

Two packages from Arch's `extra` repository, installed through Omarchy's package helper, which
installs only what is missing: `amd-debug-tools` provides `amd-ttm`, which
[the GTT limit](#the-gtt-limit) runs, and `amdgpu_top` is what `hosting engine memory` reads:

```sh
omarchy pkg add amd-debug-tools amdgpu_top
```

### Docker without sudo

Omarchy's sudoless Docker setup adds the account to the `docker` group, so the suite runs Docker
without `sudo`; the group takes effect after a reboot, so decline its offer to reboot now, since
[the GTT limit](#the-gtt-limit) ends in one. Omarchy enables only Docker's socket, so enable the
service too, which starts each row's container at boot:

```sh
omarchy setup security sudoless docker
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
cache. The store is the host's second NVMe, the disk that doesn't hold the LUKS-encrypted root,
formatted as plain ext4 and mounted at the store. It is not encrypted because it holds only public
model weights (`architecture/principles/development-secrets.md`, "What is not a secret"). Off the
root, it is outside the snapshots Omarchy takes before every update, so a model deleted from the
store frees its space at once.

Find the second disk: `lsblk` lists each NVMe as a `disk`, and the root's is the one with a `crypt`
device under it, mounted at `/`. The other is the store's:

```sh
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

A second disk that already holds an ext4 filesystem mounted elsewhere keeps it: skip to
[A second disk already formatted](#a-second-disk-already-formatted). Otherwise format it, which
erases it, naming it in `disk` (`/dev/` and the name `lsblk` printed); then mount it at the store
by UUID with `noatime`, at once and at every boot, and own the store as the account, since the
containers write it as that account, not as root:

```sh
disk=/dev/<second disk>
store=$(mise exec -- yq -p toml -oy '.store' classes/strix-halo/profile.toml)
sudo mkfs.ext4 "$disk"
echo "UUID=$(sudo blkid -s UUID -o value "$disk") $store ext4 defaults,noatime 0 2" |
  sudo tee -a /etc/fstab
sudo install -d "$store"
sudo systemctl daemon-reload
sudo mount "$store"
sudo install -d -o "$(id -un)" -g "$(id -gn)" "$store"
findmnt "$store"
```

`findmnt` prints the store with the disk as its source and `noatime` among its options.

The kernel may number the two NVMe drives differently after a reboot: on framework-2 the store's
disk came up under the other `nvme` name. So the fstab line names the disk by UUID, and no step
names a device after the first `lsblk`.

#### A second disk already formatted

The disk's ext4 filesystem moves to the store: in its `/etc/fstab` line (`sudoedit /etc/fstab`),
change the mountpoint to the store and add `noatime` to the options, and name the disk by its
`UUID=` (`sudo blkid`) if the line names it otherwise. If the store on the root
already holds models, stop the rows first, copy the store onto the disk at its old mountpoint, and
clear the root's copy; then mount the disk at the store, own it, and start the rows again, with
`old` the mountpoint the fstab line named:

```sh
old=<old mountpoint>
store=$(mise exec -- yq -p toml -oy '.store' classes/strix-halo/profile.toml)
docker stop $(docker ps -q --filter label=ai-hosting.row)
sudo cp -a "$store"/. "$old"/
sudo find "$store" -mindepth 1 -delete
sudo umount "$old"
sudo install -d "$store"
sudo systemctl daemon-reload
sudo mount "$store"
sudo install -d -o "$(id -un)" -g "$(id -gn)" "$store"
docker start $(docker ps -aq --filter label=ai-hosting.row)
findmnt "$store"
```

On a host with no rows yet, the two `docker` commands and the copy have nothing to move; skip
them.

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
rules name a port, not a container, so they hold through every update. The loop opens every row's
port in the profile, so a host that serves one row opens the other's too; with nothing listening
there, the open port answers nothing. A row whose port changes in the profile needs its new
port's rule.

### Remote unlock

The root filesystem is LUKS-encrypted, so a reboot waits at the console's passphrase prompt. Remote
unlock puts an SSH server, dropbear, in the initramfs, which serves the same prompt over the LAN.
The initramfs has no Tailscale, so a client reaches it through another tailnet host on the same LAN
that is up, which Tailscale SSH forwards for `ssh -J` ([Reboots](#reboots)). The console prompt
still works.

Three packages provide the initramfs's network, its SSH server, and the hook that asks for the
passphrase over SSH:

```sh
omarchy pkg add mkinitcpio-netconf mkinitcpio-dropbear mkinitcpio-utils
```

Each client that unlocks holds a dedicated ed25519 key, made on the client and never committed:

```sh
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_unlock
```

The key reaches only the unlock prompt; the passphrase is still required. Install its public key,
`~/.ssh/id_ed25519_unlock.pub` on the client, as the initramfs's root key, one line per client:

```sh
echo '<public key>' | sudo install -D -m 600 /dev/stdin /etc/dropbear/root_key
```

Omarchy's `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` sets the hook list with busybox's `encrypt`
hook. A drop-in that sorts after it replaces `encrypt` with the network, the SSH server, and
`encryptssh`, which unlocks at the console or over SSH:

```sh
sudo tee /etc/mkinitcpio.conf.d/zz-remote-unlock.conf >/dev/null <<'EOF'
_hooks=()
for _hook in "${HOOKS[@]}"; do
  if [[ $_hook == encrypt ]]; then _hooks+=(netconf dropbear encryptssh); else _hooks+=("$_hook"); fi
done
HOOKS=("${_hooks[@]}")
unset _hooks _hook
EOF
```

If a later Omarchy release drops the `encrypt` hook, the drop-in changes nothing and only the
console unlock remains.

The initramfs takes its address by DHCP on the wired NIC, named in a kernel parameter with the
host's short name in `<host>`:

```sh
echo 'KERNEL_CMDLINE[default]+=" ip=::::<host>:eth0:dhcp netconf_timeout=30"' |
  sudo tee /etc/limine-entry-tool.d/remote-unlock.conf
```

The NIC is `eth0` there, not its booted name, such as `enp191s0`: the initramfs's udev loads no
`80-net-setup-link.rules`, and a parameter that names the booted name leaves the initramfs without
a network. `netconf_timeout=30` keeps the console prompt from waiting on DHCP. The host's lease is
reserved on the router, so its LAN address is stable; no address is committed.

[The GTT limit](#the-gtt-limit)'s rebuild and reboot build the unlock into the boot image.
`limine-mkinitcpio`, which Omarchy's own scripts use, rebuilds the unified kernel image of every
installed kernel and the boot entries; `mkinitcpio -P` builds nothing useful, with no active
preset. It exits 0 even when a kernel fails, so before rebooting, check its output: it holds no
`mkinitcpio failed for kernel`, and each kernel's build runs the hooks `[netconf]`, `[dropbear]`,
and `[encryptssh]`. Dropbear generates rsa and ecdsa host keys and prints their fingerprints;
record the ecdsa fingerprint to check on the first connect. Its error about a dss key is noise,
since current dropbear dropped dss. The parameter is in the boot entries once this prints `1`:

```sh
sudo grep -c 'ip=::::<host>:eth0:dhcp' /boot/limine.conf
```

A host may carry a stale stock `linux` kernel beside `linux-omarchy`, as `framework` did, and every
`limine-mkinitcpio` then builds and patches both; once `omarchy kernel` confirms `linux-omarchy`
boots, remove it with `omarchy pkg drop linux`.

Make the first reboot after the rebuild with someone at the console, so a failed remote unlock
costs nothing, and unlock it remotely as [Reboots](#reboots) says.

### The frame buffer

In the BIOS, set the GPU's dedicated frame buffer (UMA) to 0.5 GB. Auto gave the same 512 MiB on
both hosts' current firmware, but a firmware update may change what Auto gives. The frame buffer,
in bytes, prints `536870912`:

```sh
cat /sys/class/drm/card*/device/mem_info_vram_total
```

### The GTT limit

The GPU shares the host's RAM: the firmware carves out 512 MiB as its own
([the frame buffer](#the-frame-buffer)), and the GPU reaches the rest as GTT, system memory it maps
on demand. The kernel's TTM limit caps the GTT, and defaults to half of RAM. Set it to 112 GiB,
which leaves about 13 GiB of the 125 GiB for the host; `amd-ttm` writes
`options ttm pages_limit=29360128` to `/etc/modprobe.d/ttm.conf`. Answer `n` when it offers to
reboot, since the boot images carry the option only once rebuilt. The rebuild also builds
[remote unlock](#remote-unlock) into the boot images; check its output as that step says before
rebooting:

```sh
sudo amd-ttm --set 112
sudo limine-mkinitcpio
omarchy system reboot
```

amdgpu's own `gttsize` option is deprecated and unset: `/etc/modprobe.d/amdgpu.conf` holds none.
After the reboot, TTM's limit, in 4 KiB pages, prints `29360128`, and the GTT the GPU reports, in
bytes, prints `120259084288`:

```sh
cat /sys/module/ttm/parameters/pages_limit
cat /sys/class/drm/card*/device/mem_info_gtt_total
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

The row serves the profile's `model`, which takes its input with a prefix the caller adds: each
query starts `query: ` and each passage `passage: `; the row adds neither. An input may run to the
row's `context` in tokens, counting the two special tokens the tokenizer adds; the row refuses a
longer one with a 400 and never truncates it
([findings](../../docs/findings/embedding.md#e5-probes)). A caller that counts runes sizes its
chunks from the [tokens per rune](../../docs/findings/embedding.md#e5-runes).

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

The root filesystem is LUKS-encrypted, so a reboot waits at the disk-unlock prompt; with
[remote unlock](#remote-unlock), the host reboots remotely too. About a minute after
`omarchy system reboot`, once it waits at the prompt, unlock it from a client that holds the unlock
key, jumping through a tailnet host on the same LAN that is up: each Strix Halo host jumps through
the other.

```sh
ssh -J <a host that is up> -i ~/.ssh/id_ed25519_unlock root@<LAN address>
```

The login runs `cryptsetup_shell`, which asks for the passphrase, opens the root, and stops the
console's Plymouth prompt, so boot continues. Once the root opens, it prints `cryptsetup: no
process found`, which is expected under Omarchy's Plymouth splash: the console prompt is
Plymouth's, not a waiting `cryptsetup`'s. The console prompt still works. A client keeps the
connection in its own `~/.ssh/config`, never committed, such as:

```sshconfig
Host <host>-unlock
  HostName <LAN address>
  User root
  ProxyJump <other host>
  IdentityFile ~/.ssh/id_ed25519_unlock
  IdentitiesOnly yes
  RequestTTY yes
```

Once the host is unlocked, each row's container restarts by itself with `--restart unless-stopped`,
and the nonlocal bind lets it publish before Tailscale is up; a row is serving again once
`hosting engine status` shows it healthy.
