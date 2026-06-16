#include <conio.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef NETSTREAM_LINKED_HANDLER
#define BASEADDR 0x2800
#define ENGINE_PATH "D:NSENGINE.OBX"
#endif

#define NETSTREAM_FLAG_REGISTER 0x02
#define NETSTREAM_FLAG_UNPACED 0x40

#ifndef GAME_DEFAULT_HOST
#define GAME_DEFAULT_HOST "127.0.0.2"
#endif
#ifndef GAME_DEFAULT_PORT
#define GAME_DEFAULT_PORT 9000
#endif
#ifndef GAME_UNPACED
#define GAME_UNPACED 0
#endif

#define NETSTREAM_BAUD ((unsigned int)57600UL)
#define FRAME_SYNC1 0xA5
#define FRAME_SYNC2 0x5A
#define MSG_CLIENT_INPUT 0x01
#define MSG_SERVER_SNAPSHOT 0x81
#define MAX_PAYLOAD 32
#define TICK_FRAMES 3
#define INPUT_FIRE 0x10
#define FLAG_BULLET_ACTIVE 0x02
#define FLAG_AI_ALIVE 0x04
#define FLAG_AI_HIT 0x08
#define FLAG_PLAYER_ALIVE 0x10
#define FLAG_PLAYER_HIT 0x20
#define STICK0 (*(volatile unsigned char*)0x0278)
#define STRIG0 (*(volatile unsigned char*)0x0284)
#define RTCLOK ((volatile unsigned char*)0x0012)

void __fastcall__ ns_begin_stream(void);
void __fastcall__ ns_end_stream(void);
unsigned char __fastcall__ ns_send_byte(unsigned char b);
int __fastcall__ ns_recv_byte(void);
unsigned int __fastcall__ ns_bytes_avail(void);
unsigned char __fastcall__ ns_get_status(void);
unsigned char __fastcall__ ns_get_final_flags(void);
unsigned char __fastcall__ ns_init_netstream(const char* host, unsigned char flags, unsigned int nominal_baud, unsigned int port_swapped);

static unsigned char local_x = 6;
static unsigned char local_y = 6;
static unsigned char ai_x = 32;
static unsigned char ai_y = 18;
static unsigned char bullet_x;
static unsigned char bullet_y;
static unsigned char bullet_active;
static unsigned char ai_alive = 1;
static unsigned char player_alive = 1;
static unsigned char latest_flags;
static unsigned int latest_tick;
static unsigned int tx_seq;
static unsigned int rx_seq;
static unsigned int snapshots_valid;
static unsigned int bad_frames;
static unsigned int resyncs;
static unsigned int sequence_misses;
static unsigned int max_sequence_gap;
static unsigned int frames_since_snapshot;
static unsigned long input_sent;
static unsigned char status_or;
static unsigned char final_flags;
static unsigned char parser_state;
static unsigned char parser_type;
static unsigned int parser_seq;
static unsigned char parser_len;
static unsigned char parser_index;
static unsigned char parser_sum;
static unsigned char parser_payload[MAX_PAYLOAD];

