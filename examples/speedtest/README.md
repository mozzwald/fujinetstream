# NETStream Speed Test

This example measures FujiNet-to-Atari NETStream throughput and validation
errors for paced and unpaced firmware modes.

The required comparison matrix is:

| Transport | Flags | Mode |
|---|---:|---|
| UDP | `0x02` | paced, REGISTER |
| UDP | `0x42` | unpaced, REGISTER |
| TCP | `0x03` | paced, REGISTER |
| TCP | `0x43` | unpaced, REGISTER |

## Build

From the repository root:

```sh
make speedtest
```

This builds:

- `build/netstream_speed_server`
- `build/mads/atari_netstream_speedtest.atr`
- `build/ca65/atari_netstream_speedtest.atr`

The Atari handler input buffer size follows the top-level
`NETSTREAM_INPUT_BUFSIZE` setting.

The Atari client auto-starts at boot. Select the transport and pacing mode at
build time:

```sh
make -B ca65-speedtest SPEEDTEST_TCP=0 SPEEDTEST_UNPACED=0  # UDP paced
make -B ca65-speedtest SPEEDTEST_TCP=0 SPEEDTEST_UNPACED=1  # UDP unpaced
make -B ca65-speedtest SPEEDTEST_TCP=1 SPEEDTEST_UNPACED=0  # TCP paced
make -B ca65-speedtest SPEEDTEST_TCP=1 SPEEDTEST_UNPACED=1  # TCP unpaced
```

Use the same variables with `mads-speedtest` when rebuilding the MADS disk.
The default host is `127.0.0.2` and the default port is `9000`; override them
with `SPEEDTEST_HOST=<host>` and `SPEEDTEST_PORT=<port>`. For FujiNet-PC
same-host UDP tests, bind the server to `127.0.0.2`. This keeps server replies
to FujiNet's `127.0.0.1` source port from being delivered back to the server's
own socket.

## Server

UDP:

```sh
build/netstream_speed_server --udp --host 127.0.0.2 --port 9000
```

TCP:

```sh
build/netstream_speed_server --tcp --port 9000
```

Useful options:

```text
--host <bind address>       default 0.0.0.0
--bytes <payload bytes>     default 16384
--block-size <payload size> default 64, max 240
--delay-us <microseconds>   default 0
--repeat <count>            default 1
```

For UDP, `--host` is the bind address. The server learns the destination peer
from FujiNet's `REGISTER` packet.

## Protocol

The Atari client always enables `REGISTER`. After `NS_BeginStream`, it sends an
ASCII line identifying the selected test:

```text
SPEEDTEST MODE transport=UDP mode=UNPACED flags=$42 bytes=16384 block_size=64
```

The server sends framed binary blocks:

```text
byte 0:  $A5
byte 1:  block_lo
byte 2:  block_hi
byte 3:  payload_len
bytes 4..N: payload bytes
last byte: 8-bit additive checksum of all prior frame bytes
```

Payload byte `i` is `(block_number + i) & 0xFF`.

## Result

The Atari client prints a parsable result block:

```text
NETSTREAM SPEED RESULT
transport=UDP
mode=UNPACED
flags=$42
final_flags=$52
bufsize=1024
payload_bytes_expected=16384
payload_bytes_received=16384
wire_bytes_received=17664
frames=312
bytes_per_sec=3150
bits_per_sec=31500
sync_errors=0
checksum_errors=0
sequence_errors=0
rx_empty_waits=123
status=$00
END RESULT
```

Stage 3 MOTOR/PROCEED flow control must not be implemented until these results
are reviewed.
