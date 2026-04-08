#include <conio.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define NETSTREAM_FLAGS 0x06
#define NETSTREAM_BAUD 57600
#define NETSTREAM_PORT 9000
#define PACTL (*(volatile unsigned char*)0xD302)
#define AUDF3 (*(volatile unsigned char*)0xD204)
#define AUDF4 (*(volatile unsigned char*)0xD206)

#define SCREEN_COLS 40
#define SCREEN_ROWS 24

#define TITLE_ROW 0
#define VER_ROW (TITLE_ROW + 1)
#define HOST_ROW VER_ROW
#define STAT_ROW (HOST_ROW + 1)
#define PROMPT_ROW (STAT_ROW + 1)
#define PROMPT_LINES 2
#define DIVIDER_ROW (PROMPT_ROW + PROMPT_LINES)
#define RX_START_ROW (DIVIDER_ROW + 1)

#define PROMPT_MAX 78
#define NETSTREAM_HOST_MAX 31

void __fastcall__ ns_begin_stream(void);
void __fastcall__ ns_end_stream(void);
unsigned char __fastcall__ ns_get_version(void);
unsigned int __fastcall__ ns_get_base(void);
unsigned char __fastcall__ ns_send_byte(unsigned char b);
int __fastcall__ ns_recv_byte(void);
unsigned int __fastcall__ ns_bytes_avail(void);
unsigned char __fastcall__ ns_get_final_flags(void);
unsigned char __fastcall__ ns_get_final_audf3(void);
unsigned char __fastcall__ ns_get_final_audf4(void);
unsigned char __fastcall__ ns_init_netstream(const char* host, unsigned char flags, unsigned int nominal_baud, unsigned int port_swapped);

static unsigned int swap16(unsigned int value) {
    return (unsigned int)(((value << 8) & 0xFF00) | ((value >> 8) & 0x00FF));
}

static char input_buf[PROMPT_MAX + 1];
static unsigned char input_len;
static unsigned char input_cursor_x = 2;
static unsigned char input_cursor_y = PROMPT_ROW;

static char host_buf[NETSTREAM_HOST_MAX + 1];
static unsigned char host_len;
static unsigned int host_port = NETSTREAM_PORT;

static unsigned char rx_x = 0;
static unsigned char rx_y = RX_START_ROW;

static unsigned long tx_count;
static unsigned long rx_count;

static void prompt_host(void) {
    unsigned char ch;

    gotoxy(0, TITLE_ROW);
    cprintf("NETStream Chat Test");
    gotoxy(0, HOST_ROW);
    cprintf("Host: ");
    host_len = 0;
    host_buf[0] = '\0';

    while (1) {
        ch = (unsigned char)cgetc();
        if (ch == 0x9B || ch == '\r' || ch == '\n') {
            break;
        }
        if (ch == 0x7E || ch == 0x08) {
            if (host_len) {
                --host_len;
                host_buf[host_len] = '\0';
                gotoxy(6 + host_len, HOST_ROW);
                cputc(' ');
                gotoxy(6 + host_len, HOST_ROW);
            }
            continue;
        }
        if (host_len >= NETSTREAM_HOST_MAX) {
            continue;
        }
        if (ch < 0x20) {
            continue;
        }
        host_buf[host_len++] = (char)ch;
        host_buf[host_len] = '\0';
        cputc((char)ch);
    }

    if (!host_len) {
        strcpy(host_buf, "localhost");
    }
}

