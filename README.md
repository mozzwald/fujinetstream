# fujinet-atari-netstream
Atari direct POKEY serial to network raw data streaming with FujiNet.

This repo contains:
- A stripped-down Altirra 850 handler built with either MADS (`handler/mads/`) or CA65 (`handler/ca65/`) for FujiNet NETStream
- An Atari chat example (cc65) that can use either handler build
- A Linux UDP chat client to talk to the Atari
- A UDP sequencing test (Atari client + Linux server)
- Build tools to assemble ATR disk images with `autorun.sys`, `NSENGINE.OBX`, and DOS files

## Build

Requirements:
- `mads` (Mad Assembler)
- `cc65` toolchain (set `CC65_HOME` path in Makefile if needed)
- `dir2atr` (used to build the ATR, in your environment path or edit Makefile with direct path)
- `cc` (for the Linux chat example)

Build everything:
```
make clean && make
```

Build only one Atari handler variant:
```
make mads
make ca65
```

Outputs:
- `build/mads/NSENGINE.OBX` (MADS handler binary)
- `build/linux_netstream_chat` (Linux chat client)
- `build/linux_udp_sequence_server` (Linux UDP sequencing server)
- `build/mads/atari_netstream_chat.atr` and `build/mads/atari_udp_sequence.atr` (MADS handler ATR images)
- `build/ca65/atari_netstream_chat.atr` and `build/ca65/atari_udp_sequence.atr` (CA65-linked handler ATR images)

## Running the chat examples

1) Start the Linux chat first:
```
build/linux_netstream_chat --port 9000
```
It waits for a `REGISTER` packet, then prints “Client Connected”.

2) Boot either Atari ATR variant and enter the host when prompted.
The Atari chat asks for the host/IP, port and then connects to the Linux client. Both clients default to port 9000 if none given.

Atari chat status line fields:
- `Ver` = handler version
- `Base` = handler base address
- `F` = final flags
- `3` = AUDF3
- `4` = AUDF4
- `P` = PACTL, `AV` = bytes available, `TX`/`RX` = local counters

## Running the UDP sequence test

1) Start the Linux server:
```
build/linux_udp_sequence_server --port 9000 [--duplicates] [--reorder]
```

- `--duplicates`: makes the server randomly send duplicate packets to test firmware drop packet feature
- `--reorder`: randomly picks 2 packets to send out of order each run to test firmware reordering (ie, packet 24 then packet 23)

2) Boot either `build/mads/atari_udp_sequence.atr` or `build/ca65/atari_udp_sequence.atr` and enter host/port when prompted.
It will fill the 40x24 screen with Lorem Ipsum, then send the data back to the server.

## Docs

More details live in `docs/`:
- `docs/netstream_api.md` - handler API and calling conventions
- `docs/POKEY-Divisors-Chart.md` - baud/divisor reference
