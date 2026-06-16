#define _POSIX_C_SOURCE 200112L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define REGISTER_TOKEN "REGISTER"
#define DEFAULT_BIND "0.0.0.0"
#define DEFAULT_PORT "9000"
#define DEFAULT_TICK_HZ 20U
#define DEFAULT_AI_MOVE_EVERY 3U
#define FRAME_SYNC1 0xA5
#define FRAME_SYNC2 0x5A
#define MSG_CLIENT_INPUT 0x01
#define MSG_SERVER_SNAPSHOT 0x81
#define MAX_PAYLOAD 32
#define INPUT_FIRE 0x10
#define FLAG_COLLISION 0x01
#define FLAG_BULLET_ACTIVE 0x02
#define FLAG_AI_ALIVE 0x04
#define FLAG_AI_HIT 0x08
#define FLAG_PLAYER_ALIVE 0x10
#define FLAG_PLAYER_HIT 0x20
#define BULLET_MAX_RANGE 7
#define RESPAWN_TICKS (DEFAULT_TICK_HZ * 3U)
#define MIN_X 1
#define MAX_X 38
#define MIN_Y 1
#define MAX_Y 22

typedef struct Options {
    const char* bind_host;
    const char* port;
    unsigned int tick_hz;
    unsigned int ai_move_every;
    unsigned int max_runtime_sec;
    int verbose;
} Options;

typedef struct Parser {
    uint8_t state;
    uint8_t type;
    uint16_t seq;
    uint8_t len;
    uint8_t payload[MAX_PAYLOAD];
    uint8_t index;
    uint8_t sum;
} Parser;

typedef struct Game {
    uint8_t player_x;
    uint8_t player_y;
    uint8_t player_alive;
    uint8_t player_hit_this_tick;
    uint16_t player_respawn_ticks;
    uint8_t ai_x;
    uint8_t ai_y;
    uint8_t bullet_x;
    uint8_t bullet_y;
    int8_t bullet_dx;
    int8_t bullet_dy;
    uint8_t bullet_active;
    uint8_t bullet_range;
    uint8_t fire_ready;
    uint8_t ai_alive;
    uint8_t ai_hit_this_tick;
    uint16_t ai_respawn_ticks;
    uint8_t latest_input;
    uint16_t input_seq;
    uint16_t snapshot_seq;
    uint16_t tick;
    unsigned long ticks;
    unsigned long client_frames;
    unsigned long bad_client_frames;
    unsigned long snapshots_sent;
    unsigned long registers_seen;
    unsigned long shots_fired;
    unsigned long ai_hits;
} Game;

static uint64_t monotonic_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)(ts.tv_nsec / 1000ULL);
}

static void sleep_until_us(uint64_t when_us)
{
    while (1) {
        uint64_t now = monotonic_us();
        struct timespec ts;
        if (now >= when_us) {
            return;
        }
        ts.tv_sec = (time_t)((when_us - now) / 1000000ULL);
        ts.tv_nsec = (long)((when_us - now) % 1000000ULL) * 1000L;
        while (nanosleep(&ts, &ts) < 0 && errno == EINTR) {
        }
    }
}

static unsigned long parse_ulong_arg(const char* text, const char* name)
{
    char* end = NULL;
    unsigned long value = strtoul(text, &end, 10);
    if (end == text || *end != '\0') {
        fprintf(stderr, "Invalid %s: %s\n", name, text);
        exit(1);
    }
    return value;
}

static void usage(const char* prog)
{
    fprintf(stderr,
            "Usage: %s [--bind <host>] [--port <port>] [--tick-hz <n>] "
            "[--ai-move-every <n>] [--max-runtime-sec <n>] [--verbose]\n",
            prog);
}

