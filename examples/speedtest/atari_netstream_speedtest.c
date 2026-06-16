#include <conio.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef NETSTREAM_LINKED_HANDLER
#define BASEADDR 0x2800
#define ENGINE_PATH "D:NSENGINE.OBX"
#endif

#define NETSTREAM_FLAG_TCP 0x01
#define NETSTREAM_FLAG_REGISTER 0x02
#define NETSTREAM_FLAG_UNPACED 0x40

#define NETSTREAM_BAUD ((unsigned int)57600UL)
#define NETSTREAM_PORT 9000
#ifndef NETSTREAM_DEFAULT_HOST
#define NETSTREAM_DEFAULT_HOST "127.0.0.2"
#endif
#ifndef NETSTREAM_DEFAULT_PORT
#define NETSTREAM_DEFAULT_PORT NETSTREAM_PORT
#endif
#ifndef NETSTREAM_DEFAULT_TCP
#define NETSTREAM_DEFAULT_TCP 0
#endif
#ifndef NETSTREAM_DEFAULT_UNPACED
#define NETSTREAM_DEFAULT_UNPACED 0
#endif
#ifndef NETSTREAM_AUTOSTART
#define NETSTREAM_AUTOSTART 1
#endif
#define NETSTREAM_HOST_MAX 31
#define NETSTREAM_TEST_BYTES 16384UL
#define NETSTREAM_BLOCK_SIZE 64
#define NETSTREAM_FRAME_SYNC 0xA5
#define NETSTREAM_MAX_PAYLOAD 240
#define NETSTREAM_TIMEOUT_FRAMES 300U
#define RTCLOK ((volatile unsigned char*)0x0012)

void __fastcall__ ns_begin_stream(void);
void __fastcall__ ns_end_stream(void);
unsigned char __fastcall__ ns_send_byte(unsigned char b);
int __fastcall__ ns_recv_byte(void);
unsigned int __fastcall__ ns_bytes_avail(void);
unsigned char __fastcall__ ns_get_status(void);
unsigned char __fastcall__ ns_get_final_flags(void);
unsigned char __fastcall__ ns_get_final_audf3(void);
unsigned char __fastcall__ ns_get_final_audf4(void);
unsigned char __fastcall__ ns_init_netstream(const char* host, unsigned char flags, unsigned int nominal_baud, unsigned int port_swapped);

static char host_buf[NETSTREAM_HOST_MAX + 1];
static unsigned int host_port = NETSTREAM_PORT;
static unsigned char transport_tcp;
static unsigned char unpaced;
static unsigned char flags_requested;
static unsigned char final_flags;
static unsigned char final_audf3;
static unsigned char final_audf4;

static unsigned long payload_expected = NETSTREAM_TEST_BYTES;
static unsigned long payload_received;
static unsigned long wire_received;
static unsigned long rx_empty_waits;
static unsigned int frames_elapsed;
static unsigned int sync_errors;
static unsigned int checksum_errors;
static unsigned int sequence_errors;
static unsigned char status_accum;

#ifndef NETSTREAM_LINKED_HANDLER
static unsigned char load_engine(void) {
    FILE* f = fopen(ENGINE_PATH, "rb");
    unsigned char hdr[6];
    unsigned char* dst = (unsigned char*)BASEADDR;
    size_t n;

    if (!f) {
        return 0;
    }

    n = fread(hdr, 1, 2, f);
    if (n != 2) {
        fclose(f);
        return 0;
    }

    if (hdr[0] == 0xFF && hdr[1] == 0xFF) {
        unsigned int start, end, len;

        if (fread(hdr + 2, 1, 4, f) != 4) {
            fclose(f);
            return 0;
        }

        start = (unsigned int)hdr[2] | ((unsigned int)hdr[3] << 8);
        end = (unsigned int)hdr[4] | ((unsigned int)hdr[5] << 8);
        if (start != BASEADDR || end < start) {
            fclose(f);
            return 0;
        }

        len = end - start + 1;
        if (fread(dst, 1, len, f) != len) {
            fclose(f);
            return 0;
        }
    } else {
        unsigned int i = 0;
        dst[i++] = hdr[0];
        dst[i++] = hdr[1];
        while ((n = fread(dst + i, 1, 128, f)) > 0) {
            i += (unsigned int)n;
        }
    }

    fclose(f);
    return 1;
}
#endif

static unsigned int swap16(unsigned int value) {
    return (unsigned int)(((value << 8) & 0xFF00) | ((value >> 8) & 0x00FF));
}

static unsigned long read_rtclok(void) {
    unsigned char hi1;
    unsigned char mid;
    unsigned char lo;
    unsigned char hi2;

    do {
        hi1 = RTCLOK[0];
        mid = RTCLOK[1];
        lo = RTCLOK[2];
        hi2 = RTCLOK[0];
    } while (hi1 != hi2);

    return ((unsigned long)hi1 << 16) | ((unsigned long)mid << 8) | lo;
}

