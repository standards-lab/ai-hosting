# Secrets

How development-time secrets reach ai-hosting. The `secrets` task builds the convention; the
[gateway](gateway.md) task builds the `key` group on it. The principle behind it is the
architecture page `architecture/principles/development-secrets.md`.

- Each repository holds its own secrets in a committed root `fnox.toml`, with `root = true`, and
  no store repository holds them. fnox's age provider writes each value as ciphertext inline, so
  the file is safe to commit and stays a public reference.
- ai-hosting's `fnox.toml` encrypts to two named recipients: `laptop`, the architect's machine,
  whose identity is `~/.config/fnox/age.txt` (a plain 0600 file that no dotfiles repository
  tracks), and `backup`, whose identity is held offline. Only public keys are committed.
- It holds `AZURE_FOUNDRY_KEY`, the Azure AI Foundry account's key, and
  `AZURE_FOUNDRY_ACCOUNT`, the account's resource name; the gateway's overflow to
  [Azure AI Foundry](foundry-overflow.md) reads both. The values came from
  spike-model-gateway's `.state/azure`.
- Every secret carries a `description` saying what it is, what reads it, and how to generate
  one's own, and a `url` to the page that issues it, so `mise secrets ls` and
  `fnox -c ./fnox.toml env --json --describe` explain the file without a key.
- mise pins fnox and age and declares `[secrets.fnox]`; a task receives a secret only when its
  `secrets = [...]` lists the key, and mise redacts the value from the task's output. No task
  lists one yet. With no identity, fnox leaves the variable unset and warns, so `mise run check`
  and `mise run currency` run unchanged without a key.
- `scripts/lint-secrets.sh`, which `mise run check` runs without a key, refuses a secret with no
  description, an age-provider value that isn't age ciphertext, a tracked file holding an age
  secret key, and a `fnox.local.toml` git doesn't ignore. It holds nothing specific to
  ai-hosting, so another repository copies it unchanged.
- A machine's own values go in the gitignored `fnox.local.toml`, encrypted to that machine's own
  recipient; the [README](../README.md#secrets) gives the steps.
- Secrets reach the containers only as Compose secrets fed by fnox, and the rendered config holds
  no secret ([gateway](gateway.md)).
- The `key` group's verbs are the only ones that call fnox; the suite has no `secrets` group.
  Where `key issue` writes an issued key is open at the gateway plan.
- A published development credential is not a secret and stays committed: Azurite's well-known
  key, MinIO's admin/secret, Postgres's "app", and go-web-service's `secrets.example.json`.
