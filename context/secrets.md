# Secrets

ai-hosting's development-time secrets follow the [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md),
which holds the convention and every procedure. The [README](../README.md#secrets) lists the
secrets and recipients. What follows is ai-hosting's own.

- `AZURE_FOUNDRY_KEY` is the Azure AI Foundry account's key and `AZURE_FOUNDRY_ACCOUNT` its
  resource name; the [gateway](gateway.md)'s overflow to Azure AI Foundry reads both.
  The values came from spike-model-gateway's `.state/azure`.
- Two verbs call fnox, and the suite has no `secrets` group. `hosting gateway up` reads the
  Foundry key and account from this file, and the [gateway
  document](../docs/gateway.md#secrets-and-postgres) says how each reaches agentgateway with no
  secret in the rendered config. `hosting key issue` writes an issued key into the consumer
  repository's own `fnox.toml`, and ai-hosting commits only its SHA-256
  ([gateway document](../docs/gateway.md#keys)).
- `scripts/lint-secrets.sh` is the principle's `lint-secrets`; go-ai and docinfer carry copies
  that differ only in their `See` line.
- Azurite's well-known key, MinIO's admin/secret, Postgres's "app", go-web-service's
  `secrets.example.json`, and the gateway's Postgres credential, `agentgateway`, are published
  development credentials, which stay committed.
