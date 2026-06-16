# NETStream 20 Hz Pseudo Game

This example tests whether a small real-time game protocol can work over the
current NETStream byte-stream behavior without firmware or handler protocol
changes.

The Atari client sends joystick/fire input frames at roughly 20 Hz. The Linux
server is authoritative for the player, bullet, and AI positions and sends
compact, complete state snapshots at 20 Hz. Old state is never replayed or
queued.

## Build

From the repository root:

```sh
make pseudogame
```

This builds:

- `build/netstream_pseudo_game_server`
- `build/mads/atari_pseudo_game_20hz.atr`
- `build/ca65/atari_pseudo_game_20hz.atr`

The Atari client auto-starts. Defaults:

```text
GAME_HOST=127.0.0.2
GAME_PORT=9000
GAME_UNPACED=0
```

Override at build time:

```sh
make -B ca65-pseudogame GAME_HOST=192.168.1.100 GAME_PORT=9000
make -B ca65-pseudogame GAME_UNPACED=1
```

## Run

For FujiNet-PC same-host UDP testing, bind the server to the address used by
the Atari client:

```sh
build/netstream_pseudo_game_server --bind 127.0.0.2 --port 9000 --tick-hz 20 --verbose
```

Then boot the ATR. The server waits for FujiNet's UDP `REGISTER` packet before
sending snapshots.

## Protocol

All messages are framed inside the NETStream byte stream:

```text
$A5 $5A type seq_lo seq_hi len payload... checksum
```

The checksum is an 8-bit two's-complement checksum; the sum of all bytes
including checksum must be zero.

Required messages:

```text
$01 CLIENT_INPUT
$81 SERVER_SNAPSHOT
```

Snapshots are self-contained current state. They are not deltas.

The player can have one bullet on screen at a time. Hold fire and press a
direction to shoot in that direction; while fire is held, directional input
aims instead of moving. Release fire to move freely again. The bullet travels up
to seven tiles, disappears at a wall, and destroys the AI on contact. The AI
respawns at a random position after about three seconds. If the AI catches the
player, the player is removed and respawns at a random position after the same
delay.

## Notes

- Baseline mode is paced UDP with `REGISTER`, flags `0x02`.
- Optional unpaced comparison uses flags `0x42`.
- Current NETStream does not preserve UDP packet boundaries.
- The app protocol owns framing, resync, sequence checks, and checksums.
- `status=$10` on the Atari display means confirmed handler RX overflow.
