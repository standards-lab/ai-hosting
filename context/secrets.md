# Secrets

How development-time secrets reach ai-hosting. The `secrets` task builds the store and the
convention; the [gateway](gateway.md) task builds the `key` group on it.

- The workspace's development-time secret convention is fnox's age provider, read through mise's
  `[secrets.fnox]`, with a pinned `fnox exec` as the fallback. The values live in a private
  `secrets` store repository, which each consumer's `fnox.toml` imports from its sibling
  checkout: a global file and the consumer's own file, the repository's scope overriding the
  global one.
- The store holds the Foundry key and account, and the live spike gateway's `go-ai` key until the
  gateway task replaces it with issued keys.
- Secrets reach the containers only as Compose secrets fed by fnox, and the rendered config holds
  no secret ([gateway](gateway.md)).
- A consumer's machine is an age recipient and reads its key, which `key issue` stored, after
  pulling the store.
- The `key` group's verbs are the only ones that call fnox; the suite has no `secrets` group.
- A published development credential is not a secret and stays committed: Azurite's well-known
  key, MinIO's admin/secret, Postgres's "app", and go-web-service's `secrets.example.json`.
