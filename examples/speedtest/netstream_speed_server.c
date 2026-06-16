#define _POSIX_C_SOURCE 200112L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define REGISTER_TOKEN "REGISTER"
#define MODE_PREFIX "SPEEDTEST MODE "
#define DEFAULT_BIND "0.0.0.0"
#define DEFAULT_PORT "9000"
#define DEFAULT_BYTES 16384UL
#define DEFAULT_BLOCK_SIZE 64U
#define MAX_BLOCK_SIZE 240U
#define FRAME_SYNC 0xA5

typedef enum Transport {
    TRANSPORT_UDP,
    TRANSPORT_TCP
} Transport;

typedef struct Options {
    Transport transport;
    const char* bind_host;
    const char* port;
    unsigned long bytes;
    unsigned int block_size;
    unsigned int delay_us;
    unsigned int repeat;
} Options;

typedef struct ModeInfo {
    char transport[8];
    char mode[12];
    unsigned int flags;
    unsigned long bytes;
    unsigned int block_size;
} ModeInfo;

static void usage(const char* prog)
{
    fprintf(stderr,
            "Usage: %s [--udp|--tcp] [--host <bind>] [--port <port>] "
            "[--bytes <payload-bytes>] [--block-size <n>] [--delay-us <n>] [--repeat <n>]\n",
            prog);
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

static void sleep_us(unsigned int usec)
{
    struct timespec ts;
    ts.tv_sec = usec / 1000000U;
    ts.tv_nsec = (long)(usec % 1000000U) * 1000L;
    while (nanosleep(&ts, &ts) < 0 && errno == EINTR) {
    }
}

static int is_register(const uint8_t* buf, size_t len)
{
    size_t register_len = strlen(REGISTER_TOKEN);
    return len == register_len && memcmp(buf, REGISTER_TOKEN, register_len) == 0;
}

static void mode_defaults(ModeInfo* mode, const Options* opts)
{
    strcpy(mode->transport, opts->transport == TRANSPORT_TCP ? "TCP" : "UDP");
    strcpy(mode->mode, "UNKNOWN");
    mode->flags = 0;
    mode->bytes = opts->bytes;
    mode->block_size = opts->block_size;
}

static int parse_hex_flags(const char* text, unsigned int* flags)
{
    char* end = NULL;
    unsigned long value;

    if (text[0] == '$') {
        ++text;
        value = strtoul(text, &end, 16);
    } else if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        value = strtoul(text + 2, &end, 16);
    } else {
        value = strtoul(text, &end, 16);
    }
    if (end == text || *end != '\0' || value > 0xFFUL) {
        return 0;
    }
    *flags = (unsigned int)value;
    return 1;
}

