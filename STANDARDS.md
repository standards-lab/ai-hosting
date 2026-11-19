# ai-hosting standards

The judgement calls the standards-reviewer applies to ai-hosting, beyond what `mise run check`
enforces: each one line, with a pointer to the architecture page that applies. The design task
writes them; until then these apply.

- `architecture/principles/minimal-footprint.md`: a host holds only what its rows serve, and
  ai-hosting is the one hosting repository on it.
- `architecture/principles/rolling-currency.md`: every pin, image, and tool is current or held
  with a recorded reason.
- `architecture/principles/validation-first.md`: a command refuses a bad input or an unknown host
  class before it changes the host.
- `architecture/principles/comments.md`: the comments in scripts.
- No tailnet identifier (MagicDNS suffix or address) is committed; hosts go by short name
  (`standards-lab/context/ai-hosting.md`).