static int parse_args(int argc, char** argv, Options* opts)
{
    int i;
    opts->bind_host = DEFAULT_BIND;
    opts->port = DEFAULT_PORT;
    opts->tick_hz = DEFAULT_TICK_HZ;
    opts->ai_move_every = DEFAULT_AI_MOVE_EVERY;
    opts->max_runtime_sec = 0;
    opts->verbose = 0;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bind") == 0 && i + 1 < argc) {
            opts->bind_host = argv[++i];
        } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            opts->port = argv[++i];
        } else if (strcmp(argv[i], "--tick-hz") == 0 && i + 1 < argc) {
            opts->tick_hz = (unsigned int)parse_ulong_arg(argv[++i], "tick-hz");
        } else if (strcmp(argv[i], "--ai-move-every") == 0 && i + 1 < argc) {
            opts->ai_move_every = (unsigned int)parse_ulong_arg(argv[++i], "ai-move-every");
        } else if (strcmp(argv[i], "--max-runtime-sec") == 0 && i + 1 < argc) {
            opts->max_runtime_sec = (unsigned int)parse_ulong_arg(argv[++i], "max-runtime-sec");
        } else if (strcmp(argv[i], "--verbose") == 0) {
            opts->verbose = 1;
        } else {
            usage(argv[0]);
            return 0;
        }
    }

    if (opts->tick_hz == 0 || opts->ai_move_every == 0) {
        usage(argv[0]);
        return 0;
    }
    return 1;
}

