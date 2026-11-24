# Secrets

ai-hosting's development-time secrets follow the [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md),
which holds the convention and every procedure. The [README](../README.md#secrets) lists the
secrets and recipients. What follows is ai-hosting's own.

- `AZURE_FOUNDRY_KEY` is the Azure AI Foundry account's key and `AZURE_FOUNDRY_ACCOUNT` its
  resource name; the [gateway](gateway.md)'s overflow to Azure AI Foundry reads both.
  The values came from spike-model-gateway's `.state/azure`.
- Two verbs call fnox, and the suite has no `secrets` group. `hosting gateway up` reads the
  Foundry key and account from this file. `hosting key issue` writes an issued key into the
  consumer repository's own `fnox.toml`, as `AI_GATEWAY_TOKEN`, encrypted to that file's
  recipients; ai-hosting commits only its SHA-256, in the gateway's key list
  ([gateway document](../docs/gateway.md#keys)).
- The Foundry key reaches agentgateway only as a Compose secret fed by fnox; the Foundry account
  name reaches it through its environment, since `hostOverride` has no file form. The rendered
  config holds no secret ([gateway document](../docs/gateway.md#secrets-and-postgres)).
- `scripts/lint-secrets.sh` is the principle's `lint-secrets`; go-ai and docinfer carry copies
  that differ only in their `See` line.
- Azurite's well-known key, MinIO's admin/secret, Postgres's "app", go-web-service's
  `secrets.example.json`, and the gateway's Postgres credential, `agentgateway`, are published
  development credentials, which stay committed.
