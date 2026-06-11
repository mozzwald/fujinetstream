# Netstream Handler Implementations

This repository carries two assembler implementations of the same Netstream
handler API:

- `handler/mads/` builds a standalone `NSENGINE.OBX` with MADS. The Atari
  examples load that object at `HANDLER_BASE` and call it through the cc65
  jump-table wrappers in `examples/common/netstream_api.s`.
- `handler/ca65/` builds with CA65 through `cl65`. The Atari examples define
  `NETSTREAM_LINKED_HANDLER` and link the handler directly into `autorun.sys`.

Keep behavior changes in both implementations unless the change is explicitly
assembler-specific. The public API expected by the examples is the `ns_*`
function set declared in the Atari C sources.