static int make_udp_socket(const Options* opts)
{
    struct addrinfo hints;
    struct addrinfo* res = NULL;
    struct addrinfo* it;
    int fd = -1;
    int yes = 1;
    int rc;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_PASSIVE;

    rc = getaddrinfo(opts->bind_host, opts->port, &hints, &res);
    if (rc != 0) {
        fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rc));
        return -1;
    }

    for (it = res; it != NULL; it = it->ai_next) {
        fd = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
        if (fd < 0) {
            continue;
        }
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        if (bind(fd, it->ai_addr, it->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }

    freeaddrinfo(res);
    return fd;
}

static void parser_init(Parser* parser)
{
    memset(parser, 0, sizeof(*parser));
}

static int seq_newer(uint16_t seq, uint16_t old)
{
    return (uint16_t)(seq - old) < 0x8000U && seq != old;
}

static int input_direction(uint8_t input, int8_t* dx, int8_t* dy)
{
    *dx = 0;
    *dy = 0;
    if (input & 0x01) {
        *dy = -1;
    } else if (input & 0x02) {
        *dy = 1;
    } else if (input & 0x04) {
        *dx = -1;
    } else if (input & 0x08) {
        *dx = 1;
    }
    return *dx != 0 || *dy != 0;
}

static void apply_input(Game* game, uint8_t input)
{
    if (!game->player_alive) {
        return;
    }
    if (input & INPUT_FIRE) {
        return;
    }

    if ((input & 0x01) && game->player_y > MIN_Y) {
        game->player_y--;
    } else if ((input & 0x02) && game->player_y < MAX_Y) {
        game->player_y++;
    } else if ((input & 0x04) && game->player_x > MIN_X) {
        game->player_x--;
    } else if ((input & 0x08) && game->player_x < MAX_X) {
        game->player_x++;
    }
}

static void hit_ai(Game* game)
{
    game->bullet_active = 0;
    game->fire_ready = 1;
    game->ai_alive = 0;
    game->ai_respawn_ticks = RESPAWN_TICKS;
    game->ai_hit_this_tick = 1;
    game->ai_hits++;
}

static void hit_player(Game* game)
{
    game->player_alive = 0;
    game->player_respawn_ticks = RESPAWN_TICKS;
    game->player_hit_this_tick = 1;
}

static void move_ai(Game* game)
{
    int dx = (int)game->player_x - (int)game->ai_x;
    int dy = (int)game->player_y - (int)game->ai_y;

    if (!game->player_alive) {
        return;
    }
    if (dx == 0 && dy == 0) {
        return;
    }
    if (abs(dx) >= abs(dy)) {
        if (dx < 0 && game->ai_x > MIN_X) {
            game->ai_x--;
        } else if (dx > 0 && game->ai_x < MAX_X) {
            game->ai_x++;
        } else if (dy < 0 && game->ai_y > MIN_Y) {
            game->ai_y--;
        } else if (dy > 0 && game->ai_y < MAX_Y) {
            game->ai_y++;
        }
    } else {
        if (dy < 0 && game->ai_y > MIN_Y) {
            game->ai_y--;
        } else if (dy > 0 && game->ai_y < MAX_Y) {
            game->ai_y++;
        } else if (dx < 0 && game->ai_x > MIN_X) {
            game->ai_x--;
        } else if (dx > 0 && game->ai_x < MAX_X) {
            game->ai_x++;
        }
    }
}

static uint8_t random_range(uint8_t min_value, uint8_t max_value)
{
    return (uint8_t)(min_value + (rand() % (max_value - min_value + 1)));
}

static void respawn_ai(Game* game)
{
    do {
        game->ai_x = random_range(MIN_X, MAX_X);
        game->ai_y = random_range(MIN_Y, MAX_Y);
    } while (game->player_alive && game->ai_x == game->player_x && game->ai_y == game->player_y);
    game->ai_alive = 1;
    game->ai_hit_this_tick = 0;
}

static void respawn_player(Game* game)
{
    do {
        game->player_x = random_range(MIN_X, MAX_X);
        game->player_y = random_range(MIN_Y, MAX_Y);
    } while (game->ai_alive && game->player_x == game->ai_x && game->player_y == game->ai_y);
    game->player_alive = 1;
    game->player_hit_this_tick = 0;
    game->fire_ready = 1;
}

static void update_bullet(Game* game)
{
    int8_t dx;
    int8_t dy;
    int next_x;
    int next_y;

    game->ai_hit_this_tick = 0;

    if (!(game->latest_input & INPUT_FIRE) || !game->player_alive) {
        game->fire_ready = 1;
    }

    if (!game->bullet_active) {
        if (game->player_alive && (game->latest_input & INPUT_FIRE) && game->fire_ready &&
            input_direction(game->latest_input, &dx, &dy)) {
            game->fire_ready = 0;
            next_x = (int)game->player_x + dx;
            next_y = (int)game->player_y + dy;
            if (next_x >= MIN_X && next_x <= MAX_X && next_y >= MIN_Y && next_y <= MAX_Y) {
                game->bullet_active = 1;
                game->bullet_x = (uint8_t)next_x;
                game->bullet_y = (uint8_t)next_y;
                game->bullet_dx = dx;
                game->bullet_dy = dy;
                game->bullet_range = 1;
                game->shots_fired++;
                if (game->ai_alive && game->bullet_x == game->ai_x && game->bullet_y == game->ai_y) {
                    hit_ai(game);
                }
            } else {
                game->fire_ready = 1;
            }
        }
        return;
    }

    if (game->ai_alive && game->bullet_x == game->ai_x && game->bullet_y == game->ai_y) {
        hit_ai(game);
        return;
    }

    if (game->bullet_range >= BULLET_MAX_RANGE) {
        game->bullet_active = 0;
        game->fire_ready = 1;
        return;
    }

    next_x = (int)game->bullet_x + game->bullet_dx;
    next_y = (int)game->bullet_y + game->bullet_dy;
    if (next_x < MIN_X || next_x > MAX_X || next_y < MIN_Y || next_y > MAX_Y) {
        game->bullet_active = 0;
        game->fire_ready = 1;
        return;
    }

    game->bullet_x = (uint8_t)next_x;
    game->bullet_y = (uint8_t)next_y;
    game->bullet_range++;

    if (game->ai_alive && game->bullet_x == game->ai_x && game->bullet_y == game->ai_y) {
        hit_ai(game);
    }
}

static void update_ai_respawn(Game* game)
{
    if (game->ai_alive) {
        return;
    }
    if (game->ai_respawn_ticks > 0) {
        game->ai_respawn_ticks--;
    }
    if (game->ai_respawn_ticks == 0) {
        respawn_ai(game);
    }
}

static void update_player_respawn(Game* game)
{
    if (game->player_alive) {
        return;
    }
    if (game->player_respawn_ticks > 0) {
        game->player_respawn_ticks--;
    }
    if (game->player_respawn_ticks == 0) {
        respawn_player(game);
    }
}

static void check_player_collision(Game* game)
{
    if (game->player_alive && game->ai_alive &&
        game->player_x == game->ai_x && game->player_y == game->ai_y) {
        hit_player(game);
    }
}

static void on_client_frame(Parser* parser, Game* game)
{
    if (parser->type != MSG_CLIENT_INPUT || parser->len < 3) {
        game->bad_client_frames++;
        return;
    }
    if (seq_newer(parser->seq, game->input_seq) || game->client_frames == 0) {
        game->input_seq = parser->seq;
        game->latest_input = parser->payload[0];
        game->client_frames++;
    }
}

static void parse_bytes(Parser* parser, Game* game, const uint8_t* buf, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++) {
        uint8_t b = buf[i];
        switch (parser->state) {
        case 0:
            if (b == FRAME_SYNC1) {
                parser->sum = b;
                parser->state = 1;
            }
            break;
        case 1:
            if (b == FRAME_SYNC2) {
                parser->sum = (uint8_t)(parser->sum + b);
                parser->state = 2;
            } else {
                parser->state = (b == FRAME_SYNC1) ? 1 : 0;
                parser->sum = (b == FRAME_SYNC1) ? b : 0;
            }
            break;
        case 2:
            parser->type = b;
            parser->sum = (uint8_t)(parser->sum + b);
            parser->state = 3;
            break;
        case 3:
            parser->seq = b;
            parser->sum = (uint8_t)(parser->sum + b);
            parser->state = 4;
            break;
        case 4:
            parser->seq |= ((uint16_t)b << 8);
            parser->sum = (uint8_t)(parser->sum + b);
            parser->state = 5;
            break;
        case 5:
            parser->len = b;
            parser->index = 0;
            parser->sum = (uint8_t)(parser->sum + b);
            if (parser->len > MAX_PAYLOAD) {
                game->bad_client_frames++;
                parser_init(parser);
            } else if (parser->len == 0) {
                parser->state = 7;
            } else {
                parser->state = 6;
            }
            break;
        case 6:
            parser->payload[parser->index++] = b;
            parser->sum = (uint8_t)(parser->sum + b);
            if (parser->index >= parser->len) {
                parser->state = 7;
            }
            break;
        case 7:
            parser->sum = (uint8_t)(parser->sum + b);
            if (parser->sum == 0) {
                on_client_frame(parser, game);
            } else {
                game->bad_client_frames++;
            }
            parser_init(parser);
            break;
        }
    }
}

