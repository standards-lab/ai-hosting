# ai-hosting standards

The judgement calls the standards-reviewer applies to ai-hosting, beyond what `mise run check`
enforces: each one line, with a pointer to the architecture page that applies. They come from
ai-hosting's design review, `context/design.md`, and apply to its shell, TOML, compose files, and
Markdown; ai-hosting holds no Go, so Go Elemental's pages don't apply.

- `architecture/principles/comments.md`: every comment is one of the five kinds, in scripts and in
  every configuration file (TOML, YAML, `.gitignore`), not just source; a script, profile,
  Dockerfile, or compose file points at the document or principle that governs it with a one-line
  reference instead of restating its reasoning, which lives in ai-hosting's documents.
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
- `architecture/principles/tool-beside-library.md`: each `hosting-<group>-<verb>` command is a
  thin consumer of the suite's shell library, which holds the logic the commands share.
- `architecture/principles/repository-topology.md`: ai-hosting stands outside the five tiers,
  beside the harness repositories, and is the one hosting repository on each workstation.
- `architecture/principles/`'s `resolution.md`, `downward-dependencies.md`, `service-tiers.md`,
  `independent-releases.md`, `composition-root.md`, and `composition-terms.md` don't apply: they
  govern Go modules, libraries, and services, and ai-hosting holds none.
- Development-time secrets reach ai-hosting only through the workspace's fnox store, never a
  committed file; a published development credential is not a secret and stays committed (the
  architecture page arrives with the `secrets` task).
- No tailnet identifier (MagicDNS suffix or address) is committed; hosts go by short name
  (`standards-lab/context/ai-hosting.md`).
