# Netstream Handler Implementations

This repository carries two assembler implementations of the same Netstream
handler API:

- `handler/mads/` builds a standalone `NSENGINE.OBX` with MADS. The Atari
  examples load that object at `HANDLER_BASE` and call it through the cc65
  jump-table wrappers in `examples/common/netstream_api.s`.
- `handler/ca65/` builds a relocatable object with CA65. The Atari examples
  define `NETSTREAM_LINKED_HANDLER` and link that object directly into
  `autorun.sys`; no `NSENGINE.OBX` loader is used for this syntax.

Keep behavior changes in both implementations unless the change is explicitly
assembler-specific. The public API expected by the examples is the `ns_*`
function set declared in the Atari C sources.

## Building

The top-level Makefile can build both handler syntaxes together or each one
independently:

```
make handlers
make mads-handler
make ca65-handler
```

`make mads` builds the MADS handler plus the MADS ATR examples. `make ca65`
builds the CA65 handler object plus the CA65-linked ATR examples.

Outputs:
- `build/mads/NSENGINE.OBX`
- `build/ca65/netstream.o`

## Input Buffer Size

Both sources now allow the embedding build to provide `INPUT_BUFSIZE`.
If no value is supplied, each source defaults to 128 bytes. The top-level
Makefile sets `NETSTREAM_INPUT_BUFSIZE ?= 1024` for the examples because the
test programs can receive bursts larger than the conservative default.

Examples:

```
make mads-handler NETSTREAM_INPUT_BUFSIZE=128
make ca65-handler NETSTREAM_INPUT_BUFSIZE=1024
```

For MADS, the Makefile passes `-d:INPUT_BUFSIZE=...`. For CA65, it passes
`-D INPUT_BUFSIZE=...` when assembling `handler/ca65/netstream.s`.

## Send Return Convention

`NS_SendByte` has the same public behavior in both syntaxes:

- success: `A=0`, carry clear
- output ring full: `A=1`, carry set

The implementations restore the saved processor flags before setting this
public return status, so callers can reliably use either `A` or carry.