static size_t make_snapshot(uint8_t* out, Game* game)
{
    uint8_t payload[10];
    uint8_t sum = 0;
    uint8_t i;
    size_t p = 0;

    payload[0] = (uint8_t)(game->tick & 0xff);
    payload[1] = (uint8_t)(game->tick >> 8);
    payload[2] = game->player_x;
    payload[3] = game->player_y;
    payload[4] = game->ai_x;
    payload[5] = game->ai_y;
    payload[6] = 0;
    if (game->player_x == game->ai_x && game->player_y == game->ai_y) {
        payload[6] |= FLAG_COLLISION;
    }
    if (game->bullet_active) {
        payload[6] |= FLAG_BULLET_ACTIVE;
    }
    if (game->ai_alive) {
        payload[6] |= FLAG_AI_ALIVE;
    }
    if (game->ai_hit_this_tick) {
        payload[6] |= FLAG_AI_HIT;
    }
    if (game->player_alive) {
        payload[6] |= FLAG_PLAYER_ALIVE;
    }
    if (game->player_hit_this_tick) {
        payload[6] |= FLAG_PLAYER_HIT;
    }
    payload[7] = 0;
    payload[8] = game->bullet_x;
    payload[9] = game->bullet_y;

    out[p++] = FRAME_SYNC1;
    out[p++] = FRAME_SYNC2;
    out[p++] = MSG_SERVER_SNAPSHOT;
    out[p++] = (uint8_t)(game->snapshot_seq & 0xff);
    out[p++] = (uint8_t)(game->snapshot_seq >> 8);
    out[p++] = sizeof(payload);
    for (i = 0; i < sizeof(payload); i++) {
        out[p++] = payload[i];
    }
    for (i = 0; i < p; i++) {
        sum = (uint8_t)(sum + out[i]);
    }
    out[p++] = (uint8_t)(0U - sum);
    return p;
}

static int is_register_packet(const uint8_t* buf, ssize_t len)
{
    size_t register_len = strlen(REGISTER_TOKEN);
    return len == (ssize_t)register_len && memcmp(buf, REGISTER_TOKEN, register_len) == 0;
}

static int same_peer(const struct sockaddr_storage* a, socklen_t a_len,
                     const struct sockaddr_storage* b, socklen_t b_len)
{
    const struct sockaddr_in* ia;
    const struct sockaddr_in* ib;

    if (a_len != b_len || a->ss_family != b->ss_family || a->ss_family != AF_INET) {
        return 0;
    }
    ia = (const struct sockaddr_in*)a;
    ib = (const struct sockaddr_in*)b;
    return ia->sin_port == ib->sin_port && ia->sin_addr.s_addr == ib->sin_addr.s_addr;
}

