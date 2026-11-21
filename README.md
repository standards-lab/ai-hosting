# ai-hosting

ai-hosting specifies how the organization's workstations host models: the vLLM rows each host
class serves and the one gateway in front of them. Nothing is built yet; the working context,
with each planned capability's note, starts at [`context/README.md`](context/README.md).

## Secrets

`fnox.toml` holds ai-hosting's development-time secrets, the Azure AI Foundry account's key and
name, encrypted with [age](https://age-encryption.org) to the maintainer's recipients. The
ciphertext is safe to read, but only those recipients can decrypt it. Each secret says what it is,
what reads it, and how to generate your own; list them, with no key, with:

```sh
mise secrets ls
```

To use your own values, generate an age identity with `age-keygen -o ~/.config/fnox/age.txt`,
then write each value to the gitignored `fnox.local.toml`, which overrides `fnox.toml`. Give
that file an age provider whose recipient is your own public key (`age-keygen -y
~/.config/fnox/age.txt`), then run:

```sh
fnox -c ./fnox.local.toml set AZURE_FOUNDRY_KEY
```

In a fork, replace the recipients in `fnox.toml` with your own and set each value again. A plain
`fnox set` writes to the committed `fnox.toml`, so name `fnox.local.toml` with `-c` unless you
mean to change the committed file. See [context/secrets.md](context/secrets.md).

### Adding a device

A device decrypts `fnox.toml` with its own age identity, which never leaves it. To add one:

1. On the new device, clone ai-hosting, run `mise trust` and `mise install`, then generate its
   identity with the pinned age and print its public key:

   ```sh
   mkdir -p -m 700 ~/.config/fnox
   (umask 077; mise exec -- age-keygen -o ~/.config/fnox/age.txt)
   mise exec -- age-keygen -y ~/.config/fnox/age.txt
   ```

   Keep `age.txt` a plain 0600 file; no dotfiles repository tracks or links it.
2. Send the public key to a device that can already decrypt, and add it to
   `[providers.age.recipients]` in `fnox.toml` under the device's short name.
3. There, re-encrypt every value to the new recipient list, and check that the values still
   decrypt and that `mise run check` passes:

   ```sh
   fnox -c ./fnox.toml reencrypt -p age --force
   ```

4. Commit `fnox.toml` and pull it on the new device. `fnox -c ./fnox.toml get <KEY> | wc -c`
   there confirms it decrypts without printing the value.

Removing a recipient doesn't revoke it (`architecture/principles/development-secrets.md`, "Adding
a device, rotating, and restoring"); rotate each value at the source that issues it, then set it
again.
