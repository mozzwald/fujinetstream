#include <conio.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define BASEADDR 0x2800
#define ENGINE_PATH "D:NSENGINE.OBX"
#define PACTL (*(volatile unsigned char*)0xD302)
#define AUDF3 (*(volatile unsigned char*)0xD204)
#define AUDF4 (*(volatile unsigned char*)0xD206)

void __fastcall__ ns_begin(void);
void __fastcall__ ns_end(void);
unsigned char __fastcall__ ns_get_version(void);
unsigned int __fastcall__ ns_get_base(void);
unsigned char __fastcall__ ns_send_byte(unsigned char b);
int __fastcall__ ns_recv_byte(void);
unsigned int __fastcall__ ns_bytes_avail(void);
unsigned char __fastcall__ ns_get_status(void);

static void print_hex(unsigned char v) {
    static const char hexdig[] = "0123456789ABCDEF";
    cputc(hexdig[(v >> 4) & 0x0F]);
    cputc(hexdig[v & 0x0F]);
}

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

int main(void) {
    unsigned int frame = 0;
    unsigned char rx_row = 8;
    unsigned char rx_col = 0;
    unsigned char counter = 0;

    clrscr();
    printf("NETStream smoke test\n");
    printf("Loading %s...\n", ENGINE_PATH);

    if (!load_engine()) {
        printf("Load failed\n");
        cgetc();
        return 1;
    }

    printf("Loaded at $%04X\n", BASEADDR);
    printf("Version: $%02X  Base: $%04X\n", ns_get_version(), ns_get_base());
    gotoxy(0, 6);
    printf("RX:\n");

    ns_begin();

    while (!kbhit()) {
        unsigned int avail = ns_bytes_avail();
        unsigned char status = ns_get_status();

        gotoxy(0, 4);
        printf("PACTL=$%02X AUDF3=$%02X AUDF4=$%02X AVAIL=%5u TX=%3u",
                PACTL, AUDF3, AUDF4, avail, (unsigned)counter, status);

        if ((frame & 0x1F) == 0) {
            if (ns_send_byte(0x41) == 0) { /* A */
                counter++;
            }
            if (ns_send_byte(0x0A) == 0) { /* \n */
                counter++;
            }
            if (ns_send_byte(counter) == 0) {
                counter++;
            }
        }

        if (avail > 0) {
            gotoxy(rx_col, rx_row);
            cprintf("RX: ");
        }
        while (avail--) {
            int b = ns_recv_byte();
            if (b >= 0) {
                print_hex((unsigned char)b);
                cputc(' ');
                rx_col += 3;
                if (rx_col >= 36) {
                    rx_col = 0;
                    rx_row++;
                    if (rx_row > 23) {
                        rx_row = 7;
                    }
                }
            }
        }

        ++frame;
    }

    cgetc();
    ns_end();
    printf("\nDone.\n");

    return 0;
}
