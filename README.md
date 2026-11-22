# ai-hosting

ai-hosting specifies how the organization's workstations host models: the vLLM rows each host
class serves and the one gateway in front of them. Only its development-time secrets are built;
the working context, with each planned capability's note, starts at
[`context/README.md`](context/README.md).

## Secrets

`fnox.toml` holds ai-hosting's development-time secrets, the Azure AI Foundry account's key and
name, encrypted to three recipients: `laptop`, `gb10-2`, and the offline `backup`. No task is
granted one yet. Each secret says what it is, what reads it, and how to generate your own; this
lists them without a key:

```sh
mise secrets ls
```

The [development-secrets
principle](https://github.com/standards-lab/architecture/blob/main/principles/development-secrets.md)
gives the convention and every step: supplying your own values, adding a device, rotating, and
restoring.