static void set_test_options(void) {
    strncpy(host_buf, NETSTREAM_DEFAULT_HOST, NETSTREAM_HOST_MAX);
    host_buf[NETSTREAM_HOST_MAX] = '\0';
    host_port = NETSTREAM_DEFAULT_PORT;
    transport_tcp = NETSTREAM_DEFAULT_TCP ? 1 : 0;
    unpaced = NETSTREAM_DEFAULT_UNPACED ? 1 : 0;

    flags_requested = NETSTREAM_FLAG_REGISTER;
    if (transport_tcp) {
        flags_requested |= NETSTREAM_FLAG_TCP;
    }
    if (unpaced) {
        flags_requested |= NETSTREAM_FLAG_UNPACED;
    }
}

#if !NETSTREAM_AUTOSTART
static void prompt_host(void) {
    unsigned char ch;
    unsigned char len = 0;

    clrscr();
    cprintf("NETStream Speed Test\r\n");
    cprintf("Host: ");
    host_buf[0] = '\0';

    while (1) {
        ch = (unsigned char)cgetc();
        if (ch == 0x9B || ch == '\r' || ch == '\n') {
            break;
        }
        if (ch == 0x7E || ch == 0x08) {
            if (len) {
                --len;
                host_buf[len] = '\0';
                gotoxy(6 + len, 1);
                cputc(' ');
                gotoxy(6 + len, 1);
            }
            continue;
        }
        if (len >= NETSTREAM_HOST_MAX || ch < 0x20) {
            continue;
        }
        host_buf[len++] = (char)ch;
        host_buf[len] = '\0';
        cputc((char)ch);
    }

    if (!len) {
        strcpy(host_buf, "localhost");
    }
}

static void prompt_port(void) {
    unsigned char ch;
    unsigned char len = 0;
    char port_buf[6];

    gotoxy(0, 2);
    cprintf("Port: ");
    memset(port_buf, 0, sizeof(port_buf));

    while (1) {
        ch = (unsigned char)cgetc();
        if (ch == 0x9B || ch == '\r' || ch == '\n') {
            break;
        }
        if (ch == 0x7E || ch == 0x08) {
            if (len) {
                --len;
                port_buf[len] = '\0';
                gotoxy(6 + len, 2);
                cputc(' ');
                gotoxy(6 + len, 2);
            }
            continue;
        }
        if (len >= 5 || ch < '0' || ch > '9') {
            continue;
        }
        port_buf[len++] = (char)ch;
        port_buf[len] = '\0';
        cputc((char)ch);
    }

    if (len) {
        host_port = (unsigned int)atoi(port_buf);
        if (!host_port) {
            host_port = NETSTREAM_PORT;
        }
    }
}

static void select_mode(void) {
    unsigned char ch;

    clrscr();
    cprintf("NETStream Speed Test\r\n\r\n");
    cprintf("1 UDP paced\r\n");
    cprintf("2 UDP unpaced\r\n");
    cprintf("3 TCP paced\r\n");
    cprintf("4 TCP unpaced\r\n\r\n");
    cprintf("Select: ");

    while (1) {
        ch = (unsigned char)cgetc();
        if (ch >= '1' && ch <= '4') {
            cputc((char)ch);
            break;
        }
    }

    transport_tcp = (ch == '3' || ch == '4');
    unpaced = (ch == '2' || ch == '4');
    flags_requested = NETSTREAM_FLAG_REGISTER;
    if (transport_tcp) {
        flags_requested |= NETSTREAM_FLAG_TCP;
    }
    if (unpaced) {
        flags_requested |= NETSTREAM_FLAG_UNPACED;
    }
}
#endif

static unsigned char send_byte_wait(unsigned char b) {
    unsigned long spins = 0;

    while (ns_send_byte(b) != 0) {
        if (++spins > 200000UL) {
            return 0;
        }
    }
    return 1;
}

static unsigned char send_text(const char* s) {
    while (*s) {
        if (!send_byte_wait((unsigned char)*s++)) {
            return 0;
        }
    }
    return send_byte_wait(0x9B);
}

static unsigned char announce_mode(void) {
    char line[96];

    sprintf(line,
            "SPEEDTEST MODE transport=%s mode=%s flags=$%02X bytes=%lu block_size=%u",
            transport_tcp ? "TCP" : "UDP",
            unpaced ? "UNPACED" : "PACED",
            flags_requested,
            payload_expected,
            (unsigned)NETSTREAM_BLOCK_SIZE);
    return send_text(line);
}

static unsigned char expected_payload_byte(unsigned int block, unsigned char index) {
    return (unsigned char)((block + index) & 0xFF);
}