static int parse_mode_line(const char* line, ModeInfo* mode)
{
    char copy[256];
    char* token;

    if (strncmp(line, MODE_PREFIX, strlen(MODE_PREFIX)) != 0) {
        return 0;
    }

    strncpy(copy, line + strlen(MODE_PREFIX), sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    token = strtok(copy, " \t\r\n");
    while (token != NULL) {
        char* eq = strchr(token, '=');
        if (eq != NULL) {
            *eq++ = '\0';
            if (strcmp(token, "transport") == 0) {
                snprintf(mode->transport, sizeof(mode->transport), "%s", eq);
            } else if (strcmp(token, "mode") == 0) {
                snprintf(mode->mode, sizeof(mode->mode), "%s", eq);
            } else if (strcmp(token, "flags") == 0) {
                if (!parse_hex_flags(eq, &mode->flags)) {
                    return 0;
                }
            } else if (strcmp(token, "bytes") == 0) {
                mode->bytes = parse_ulong_arg(eq, "mode bytes");
            } else if (strcmp(token, "block_size") == 0) {
                mode->block_size = (unsigned int)parse_ulong_arg(eq, "mode block_size");
                if (mode->block_size == 0 || mode->block_size > MAX_BLOCK_SIZE) {
                    return 0;
                }
            }
        }
        token = strtok(NULL, " \t\r\n");
    }

    return mode->bytes > 0 && mode->block_size > 0 && mode->block_size <= MAX_BLOCK_SIZE;
}

static int make_listener(const Options* opts, int socktype)
{
    struct addrinfo hints;
    struct addrinfo* res = NULL;
    struct addrinfo* it;
    int fd = -1;
    int rc;
    int yes = 1;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = socktype;
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

static int wait_udp_mode(int fd, struct sockaddr_storage* peer, socklen_t* peer_len, ModeInfo* mode)
{
    char line[256];
    size_t line_len = 0;
    int saw_register = 0;

    fprintf(stderr, "Waiting for REGISTER and SPEEDTEST MODE over UDP...\n");
    while (1) {
        uint8_t buf[512];
        struct sockaddr_storage from;
        socklen_t from_len = sizeof(from);
        ssize_t got = recvfrom(fd, buf, sizeof(buf), 0, (struct sockaddr*)&from, &from_len);
        if (got < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("recvfrom");
            return 0;
        }
        if (got == 0) {
            continue;
        }
        if (is_register(buf, (size_t)got)) {
            *peer = from;
            *peer_len = from_len;
            saw_register = 1;
            line_len = 0;
            fprintf(stderr, "Client REGISTER received\n");
            continue;
        }
        if (!saw_register) {
            continue;
        }

        for (ssize_t i = 0; i < got; ++i) {
            uint8_t ch = buf[i];
            if (ch == 0x9B || ch == '\n' || ch == '\r') {
                line[line_len] = '\0';
                if (parse_mode_line(line, mode)) {
                    fprintf(stderr, "Mode: %s\n", line);
                    return 1;
                }
                fprintf(stderr, "Ignoring unparsed mode line: %s\n", line);
                line_len = 0;
                continue;
            }
            if (line_len + 1 < sizeof(line)) {
                line[line_len++] = (char)ch;
            }
        }
    }
}

static ssize_t tcp_read_some(int fd, uint8_t* buf, size_t len)
{
    ssize_t got;
    do {
        got = recv(fd, buf, len, 0);
    } while (got < 0 && errno == EINTR);
    return got;
}

static int wait_tcp_mode(int fd, ModeInfo* mode)
{
    char line[256];
    size_t line_len = 0;
    int saw_register = 0;

    fprintf(stderr, "Waiting for REGISTER and SPEEDTEST MODE over TCP...\n");
    while (1) {
        uint8_t buf[512];
        ssize_t got = tcp_read_some(fd, buf, sizeof(buf));
        if (got <= 0) {
            if (got < 0) {
                perror("recv");
            }
            return 0;
        }
        for (ssize_t i = 0; i < got; ++i) {
            uint8_t ch = buf[i];
            if (!saw_register) {
                static const char reg[] = REGISTER_TOKEN;
                static size_t reg_pos = 0;
                if (ch == (uint8_t)reg[reg_pos]) {
                    ++reg_pos;
                    if (reg_pos == strlen(reg)) {
                        saw_register = 1;
                        reg_pos = 0;
                        fprintf(stderr, "Client REGISTER received\n");
                    }
                    continue;
                }
                reg_pos = (ch == (uint8_t)reg[0]) ? 1U : 0U;
                continue;
            }

            if (ch == 0x9B || ch == '\n' || ch == '\r') {
                line[line_len] = '\0';
                if (parse_mode_line(line, mode)) {
                    fprintf(stderr, "Mode: %s\n", line);
                    return 1;
                }
                fprintf(stderr, "Ignoring unparsed mode line: %s\n", line);
                line_len = 0;
                continue;
            }
            if (line_len + 1 < sizeof(line)) {
                line[line_len++] = (char)ch;
            }
        }
    }
}

static uint8_t payload_byte(unsigned int block, unsigned int index)
{
    return (uint8_t)((block + index) & 0xFF);
}

static size_t build_frame(uint8_t* frame, unsigned int block, unsigned int payload_len)
{
    uint8_t checksum;
    size_t pos = 0;

    frame[pos++] = FRAME_SYNC;
    frame[pos++] = (uint8_t)(block & 0xFF);
    frame[pos++] = (uint8_t)((block >> 8) & 0xFF);
    frame[pos++] = (uint8_t)payload_len;

    checksum = 0;
    for (size_t i = 0; i < pos; ++i) {
        checksum = (uint8_t)(checksum + frame[i]);
    }

    for (unsigned int i = 0; i < payload_len; ++i) {
        frame[pos] = payload_byte(block, i);
        checksum = (uint8_t)(checksum + frame[pos]);
        ++pos;
    }
    frame[pos++] = checksum;

    return pos;
}

static int send_all(int fd, const uint8_t* buf, size_t len)
{
    while (len > 0) {
        ssize_t sent = send(fd, buf, len, 0);
        if (sent < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("send");
            return 0;
        }
        buf += sent;
        len -= (size_t)sent;
    }
    return 1;
}

static int send_run_udp(int fd, const struct sockaddr_storage* peer, socklen_t peer_len,
                        const Options* opts, const ModeInfo* mode)
{
    uint8_t frame[4 + MAX_BLOCK_SIZE + 1];
    unsigned long payload_sent = 0;
    unsigned long wire_sent = 0;
    unsigned int block = 0;
    struct timespec start;
    struct timespec end;

    clock_gettime(CLOCK_MONOTONIC, &start);
    while (payload_sent < mode->bytes) {
        unsigned long remaining = mode->bytes - payload_sent;
        unsigned int payload_len = remaining < mode->block_size ? (unsigned int)remaining : mode->block_size;
        size_t frame_len = build_frame(frame, block, payload_len);
        ssize_t sent = sendto(fd, frame, frame_len, 0, (const struct sockaddr*)peer, peer_len);
        if (sent < 0) {
            perror("sendto");
            return 0;
        }
        payload_sent += payload_len;
        wire_sent += (unsigned long)frame_len;
        ++block;
        if (opts->delay_us) {
            sleep_us(opts->delay_us);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    {
        unsigned long elapsed_ms = (unsigned long)((end.tv_sec - start.tv_sec) * 1000L +
            (end.tv_nsec - start.tv_nsec) / 1000000L);
        unsigned long bps = elapsed_ms ? (payload_sent * 1000UL) / elapsed_ms : payload_sent;
        printf("transport=UDP\nmode=%s\nflags=$%02X\nport=%s\npayload_bytes=%lu\nwire_bytes=%lu\nblock_size=%u\nblocks_sent=%u\nelapsed_ms=%lu\nserver_bytes_per_sec=%lu\n",
               mode->mode, mode->flags, opts->port, payload_sent, wire_sent,
               mode->block_size, block, elapsed_ms, bps);
    }
    return 1;
}

static int send_run_tcp(int fd, const Options* opts, const ModeInfo* mode)
{
    uint8_t frame[4 + MAX_BLOCK_SIZE + 1];
    unsigned long payload_sent = 0;
    unsigned long wire_sent = 0;
    unsigned int block = 0;
    struct timespec start;
    struct timespec end;

    clock_gettime(CLOCK_MONOTONIC, &start);
    while (payload_sent < mode->bytes) {
        unsigned long remaining = mode->bytes - payload_sent;
        unsigned int payload_len = remaining < mode->block_size ? (unsigned int)remaining : mode->block_size;
        size_t frame_len = build_frame(frame, block, payload_len);
        if (!send_all(fd, frame, frame_len)) {
            return 0;
        }
        payload_sent += payload_len;
        wire_sent += (unsigned long)frame_len;
        ++block;
        if (opts->delay_us) {
            sleep_us(opts->delay_us);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    {
        unsigned long elapsed_ms = (unsigned long)((end.tv_sec - start.tv_sec) * 1000L +
            (end.tv_nsec - start.tv_nsec) / 1000000L);
        unsigned long bps = elapsed_ms ? (payload_sent * 1000UL) / elapsed_ms : payload_sent;
        printf("transport=TCP\nmode=%s\nflags=$%02X\nport=%s\npayload_bytes=%lu\nwire_bytes=%lu\nblock_size=%u\nblocks_sent=%u\nelapsed_ms=%lu\nserver_bytes_per_sec=%lu\n",
               mode->mode, mode->flags, opts->port, payload_sent, wire_sent,
               mode->block_size, block, elapsed_ms, bps);
    }
    return 1;
}

int main(int argc, char** argv)
{
    Options opts;
    int fd;

    opts.transport = TRANSPORT_UDP;
    opts.bind_host = DEFAULT_BIND;
    opts.port = DEFAULT_PORT;
    opts.bytes = DEFAULT_BYTES;
    opts.block_size = DEFAULT_BLOCK_SIZE;
    opts.delay_us = 0;
    opts.repeat = 1;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--udp") == 0) {
            opts.transport = TRANSPORT_UDP;
        } else if (strcmp(argv[i], "--tcp") == 0) {
            opts.transport = TRANSPORT_TCP;
        } else if ((strcmp(argv[i], "--host") == 0 || strcmp(argv[i], "--bind") == 0) && i + 1 < argc) {
            opts.bind_host = argv[++i];
        } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            opts.port = argv[++i];
        } else if (strcmp(argv[i], "--bytes") == 0 && i + 1 < argc) {
            opts.bytes = parse_ulong_arg(argv[++i], "bytes");
        } else if (strcmp(argv[i], "--block-size") == 0 && i + 1 < argc) {
            opts.block_size = (unsigned int)parse_ulong_arg(argv[++i], "block-size");
        } else if (strcmp(argv[i], "--delay-us") == 0 && i + 1 < argc) {
            opts.delay_us = (unsigned int)parse_ulong_arg(argv[++i], "delay-us");
        } else if (strcmp(argv[i], "--repeat") == 0 && i + 1 < argc) {
            opts.repeat = (unsigned int)parse_ulong_arg(argv[++i], "repeat");
            if (!opts.repeat) {
                opts.repeat = 1;
            }
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (opts.bytes == 0 || opts.block_size == 0 || opts.block_size > MAX_BLOCK_SIZE) {
        fprintf(stderr, "Invalid bytes or block-size\n");
        return 1;
    }

    if (opts.transport == TRANSPORT_UDP) {
        fd = make_listener(&opts, SOCK_DGRAM);
        if (fd < 0) {
            perror("bind UDP");
            return 1;
        }
        for (unsigned int run = 0; run < opts.repeat; ++run) {
            struct sockaddr_storage peer;
            socklen_t peer_len = 0;
            ModeInfo mode;
            mode_defaults(&mode, &opts);
            if (!wait_udp_mode(fd, &peer, &peer_len, &mode)) {
                close(fd);
                return 1;
            }
            if (!send_run_udp(fd, &peer, peer_len, &opts, &mode)) {
                close(fd);
                return 1;
            }
        }
        close(fd);
    } else {
        fd = make_listener(&opts, SOCK_STREAM);
        if (fd < 0) {
            perror("bind TCP");
            return 1;
        }
        if (listen(fd, 1) < 0) {
            perror("listen");
            close(fd);
            return 1;
        }
        for (unsigned int run = 0; run < opts.repeat; ++run) {
            struct sockaddr_storage peer;
            socklen_t peer_len = sizeof(peer);
            int client_fd;
            ModeInfo mode;
            mode_defaults(&mode, &opts);
            fprintf(stderr, "Waiting for TCP connection on %s:%s...\n", opts.bind_host, opts.port);
            client_fd = accept(fd, (struct sockaddr*)&peer, &peer_len);
            if (client_fd < 0) {
                perror("accept");
                close(fd);
                return 1;
            }
            if (!wait_tcp_mode(client_fd, &mode) || !send_run_tcp(client_fd, &opts, &mode)) {
                close(client_fd);
                close(fd);
                return 1;
            }
            close(client_fd);
        }
        close(fd);
    }

    return 0;
}
