# multilingual-e5-large on Foundry managed compute

What overflow for the [gateway](gateway.md)'s embedding route would deploy. Acceptance proves a
Foundry managed-compute endpoint through the provider shape before the route gets an Azure group.

**Sourced.** Re-read 2026-11-23 from public pages, without signing in. [A] renders without
sign-in only in part: its header, its description and its API reference, not its license terms,
deployment options, regions or SKUs. A fact marked *unconfirmed* is one [A] carries only past
sign-in or in data its public page doesn't render; it keeps the first read, by 2026-11-20, when
this note was first committed. The registry entry itself, read through the Azure CLI on
2026-11-23 [G], settles the license, the deployment options and the engine.

- The catalog entry, `intfloat-multilingual-e5-large`, is a Hugging Face model by intfloat,
  version 3, generally available, an embeddings model: confirmed. [A] MIT-licensed (`license:
  mit`): confirmed. [G]
- Hugging Face's collection deploys on managed compute, which needs a hub-based (classic)
  project: confirmed. [B] This model has no serverless or per-token offer: confirmed, since its
  only deployment option is `MaaP`, managed compute. [G] Shared compute capacity is enabled
  (`SharedComputeCapacityEnabled: true`). [G]
- The registry is geo-replicated: confirmed, though [B] now says to all Azure regions rather than
  naming about 30. The deployable regions aren't stated. [B]
- It serves Hugging Face Text Embeddings Inference (TEI): a native `POST` taking `inputs`, and
  `normalize`, `prompt_name`, `truncate` and `truncation_direction` under `parameters`, and an
  OpenAI-compatible `/v1/embeddings`. `truncate` defaults to false, and `prompt_name` `query`
  prepends `query: `: confirmed. [A] The maximum, 512 tokens: unconfirmed, since [A] says only
  "the maximum supported size"; the model's card and the served row give 512
  ([findings](../docs/findings/embedding.md#e5-probes)).
- The engine is `tei-gpu-extra-small` (`skuBasedEngineIds`): confirmed. [G] That no recommended
  SKU is published (`inferenceRecommendedSkus` null): unconfirmed, since [G] doesn't show it. [A]
- Linux pay-as-you-go VM prices, by the hour, which managed compute bills: Standard_NC4as_T4_v3
  $0.526 in East US and East US 2; NC8as_T4_v3 $0.752 in both; DS3_v2 $0.293 in East US, $0.229
  in East US 2: confirmed, as `Virtual Machines` meters (the note called them managed hosting
  prices). [C] Managed compute adds no surcharge beyond compute and network, and quota must cover
  20% more instances on some SKUs, which cost nothing unless a system operation runs on them:
  confirmed. [D]
- Autoscale runs through Azure Monitor with a minimum, a maximum and a default instance count;
  scale to zero isn't documented: confirmed. [E]
- For comparison, per million tokens: text-embedding-3-large $0.13 Global, $0.143 Regional or
  Data Zone; text-embedding-3-small $0.02 Global, $0.022 Regional or Data Zone: confirmed. [C]

**Inferred.**

- The SKU is Standard_NC4as_T4_v3, from the engine name; the deploy dialog confirms it. At 730
  hours a month that is about $384; NC8as_T4_v3 about $549, DS3_v2 about $214 (East US) or $167
  (East US 2).
- No pause to zero without deleting the deployment (a community answer of 2025-09-27, re-read
  2026-11-23, [F]), so plan at least one instance always on.
- An input over 512 tokens is rejected unless the request sets `truncate`.

Sources: [A] `https://ai.azure.com/catalog/models/intfloat-multilingual-e5-large`; [B]
`https://learn.microsoft.com/en-us/azure/foundry-classic/concepts/foundry-models-overview`; [C]
`https://prices.azure.com/api/retail/prices`; [D]
`https://learn.microsoft.com/en-us/azure/machine-learning/concept-endpoints-online`; [E]
`https://learn.microsoft.com/en-us/azure/machine-learning/how-to-autoscale-endpoints`; [F]
`https://learn.microsoft.com/en-us/answers/a/12259624` (community); [G] `az ml model show
--registry-name HuggingFace --name intfloat-multilingual-e5-large --version 3`. The deploy flow:
`https://learn.microsoft.com/en-us/azure/foundry-classic/how-to/deploy-models-managed`.