static void run_receive_test(void) {
    unsigned char state = 0;
    unsigned int block = 0;
    unsigned int expected_block = 0;
    unsigned char payload_len = 0;
    unsigned char payload_index = 0;
    unsigned char checksum = 0;
    unsigned long start_frame;
    unsigned long last_byte_frame;
    unsigned long now_frame;

    payload_received = 0;
    wire_received = 0;
    rx_empty_waits = 0;
    sync_errors = 0;
    checksum_errors = 0;
    sequence_errors = 0;
    status_accum = 0;

    start_frame = read_rtclok();
    last_byte_frame = start_frame;

    while (payload_received < payload_expected) {
        int value;
        unsigned char b;

        if (ns_bytes_avail() == 0) {
            ++rx_empty_waits;
            status_accum |= ns_get_status();
            now_frame = read_rtclok();
            if ((unsigned int)(now_frame - last_byte_frame) > NETSTREAM_TIMEOUT_FRAMES) {
                break;
            }
            continue;
        }

        value = ns_recv_byte();
        if (value < 0) {
            ++rx_empty_waits;
            continue;
        }

        b = (unsigned char)value;
        ++wire_received;
        last_byte_frame = read_rtclok();

        switch (state) {
        case 0:
            if (b == NETSTREAM_FRAME_SYNC) {
                checksum = b;
                state = 1;
            } else {
                ++sync_errors;
            }
            break;
        case 1:
            block = b;
            checksum = (unsigned char)(checksum + b);
            state = 2;
            break;
        case 2:
            block |= ((unsigned int)b << 8);
            checksum = (unsigned char)(checksum + b);
            state = 3;
            break;
        case 3:
            payload_len = b;
            checksum = (unsigned char)(checksum + b);
            payload_index = 0;
            if (payload_len == 0 || payload_len > NETSTREAM_MAX_PAYLOAD) {
                ++sync_errors;
                state = 0;
            } else {
                if (block != expected_block) {
                    ++sequence_errors;
                    expected_block = (unsigned int)(block + 1);
                } else {
                    ++expected_block;
                }
                state = 4;
            }
            break;
        case 4:
            if (b != expected_payload_byte(block, payload_index)) {
                ++sequence_errors;
            }
            checksum = (unsigned char)(checksum + b);
            ++payload_received;
            ++payload_index;
            if (payload_index >= payload_len) {
                state = 5;
            }
            break;
        case 5:
            if (b != checksum) {
                ++checksum_errors;
            }
            state = 0;
            break;
        }
    }

    now_frame = read_rtclok();
    frames_elapsed = (unsigned int)(now_frame - start_frame);
    if (frames_elapsed == 0) {
        frames_elapsed = 1;
    }
}

static void print_result(void) {
    unsigned long bytes_per_sec = (payload_received * 60UL) / frames_elapsed;
    unsigned long bits_per_sec = bytes_per_sec * 10UL;

    clrscr();
    cprintf("NETSTREAM SPEED RESULT\r\n");
    cprintf("transport=%s\r\n", transport_tcp ? "TCP" : "UDP");
    cprintf("mode=%s\r\n", unpaced ? "UNPACED" : "PACED");
    cprintf("flags=$%02X\r\n", flags_requested);
    cprintf("final_flags=$%02X\r\n", final_flags);
    cprintf("bufsize=%u\r\n", (unsigned)INPUT_BUFSIZE);
    cprintf("payload_bytes_expected=%lu\r\n", payload_expected);
    cprintf("payload_bytes_received=%lu\r\n", payload_received);
    cprintf("wire_bytes_received=%lu\r\n", wire_received);
    cprintf("frames=%u\r\n", frames_elapsed);
    cprintf("bytes_per_sec=%lu\r\n", bytes_per_sec);
    cprintf("bits_per_sec=%lu\r\n", bits_per_sec);
    cprintf("sync_errors=%u\r\n", sync_errors);
    cprintf("checksum_errors=%u\r\n", checksum_errors);
    cprintf("sequence_errors=%u\r\n", sequence_errors);
    cprintf("rx_empty_waits=%lu\r\n", rx_empty_waits);
    cprintf("status=$%02X\r\n", status_accum);
    cprintf("END RESULT\r\n");
}

int main(void) {
    clrscr();

#ifndef NETSTREAM_LINKED_HANDLER
    if (!load_engine()) {
        cprintf("Failed to load NSENGINE.OBX\r\n");
        return 1;
    }
#endif

#if NETSTREAM_AUTOSTART
    set_test_options();
#else
    prompt_host();
    prompt_port();
    select_mode();
#endif

    clrscr();
    cprintf("Init %s %s flags=$%02X\r\n",
            transport_tcp ? "TCP" : "UDP",
            unpaced ? "UNPACED" : "PACED",
            flags_requested);
    cprintf("%s:%u\r\n", host_buf, host_port);

    if (ns_init_netstream(host_buf, flags_requested, NETSTREAM_BAUD, swap16(host_port)) != 0) {
        cprintf("Init failed\r\n");
        return 1;
    }

    final_flags = ns_get_final_flags();
    final_audf3 = ns_get_final_audf3();
    final_audf4 = ns_get_final_audf4();

    ns_begin_stream();

    cprintf("Final=$%02X AUDF3=%u AUDF4=%u\r\n", final_flags, final_audf3, final_audf4);
    cprintf("Announcing mode...\r\n");
    if (!announce_mode()) {
        cprintf("Announce failed\r\n");
        ns_end_stream();
        return 1;
    }

    cprintf("Receiving %lu bytes...\r\n", payload_expected);
    run_receive_test();
    ns_end_stream();
    print_result();

    return 0;
}