static void prompt_port(void) {
    unsigned char ch;
    unsigned char len = 0;
    char port_buf[6];

    gotoxy(0, HOST_ROW + 1);
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
                gotoxy(6 + len, HOST_ROW + 1);
                cputc(' ');
                gotoxy(6 + len, HOST_ROW + 1);
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

static void render_prompt(void) {
    unsigned char i = 0;
    unsigned char max_first = (unsigned char)(SCREEN_COLS - 2);

    gotoxy(0, PROMPT_ROW);
    cprintf("> ");
    for (i = 0; i < max_first; ++i) {
        if (i < input_len) {
            cputc(input_buf[i]);
        } else {
            cputc(' ');
        }
    }

    gotoxy(0, PROMPT_ROW + 1);
    for (i = 0; i < SCREEN_COLS; ++i) {
        unsigned char idx = (unsigned char)(max_first + i);
        if (idx < input_len) {
            cputc(input_buf[idx]);
        } else {
            cputc(' ');
        }
    }

    if (input_len < max_first) {
        input_cursor_x = (unsigned char)(2 + input_len);
        input_cursor_y = PROMPT_ROW;
    } else {
        unsigned char second_pos = (unsigned char)(input_len - max_first);
        if (second_pos >= SCREEN_COLS) {
            second_pos = (unsigned char)(SCREEN_COLS - 1);
        }
        input_cursor_x = second_pos;
        input_cursor_y = (unsigned char)(PROMPT_ROW + 1);
    }
}

static void draw_ui(void) {
    unsigned char i = 0;

    clrscr();
    gotoxy(0, TITLE_ROW);
    cprintf("NETStream Chat Test");
    gotoxy(0, VER_ROW);
    cprintf("Ver:%02X Base:%04X F:%02X 3:%02X 4:%02X",
            ns_get_version(), ns_get_base(),
            ns_get_final_flags(), ns_get_final_audf3(), ns_get_final_audf4());
    gotoxy(0, STAT_ROW);
    cprintf("P:$00 AV:00000 TX:00000 RX:00000 S:00");
    render_prompt();

    gotoxy(0, DIVIDER_ROW);
    for (i = 0; i < SCREEN_COLS; ++i) {
        cputc('-');
    }

    rx_x = 0;
    rx_y = RX_START_ROW;
}

static void rx_put(unsigned char ch) {
    gotoxy(rx_x, rx_y);
    cputc(ch);

    if (ch == 0x9B || ch == 0x0D || ch == '\n') {
        rx_x = 0;
        ++rx_y;
    } else {
        ++rx_x;
        if (rx_x >= SCREEN_COLS) {
            rx_x = 0;
            ++rx_y;
        }
    }

    if (rx_y >= SCREEN_ROWS) {
        draw_ui();
    }
}

static void handle_key(unsigned char ch) {
    if (ch == 0x1B) {
        ns_end_stream();
        gotoxy(0, SCREEN_ROWS - 1);
        cprintf("Done.");
        exit(0);
    }

    if (ch == 0x9B || ch == 0x0D) {
        if (ns_send_byte(0x9B) == 0) {
            tx_count++;
        }
        input_len = 0;
        input_buf[0] = '\0';
        render_prompt();
        return;
    }

    if (ch == 0x7E || ch == 0x08) {
        if (input_len > 0) {
            --input_len;
            input_buf[input_len] = '\0';
            render_prompt();
        }
        return;
    }

    if (ch >= 0x20 && input_len < PROMPT_MAX) {
        if (ns_send_byte(ch) == 0) {
            tx_count++;
        }
        input_buf[input_len++] = (char)ch;
        input_buf[input_len] = '\0';
        render_prompt();
    }
}

int main(void) {
    clrscr();

    prompt_host();
    prompt_port();

    if (ns_init_netstream(host_buf, NETSTREAM_FLAGS, NETSTREAM_BAUD, swap16(host_port)) != 0) {
        gotoxy(0, HOST_ROW);
        cprintf("Bad baud %u", (unsigned)NETSTREAM_BAUD);
        cgetc();
        return 1;
    }
    ns_begin_stream();
    draw_ui();

    while (1) {
        unsigned int avail = ns_bytes_avail();
        gotoxy(0, STAT_ROW);
        cprintf("P:%02X AV:%5u TX:%5lu RX:%5lu",
                PACTL, avail, tx_count, rx_count);

        while (avail--) {
            int b = ns_recv_byte();
            if (b >= 0) {
                unsigned char ch = (unsigned char)b;
                if (ch == '\n') {
                    ch = 0x9B;
                }
                rx_put(ch);
                rx_count++;
            }
        }

        if (kbhit()) {
            unsigned char ch = (unsigned char)cgetc();
            handle_key(ch);
        }

        gotoxy(input_cursor_x, input_cursor_y);
    }

    return 0;
}
