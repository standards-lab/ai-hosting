# multilingual-e5-large on Foundry managed compute

What overflow for the [gateway](gateway.md)'s embedding route would deploy. Acceptance proves a
Foundry managed-compute endpoint through the provider shape before the route gets an Azure group.
The `embedding` task re-reads the sources below before relying on them.

**Sourced.**

- The catalog entry, `intfloat-multilingual-e5-large`, is a Hugging Face registry model, version
  3, MIT-licensed. It deploys on managed compute only, with no serverless or per-token offer, and
  needs a hub-based (classic) project. The registry is replicated in about 30 regions, East US and
  East US 2 among them; the deployable regions aren't stated. [A], [B]
- It serves Hugging Face TEI: a native `POST` taking `inputs`, `normalize`, `prompt_name`,
  `truncate`, and `truncation_direction`, and an OpenAI-compatible `/v1/embeddings`. The model's
  maximum is 512 tokens, and `truncate` defaults to false. [A]
- No recommended SKU is published (`inferenceRecommendedSkus` is null); the engine is
  `tei-gpu-extra-small`. [A]
- Managed hosting prices, by the hour: Standard_NC4as_T4_v3 $0.526 in East US and East US 2;
  NC8as_T4_v3 $0.752; DS3_v2 $0.293 in East US, $0.229 in East US 2. Managed compute adds no
  surcharge beyond compute and network, and quota must cover 20% more instances, which aren't
  billed. [C], [D]
- Autoscale runs through Azure Monitor with a minimum and maximum; scale to zero isn't
  documented. [E]
- For comparison, per million tokens: text-embedding-3-large $0.13 Global, $0.143 Regional or
  Data Zone; text-embedding-3-small $0.02 Global, $0.022 Regional. [C]

**Inferred.**

- The SKU is Standard_NC4as_T4_v3, from the engine name; the deploy dialog confirms it. At 730
  hours a month that is about $384; NC8as_T4_v3 about $549, DS3_v2 about $214 (East US) or $167
  (East US 2).
- No pause to zero without deleting the deployment (a community answer, [F]), so plan at least one
  instance always on.
- An input over 512 tokens is rejected unless the request sets `truncate`.

Sources: [A] `https://ai.azure.com/catalog/models/intfloat-multilingual-e5-large`; [B]
`https://learn.microsoft.com/en-us/azure/foundry-classic/concepts/foundry-models-overview`; [C]
`https://prices.azure.com/api/retail/prices`; [D]
`https://learn.microsoft.com/en-us/azure/machine-learning/concept-endpoints-online`; [E]
`https://learn.microsoft.com/en-us/azure/machine-learning/how-to-autoscale-endpoints`; [F]
`https://learn.microsoft.com/en-us/answers/a/12259624` (community). The deploy flow:
`https://learn.microsoft.com/en-us/azure/foundry-classic/how-to/deploy-models-managed`.