int main(int argc, char** argv)
{
    Options opts;
    Parser parser;
    Game game;
    struct sockaddr_storage peer;
    socklen_t peer_len = 0;
    int registered = 0;
    int fd;
    uint64_t start_us;
    uint64_t next_tick_us;
    uint64_t next_stats_us;
    uint64_t tick_interval_us;

    if (!parse_args(argc, argv, &opts)) {
        return 1;
    }

    fd = make_udp_socket(&opts);
    if (fd < 0) {
        perror("bind");
        return 1;
    }

    memset(&game, 0, sizeof(game));
    game.player_x = 6;
    game.player_y = 6;
    game.player_alive = 1;
    game.ai_x = 32;
    game.ai_y = 18;
    game.ai_alive = 1;
    game.fire_ready = 1;
    parser_init(&parser);

    tick_interval_us = 1000000ULL / opts.tick_hz;
    start_us = monotonic_us();
    srand((unsigned int)start_us);
    next_tick_us = start_us;
    next_stats_us = start_us + 1000000ULL;

    fprintf(stderr, "Waiting for REGISTER on UDP %s:%s...\n", opts.bind_host, opts.port);

    while (1) {
        uint8_t buf[512];
        struct sockaddr_storage from;
        socklen_t from_len = sizeof(from);
        ssize_t got;
        fd_set rfds;
        struct timeval tv;
        uint64_t now_us = monotonic_us();

        if (opts.max_runtime_sec && now_us - start_us >= (uint64_t)opts.max_runtime_sec * 1000000ULL) {
            break;
        }

        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        tv.tv_sec = 0;
        tv.tv_usec = 1000;
        if (select(fd + 1, &rfds, NULL, NULL, &tv) > 0) {
            got = recvfrom(fd, buf, sizeof(buf), 0, (struct sockaddr*)&from, &from_len);
            if (got > 0) {
                if (is_register_packet(buf, got)) {
                    peer = from;
                    peer_len = from_len;
                    registered = 1;
                    game.registers_seen++;
                    fprintf(stderr, "Client REGISTER received\n");
                } else if (registered && same_peer(&from, from_len, &peer, peer_len)) {
                    parse_bytes(&parser, &game, buf, (size_t)got);
                }
            }
        }

        now_us = monotonic_us();
        if (now_us >= next_tick_us) {
            if (registered) {
                uint8_t frame[32];
                size_t frame_len;
                game.player_hit_this_tick = 0;
                apply_input(&game, game.latest_input);
                update_bullet(&game);
                update_ai_respawn(&game);
                update_player_respawn(&game);
                if (game.ai_alive && (game.ticks % opts.ai_move_every) == 0) {
                    move_ai(&game);
                }
                check_player_collision(&game);
                frame_len = make_snapshot(frame, &game);
                if (sendto(fd, frame, frame_len, 0, (struct sockaddr*)&peer, peer_len) == (ssize_t)frame_len) {
                    game.snapshots_sent++;
                    game.snapshot_seq++;
                }
            }
            game.tick++;
            game.ticks++;
            next_tick_us += tick_interval_us;
            if (next_tick_us < now_us) {
                next_tick_us = now_us + tick_interval_us;
            }
        } else {
            sleep_until_us(next_tick_us);
        }

        now_us = monotonic_us();
        if (now_us >= next_stats_us) {
            fprintf(stderr,
                    "ticks=%lu registered=%d input=%lu bad=%lu sent=%lu player=%u,%u ai=%u,%u\n",
                    game.ticks, registered, game.client_frames, game.bad_client_frames,
                    game.snapshots_sent, game.player_x, game.player_y, game.ai_x, game.ai_y);
            next_stats_us += 1000000ULL;
        }
    }

    printf("PSEUDO GAME SERVER RESULT\n");
    printf("ticks=%lu\n", game.ticks);
    printf("client_frames=%lu\n", game.client_frames);
    printf("bad_client_frames=%lu\n", game.bad_client_frames);
    printf("snapshots_sent=%lu\n", game.snapshots_sent);
    printf("client_registered=%d\n", registered);
    printf("registers_seen=%lu\n", game.registers_seen);
    printf("shots_fired=%lu\n", game.shots_fired);
    printf("ai_hits=%lu\n", game.ai_hits);
    printf("duration_ms=%llu\n", (unsigned long long)((monotonic_us() - start_us) / 1000ULL));
    printf("END RESULT\n");

    close(fd);
    return 0;
}
