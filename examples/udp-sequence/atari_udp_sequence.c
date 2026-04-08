#include <conio.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define NETSTREAM_FLAG_REGISTER 0x02
#define NETSTREAM_FLAG_TX_EXT 0x04
#define NETSTREAM_FLAG_RX_INT 0x00
#define NETSTREAM_FLAG_UDP_SEQ 0x20
#define NETSTREAM_FLAGS (NETSTREAM_FLAG_REGISTER | NETSTREAM_FLAG_TX_EXT | NETSTREAM_FLAG_RX_INT | NETSTREAM_FLAG_UDP_SEQ)
#define NETSTREAM_BAUD 31250
#define NETSTREAM_PORT 9000

#define SCREEN_COLS 40
#define SCREEN_ROWS 24
#define SCREEN_BYTES (SCREEN_COLS * SCREEN_ROWS)
#define PACKET_DATA 32
#define TX_CHUNK_SIZE 60
#define TX_CHUNK_DELAY_SPIN 50

void __fastcall__ ns_begin_stream(void);
void __fastcall__ ns_end_stream(void);
unsigned char __fastcall__ ns_send_byte(unsigned char b);
int __fastcall__ ns_recv_byte(void);
unsigned int __fastcall__ ns_bytes_avail(void);
unsigned char __fastcall__ ns_get_final_flags(void);
unsigned char __fastcall__ ns_init_netstream(const char* host, unsigned char flags, unsigned int nominal_baud, unsigned int port_swapped);

static unsigned int swap16(unsigned int value) {
    return (unsigned int)(((value << 8) & 0xFF00) | ((value >> 8) & 0x00FF));
}

static char host_buf[32];
static unsigned int host_port = NETSTREAM_PORT;
static unsigned char screen_buf[SCREEN_BYTES];

static void prompt_host(void) {
    unsigned char ch;
    unsigned char len = 0;

    clrscr();
    gotoxy(0, 0);
    cprintf("UDP Sequence Test\r\n");
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
        if (len >= (sizeof(host_buf) - 1)) {
            continue;
        }
        if (ch < 0x20) {
            continue;
        }
        host_buf[len++] = (char)ch;
        host_buf[len] = '\0';
        cputc((char)ch);
    }

    if (len == 0) {
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
        if (len >= 5) {
            continue;
        }
        if (ch < '0' || ch > '9') {
            continue;
        }
        port_buf[len++] = (char)ch;
        port_buf[len] = '\0';
        cputc((char)ch);
    }

    if (len == 0) {
        host_port = NETSTREAM_PORT;
    } else {
        host_port = (unsigned int)atoi(port_buf);
        if (host_port == 0) {
            host_port = NETSTREAM_PORT;
        }
    }
}

static unsigned char recv_screen(void) {
    unsigned int received = 0;

    while (received < SCREEN_BYTES) {
        unsigned int avail = ns_bytes_avail();
        while (avail && received < SCREEN_BYTES) {
            int rc = ns_recv_byte();
            if (rc >= 0) {
                unsigned char ch = (unsigned char)rc;
                screen_buf[received] = ch;
                ++received;
            }
            if (avail) {
                --avail;
            }
        }
    }

    return 1;
}

static void send_back(void) {
    unsigned int sent = 0;
    unsigned long spins = 0;
    char status[24];
    unsigned long delay;
    unsigned int chunk_sent = 0;
    unsigned int full_count = 0;

    while (sent < SCREEN_BYTES) {
        if (ns_send_byte(screen_buf[sent]) == 0) {
            ++sent;
            ++chunk_sent;
            if ((sent % SCREEN_COLS) == 0) {
                unsigned char i;
                sprintf(status, "TX %u/%u F%u", sent, (unsigned)SCREEN_BYTES, full_count);
                gotoxy(0, SCREEN_ROWS - 1);
                for (i = 0; status[i] != '\0'; ++i) {
                    cputc((unsigned char)(status[i] | 0x80));
                }
            }
            if (chunk_sent >= TX_CHUNK_SIZE || sent == SCREEN_BYTES) {
                for (delay = 0; delay < TX_CHUNK_DELAY_SPIN; ++delay) {
                }
                chunk_sent = 0;
            }
            spins = 0;
        } else {
            ++full_count;
            if (++spins > 200000UL) {
                gotoxy(0, SCREEN_ROWS - 1);
                cprintf("TX STALL %u/%u", sent, (unsigned)SCREEN_BYTES);
                spins = 0;
            }
        }
    }
}

static void render_screen(void) {
    unsigned int i;
    for (i = 0; i < SCREEN_BYTES; ++i) {
        unsigned char col = (unsigned char)(i % SCREEN_COLS);
        unsigned char row = (unsigned char)(i / SCREEN_COLS);
        cputcxy(col, row, screen_buf[i]);
    }
}

static void wait_for_first_byte(void) {
    while (ns_bytes_avail() == 0) {
    }
}

static void run_cycle(void) {
    wait_for_first_byte();
    recv_screen();
    clrscr();
    render_screen();
    gotoxy(0, SCREEN_ROWS - 1);
    cprintf("RX DONE");
    send_back();
}

int main(void) {
    prompt_host();
    prompt_port();

    clrscr();
    if (ns_init_netstream(host_buf, NETSTREAM_FLAGS, NETSTREAM_BAUD, swap16(host_port)) != 0) {
        cprintf("Init failed\r\n");
        return 1;
    }

    (void)ns_get_final_flags();
    ns_begin_stream();

    while (1) {
        run_cycle();
    }

    ns_end_stream();

    return 0;
}
