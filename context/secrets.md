# Secrets

ai-hosting's development-time secrets follow the [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md),
which holds the convention and every procedure. The [README](../README.md#secrets) lists the
secrets and recipients. What follows is ai-hosting's own.

- `AZURE_FOUNDRY_KEY` is the Azure AI Foundry account's key and `AZURE_FOUNDRY_ACCOUNT` its
  resource name; the [gateway](gateway.md)'s overflow to Azure AI Foundry reads both.
  The values came from spike-model-gateway's `.state/azure`.
- The [gateway](gateway.md) task builds the `key` group on this file. Its verbs are the only ones
  that call fnox; the suite has no `secrets` group. Where `key issue` writes an issued key is open
  at the gateway plan.
- Secrets reach the containers only as Compose secrets fed by fnox, and the rendered config holds
  no secret ([gateway](gateway.md)).
- `scripts/lint-secrets.sh` is the principle's `lint-secrets`; go-ai and docinfer carry copies
  that differ only in their `See` line.
- Azurite's well-known key, MinIO's admin/secret, Postgres's "app", and go-web-service's
  `secrets.example.json` are published development credentials, which stay committed.
