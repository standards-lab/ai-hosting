# Cleanup

What the `cleanup` task removes, so ai-hosting is the one hosting repository on each workstation
and a host holds only what its rows serve. Each item is unconfirmed until `cleanup` checks it on
the host, and the architect runs the steps that need root. What ai-hosting doesn't carry from the
spikes' files is in [engines](engines.md), [host-class profiles](host-classes.md), and
[the gateway](gateway.md).

**Every workstation**

- Clones of experiment.hosting's spikes (spike-model-engines, spike-model-gateway,
  spike-model-hosting, spike-hosting-upgrades, spike-model-layout).
- llama.cpp: any `llama` container, llama.cpp image, `llama-router` unit, and `/opt/llama.cpp`.
- Any vLLM container without ai-hosting's row label.
- Images, units, and sudoers rules no `hosting` command created.

**Framework**

- `~/repos/spike-model-engines`, with its uncommitted audio Dockerfile edit; the edit is left
  alone and goes with the clone.
- The spike-named audio images, `spike-model-engines/vllm-openai-rocm-audio:*`.
- The llama.cpp router's paths: `/opt/llama.cpp/current`, `/etc/llama-router`, and its system
  unit.
- `outpost`'s links in `~/.local/bin` (`outpost` and `outpost-*`). A read-only ssh check found
  none there.
- The ufw rules for ports 8000 and 8080, which no strix-halo row uses.

**gb10-1 and gb10-2**

- Native vLLM: `/opt/vllm`, `/etc/systemd/system/vllm-server.service`, and
  `/etc/sudoers.d/vllm-server`.

**gb10-2**

- spike-ai-pipeline's host clone and its router. A read-only ssh check found no spike-ai-pipeline
  clone in `~/repos`.
- `~/gateway`, after the old project is down: its `postgres.env`, the rendered config, the old
  volumes, the four built images, and the pulled agentgateway image.

## Open at the cleanup plan

- Which spike clones each host holds.