#ifndef NETSTREAM_LINKED_HANDLER
static unsigned char load_engine(void)
{
    FILE* f;
    unsigned char hdr[6];
    unsigned char* dst;
    size_t n;

    f = fopen(ENGINE_PATH, "rb");
    dst = (unsigned char*)BASEADDR;
    if (!f) {
        return 0;
    }

    n = fread(hdr, 1, 2, f);
    if (n != 2) {
        fclose(f);
        return 0;
    }

    if (hdr[0] == 0xFF && hdr[1] == 0xFF) {
        unsigned int start;
        unsigned int end;
        unsigned int len;

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
        unsigned int i;
        i = 0;
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

static unsigned int swap16(unsigned int value)
{
    return (unsigned int)(((value << 8) & 0xFF00) | ((value >> 8) & 0x00FF));
}

static unsigned long read_rtclok(void)
{
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

static void put_at(unsigned char x, unsigned char y, char ch)
{
    gotoxy(x, y);
    cputc(ch);
}

static void draw_border(void)
{
    unsigned char x;
    unsigned char y;

    clrscr();
    for (x = 0; x < 40; x++) {
        put_at(x, 0, ' ');
        put_at(x, 23, '#');
    }
    for (y = 1; y < 23; y++) {
        put_at(0, y, '#');
        put_at(39, y, '#');
    }
}

static void draw_status(void)
{
    gotoxy(0, 20);
    cprintf("S%u B%u R%u M%u G%u", snapshots_valid, bad_frames, resyncs, sequence_misses, max_sequence_gap);
    gotoxy(0, 21);
    cprintf("TX%lu AGE%u ST$%02X FF$%02X", input_sent, frames_since_snapshot, status_or, final_flags);
    gotoxy(0, 22);
    cprintf("T%u F$%02X        ", latest_tick, latest_flags);
}

static void draw_game(void)
{
    static unsigned char old_lx = 0;
    static unsigned char old_ly = 0;
    static unsigned char old_ax = 0;
    static unsigned char old_ay = 0;
    static unsigned char old_bx = 0;
    static unsigned char old_by = 0;

    if (old_lx) {
        put_at(old_lx, old_ly, ' ');
    }
    if (old_ax) {
        put_at(old_ax, old_ay, ' ');
    }
    if (old_bx) {
        put_at(old_bx, old_by, ' ');
    }

    if (player_alive) {
        put_at(local_x, local_y, '@');
        old_lx = local_x;
        old_ly = local_y;
    } else {
        old_lx = 0;
        old_ly = 0;
    }
    if (ai_alive) {
        put_at(ai_x, ai_y, 'X');
        old_ax = ai_x;
        old_ay = ai_y;
    } else {
        old_ax = 0;
        old_ay = 0;
    }
    if (bullet_active) {
        put_at(bullet_x, bullet_y, '*');
        old_bx = bullet_x;
        old_by = bullet_y;
    } else {
        old_bx = 0;
        old_by = 0;
    }
    draw_status();
}

static unsigned char read_input_bits(void)
{
    unsigned char s;
    unsigned char out;

    s = (unsigned char)(~STICK0) & 0x0F;
    out = 0;
    if (s & 0x01) {
        out |= 0x01;
    }
    if (s & 0x02) {
        out |= 0x02;
    }
    if (s & 0x04) {
        out |= 0x04;
    }
    if (s & 0x08) {
        out |= 0x08;
    }
    if (STRIG0 == 0) {
        out |= INPUT_FIRE;
    }
    return out;
}

static unsigned char send_byte_wait(unsigned char b)
{
    unsigned long spins;

    spins = 0;
    while (ns_send_byte(b) != 0) {
        if (++spins > 200000UL) {
            return 0;
        }
    }
    return 1;
}

static unsigned char send_frame(unsigned char type, unsigned char* payload, unsigned char len)
{
    unsigned char header[6];
    unsigned char i;
    unsigned char sum;

    header[0] = FRAME_SYNC1;
    header[1] = FRAME_SYNC2;
    header[2] = type;
    header[3] = (unsigned char)(tx_seq & 0xFF);
    header[4] = (unsigned char)(tx_seq >> 8);
    header[5] = len;
    sum = 0;
    for (i = 0; i < sizeof(header); i++) {
        sum = (unsigned char)(sum + header[i]);
        if (!send_byte_wait(header[i])) {
            return 0;
        }
    }
    for (i = 0; i < len; i++) {
        sum = (unsigned char)(sum + payload[i]);
        if (!send_byte_wait(payload[i])) {
            return 0;
        }
    }
    if (!send_byte_wait((unsigned char)(0U - sum))) {
        return 0;
    }
    ++tx_seq;
    return 1;
}

static void send_input(void)
{
    unsigned char payload[3];

    payload[0] = read_input_bits();
    payload[1] = local_x;
    payload[2] = local_y;
    if (send_frame(MSG_CLIENT_INPUT, payload, sizeof(payload))) {
        ++input_sent;
    }
}

static unsigned char seq_newer(unsigned int seq, unsigned int old)
{
    return (unsigned int)(seq - old) < 0x8000U && seq != old;
}

static void accept_snapshot(void)
{
    unsigned int gap;

    if (parser_type != MSG_SERVER_SNAPSHOT || parser_len < 8) {
        ++bad_frames;
        return;
    }

    if (snapshots_valid && !seq_newer(parser_seq, rx_seq)) {
        return;
    }
    if (snapshots_valid) {
        gap = (unsigned int)(parser_seq - rx_seq);
        if (gap > 1) {
            sequence_misses += (unsigned int)(gap - 1);
            if (gap > max_sequence_gap) {
                max_sequence_gap = gap;
            }
        }
    }

    rx_seq = parser_seq;
    latest_tick = (unsigned int)parser_payload[0] | ((unsigned int)parser_payload[1] << 8);
    local_x = parser_payload[2];
    local_y = parser_payload[3];
    ai_x = parser_payload[4];
    ai_y = parser_payload[5];
    latest_flags = parser_payload[6];
    ai_alive = (latest_flags & FLAG_AI_ALIVE) ? 1 : 0;
    player_alive = (latest_flags & FLAG_PLAYER_ALIVE) ? 1 : 0;
    bullet_active = (latest_flags & FLAG_BULLET_ACTIVE) ? 1 : 0;
    if (parser_len >= 10) {
        bullet_x = parser_payload[8];
        bullet_y = parser_payload[9];
    } else {
        bullet_x = 0;
        bullet_y = 0;
    }
    ++snapshots_valid;
    frames_since_snapshot = 0;
}

static void parser_reset(void)
{
    parser_state = 0;
    parser_type = 0;
    parser_seq = 0;
    parser_len = 0;
    parser_index = 0;
    parser_sum = 0;
}

static void parse_byte(unsigned char b)
{
    switch (parser_state) {
    case 0:
        if (b == FRAME_SYNC1) {
            parser_sum = b;
            parser_state = 1;
        }
        break;
    case 1:
        if (b == FRAME_SYNC2) {
            parser_sum = (unsigned char)(parser_sum + b);
            parser_state = 2;
        } else {
            ++resyncs;
            if (b == FRAME_SYNC1) {
                parser_sum = b;
            } else {
                parser_reset();
            }
        }
        break;
    case 2:
        parser_type = b;
        parser_sum = (unsigned char)(parser_sum + b);
        parser_state = 3;
        break;
    case 3:
        parser_seq = b;
        parser_sum = (unsigned char)(parser_sum + b);
        parser_state = 4;
        break;
    case 4:
        parser_seq |= ((unsigned int)b << 8);
        parser_sum = (unsigned char)(parser_sum + b);
        parser_state = 5;
        break;
    case 5:
        parser_len = b;
        parser_index = 0;
        parser_sum = (unsigned char)(parser_sum + b);
        if (parser_len > MAX_PAYLOAD) {
            ++bad_frames;
            ++resyncs;
            parser_reset();
        } else if (parser_len == 0) {
            parser_state = 7;
        } else {
            parser_state = 6;
        }
        break;
    case 6:
        parser_payload[parser_index++] = b;
        parser_sum = (unsigned char)(parser_sum + b);
        if (parser_index >= parser_len) {
            parser_state = 7;
        }
        break;
    case 7:
        parser_sum = (unsigned char)(parser_sum + b);
        if (parser_sum == 0) {
            accept_snapshot();
        } else {
            ++bad_frames;
            ++resyncs;
        }
        parser_reset();
        break;
    }
}

static void drain_netstream(void)
{
    unsigned int avail;

    avail = ns_bytes_avail();
    while (avail > 0) {
        int value;
        value = ns_recv_byte();
        if (value >= 0) {
            parse_byte((unsigned char)value);
        }
        --avail;
    }
    status_or |= ns_get_status();
}

int main(void)
{
    unsigned char flags;
    unsigned long next_tick;
    unsigned long now;

#ifndef NETSTREAM_LINKED_HANDLER
    if (!load_engine()) {
        cprintf("Failed to load NSENGINE.OBX\r\n");
        return 1;
    }
#endif

    flags = NETSTREAM_FLAG_REGISTER;
#if GAME_UNPACED
    flags |= NETSTREAM_FLAG_UNPACED;
#endif

    draw_border();
    gotoxy(0, 0);
    cprintf("PseudoGame %s:%u F$%02X", GAME_DEFAULT_HOST, (unsigned)GAME_DEFAULT_PORT, flags);

    if (ns_init_netstream(GAME_DEFAULT_HOST, flags, NETSTREAM_BAUD, swap16(GAME_DEFAULT_PORT)) != 0) {
        gotoxy(1, 4);
        cprintf("Init failed");
        return 1;
    }

    final_flags = ns_get_final_flags();
    parser_reset();
    ns_begin_stream();
    next_tick = read_rtclok();

    while (1) {
        drain_netstream();
        now = read_rtclok();
        if ((unsigned int)(now - next_tick) >= TICK_FRAMES) {
            next_tick = now;
            send_input();
            drain_netstream();
            ++frames_since_snapshot;
            draw_game();
        }
    }

}
