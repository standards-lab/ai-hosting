# ai-hosting standards

The judgement calls the standards-reviewer applies to ai-hosting, beyond what `mise run check`
enforces: each one line, with a pointer to the architecture page that applies. They come from
ai-hosting's notes in `context/`, and apply to its shell, TOML, compose files, and Markdown;
ai-hosting holds no Go, so Go Elemental's pages don't apply.

- `architecture/principles/comments.md`: the reasoning a comment points to lives in ai-hosting's
  documents.
- `architecture/principles/comments.md`: ai-hosting carries no `Adapted from` provenance comments;
  a spike source is cited in the notes or the commit message instead.
- `architecture/principles/rolling-currency.md`: every pin is explicit and one that `mise run
  currency` reads, and a pin held behind the latest release carries its reason beside it.
- `architecture/principles/minimal-footprint.md`: no Go toolchain and no module; a need is met by
  shell, Docker Compose, and a mise-pinned standard tool before anything heavier, and a host holds
  only what its rows serve.
- `architecture/principles/validation-first.md`: a command validates the host-class profile, the
  gateway's config, or its argument before its first effect, and refuses an unknown host class
  before it touches Docker or the host.
- `architecture/principles/context-architecture.md`: each detail has one home and every other
  file links it: a row's settings in its class profile, the alias-to-host map in the gateway's
  config, a setting's reasoning in ai-hosting's documents.
- `architecture/principles/model-cards.md`: a row's sampling, reasoning, context, and prompt
  forms come from its model's card.
- `architecture/principles/tool-call-reliability.md`: a row serves its checkpoint's own chat
  template, so a `--chat-template` in its flags is an override, and its reason names the breakage.
- `architecture/principles/tool-beside-library.md`: each `hosting-<group>-<verb>` command is a
  thin consumer of the suite's shell library, which holds the logic the commands share.
- `architecture/principles/repository-topology.md`: ai-hosting stands outside the five tiers,
  beside the harness repositories, and is the one hosting repository on each workstation.
- The remaining principle pages govern Go modules, libraries, and services, and ai-hosting holds
  none.
- `architecture/principles/development-secrets.md`: development-time secrets live in the
  repository's own committed, age-encrypted `fnox.toml`, each with a description.
- No tailnet identifier (MagicDNS suffix or address) is committed; hosts go by short name
  (`standards-lab/context/ai-hosting.md`).
