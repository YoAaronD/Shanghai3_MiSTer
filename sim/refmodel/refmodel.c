/* Software reference model of the Shanghai III board (CPU side only).
 *
 * Uses the Musashi 68000 emulator with the memory map from MAME's
 * shangha3.cpp. Runs much faster than the HDL simulation, and writes a trace
 * in the same format so the two can be compared (scripts/compare_traces.py).
 *
 * Timing: 16 MHz CPU, 1024 CPU clocks per line, 263 lines, IRQ4 at line 240.
 *
 * usage: refmodel prog.bin frames trace.txt [options]
 *   --dsw1 XX --dsw2 XX   DIP switches (hex, default ff)
 *   --no-rom-log          leave program ROM reads out of the trace
 *   --gfx blitter.bin     enable the software blitter
 *   --frames-out DIR      write frames as DIR/frame_NNNNN.ppm (needs --gfx)
 *   --every N             only write every Nth frame (default 1)
 *   --dump-blits DIR      save RAM + frame buffer before/after blitter runs
 *   --dump-every N        ...every Nth run (default 50), --dump-max M runs (default 40)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "m68k.h"
#include "blitter.h"

static unsigned char rom[0x80000];
static unsigned char ram[0x10000];
static unsigned char pal[0x1000];
static unsigned dsw1 = 0xff, dsw2 = 0xbf;   /* MAME defaults: demo sounds on */
static int ay_addr = 0;
static unsigned char ay_regs[16];
static int prot_cnt = 0;
static long long cpu_clock = 0;   /* total CPU clocks executed */
static int irq4 = 0;
static FILE *tr;
static int log_rom = 1;
static unsigned short gfxlist = 0;
static int flip = 0;
static int gfx_on = 0;
/* --dump-blits: save snapshots around blitter runs for the HDL unit test */
static const char *dump_dir = NULL;
static int dump_every = 50, dump_max = 40, dump_count = 0;
static const char *dump_filter = NULL;   /* "zoom" or "tilemap": only runs that use it */
static long blit_index = 0;

static void dump_file(const char *name, const void *data, size_t n) {
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dump_dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return; }
    fwrite(data, 1, n, f);
    fclose(f);
}


#define LINE_CLKS   1024
#define FRAME_CLKS  (LINE_CLKS * 263)

static double now_us(void) { return (cpu_clock + m68k_cycles_run()) / 16.0; }
static int vblank(void) {
    long long c = (cpu_clock + m68k_cycles_run()) % FRAME_CLKS;
    int line = (int)(c / LINE_CLKS);
    return line < 16 || line > 239;
}

static unsigned read16(unsigned a) {
    a &= 0xfffffe;
    if (a < 0x80000) return (rom[a] << 8) | rom[a + 1];
    if ((a & 0xfff000) == 0x100000) return (pal[a & 0xfff] << 8) | pal[(a & 0xfff) + 1];
    if ((a & 0xff0000) == 0x300000) return (ram[a & 0xffff] << 8) | ram[(a & 0xffff) + 1];
    if ((a & 0xffff00) == 0x200000) {
        switch (a & 0xff) {
        case 0x00: return 0xffff;
        case 0x02: return 0xff00 | (vblank() ? 0 : 0x80) | 0x7f;
        case 0x1e: {
            unsigned v = ay_addr == 14 ? dsw1 : ay_addr == 15 ? dsw2 : ay_regs[ay_addr];
            return 0xff00 | v;
        }
        case 0x4e: {
            static const int r[] = {0x0,0x1,0x3,0x7,0xf,0xe,0xc,0x8,0x0};
            int v = r[prot_cnt]; prot_cnt = (prot_cnt + 1) % 9; return v;
        }
        case 0x6e: return 0xff00;   /* OKI status: idle (matches HDL stub) */
        }
    }
    return 0xffff;
}

static void log_read(unsigned a, unsigned v) {
    if (log_rom || a >= 0x80000) fprintf(tr, "%10.2f R %06X %04X\n", now_us(), a, v);
}

static void write_io(unsigned a, unsigned v, int uds, int lds) {
    a &= 0xfffffe;
    if ((a & 0xfff000) == 0x100000) {
        if (uds) pal[a & 0xfff] = v >> 8;
        if (lds) pal[(a & 0xfff) + 1] = v;
    } else if ((a & 0xff0000) == 0x300000) {
        if (uds) ram[a & 0xffff] = v >> 8;
        if (lds) ram[(a & 0xffff) + 1] = v;
    } else if ((a & 0xffff00) == 0x200000) {
        switch (a & 0xff) {
        case 0x08:
            fprintf(tr, "%10.2f EV BLITTER_GO list=%04X\n", now_us(), gfxlist);
            if (gfx_on) {
                static uint16_t w[0x8000];
                for (int i = 0; i < 0x8000; i++) w[i] = (ram[2 * i] << 8) | ram[2 * i + 1];
                int dump = dump_dir && dump_count < dump_max &&
                           (dump_filter || (blit_index % dump_every) == 0);
                static uint16_t vis[384 * 224];
                static uint8_t ram_copy[0x10000];
                char name[64];
                long z0 = blit_stats.sprite_zoom, t0 = blit_stats.tilemaps;
                if (dump) {
                    memcpy(ram_copy, ram, sizeof ram);
                    blit_get_visible(vis);
                }
                blit_run(w, gfxlist, flip, 1);
                if (dump && dump_filter) {
                    if (!strcmp(dump_filter, "zoom")) dump = blit_stats.sprite_zoom > z0;
                    else if (!strcmp(dump_filter, "tilemap")) dump = blit_stats.tilemaps > t0;
                }
                if (dump) {
                    snprintf(name, sizeof name, "blit_%05ld_ram.bin", blit_index);
                    dump_file(name, ram_copy, sizeof ram_copy);       /* big-endian words */
                    snprintf(name, sizeof name, "blit_%05ld_before.bin", blit_index);
                    dump_file(name, vis, sizeof vis);                 /* little-endian u16 */
                    blit_get_visible(vis);
                    snprintf(name, sizeof name, "blit_%05ld_after.bin", blit_index);
                    dump_file(name, vis, sizeof vis);
                    char info[64];
                    int n = snprintf(info, sizeof info, "%04X %d\n", gfxlist, flip);
                    snprintf(name, sizeof name, "blit_%05ld_info.txt", blit_index);
                    dump_file(name, info, n);
                    dump_count++;
                }
                blit_index++;
            }
            break;
        case 0x0a: irq4 = 0; m68k_set_irq(0); fprintf(tr, "%10.2f EV IRQ_ACK\n", now_us()); break;
        case 0x2e: if (lds) ay_regs[ay_addr] = v; break;
        case 0x3e: if (lds) ay_addr = (v & 0xf0) ? ay_addr : (v & 0xf); break;
        case 0x6e: if (lds) fprintf(tr, "%10.2f EV OKI_WRITE %02X\n", now_us(), v & 0xff); break;
        }
    } else if ((a & 0xfffffe) == 0x340000) {
        if (lds) flip = (v >> 7) & 1;
    } else if ((a & 0xfffffe) == 0x360000) {
        unsigned old = gfxlist;
        if (uds) gfxlist = (gfxlist & 0x00ff) | (v & 0xff00);
        if (lds) gfxlist = (gfxlist & 0xff00) | (v & 0x00ff);
        if (gfxlist != old) fprintf(tr, "%10.2f EV GFXLIST %04X\n", now_us(), gfxlist);
    }
}

/* Musashi callbacks. Byte accesses are mapped onto 16-bit bus cycles with UDS/LDS. */
unsigned int m68k_read_memory_8(unsigned int a) {
    unsigned v = read16(a); log_read(a & 0xfffffe, v);
    return (a & 1) ? (v & 0xff) : (v >> 8);
}
unsigned int m68k_read_memory_16(unsigned int a) {
    unsigned v = read16(a); log_read(a & 0xfffffe, v); return v;
}
unsigned int m68k_read_memory_32(unsigned int a) {
    unsigned hi = m68k_read_memory_16(a), lo = m68k_read_memory_16(a + 2);
    return (hi << 16) | lo;
}
void m68k_write_memory_8(unsigned int a, unsigned int v) {
    unsigned w = (v & 0xff) * 0x101;
    fprintf(tr, "%10.2f W %06X %04X\n", now_us(), a & 0xfffffe, w);
    write_io(a, w, !(a & 1), a & 1);
}
void m68k_write_memory_16(unsigned int a, unsigned int v) {
    fprintf(tr, "%10.2f W %06X %04X\n", now_us(), a & 0xfffffe, v & 0xffff);
    write_io(a, v, 1, 1);
}
void m68k_write_memory_32(unsigned int a, unsigned int v) {
    m68k_write_memory_16(a, v >> 16);
    m68k_write_memory_16(a + 2, v & 0xffff);
}
unsigned int m68k_read_disassembler_8(unsigned int a) { return rom[a & 0x7ffff]; }
unsigned int m68k_read_disassembler_16(unsigned int a) { a &= 0x7fffe; return (rom[a] << 8) | rom[a + 1]; }
unsigned int m68k_read_disassembler_32(unsigned int a) { return (m68k_read_disassembler_16(a) << 16) | m68k_read_disassembler_16(a + 2); }

static void write_frame(const char *dir, int n) {
    static uint8_t rgb[384 * 224 * 3];
    static uint16_t p[2048];
    for (int i = 0; i < 2048; i++) p[i] = (pal[2 * i] << 8) | pal[2 * i + 1];
    blit_render_rgb(p, rgb);
    char path[512];
    snprintf(path, sizeof path, "%s/frame_%05d.ppm", dir, n);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return; }
    fprintf(f, "P6\n384 224\n255\n");
    fwrite(rgb, 1, sizeof rgb, f);
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: refmodel prog.bin frames trace.txt [options]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fread(rom, 1, sizeof rom, f); fclose(f);
    int frames = atoi(argv[2]);
    tr = fopen(argv[3], "w");
    const char *frames_out = NULL;
    int every = 1;
    static uint8_t gfxrom[0x200000];
    for (int i = 4; i < argc; i++) {
        if (!strcmp(argv[i], "--no-rom-log")) log_rom = 0;
        else if (!strcmp(argv[i], "--dsw1") && i + 1 < argc) dsw1 = strtoul(argv[++i], 0, 16);
        else if (!strcmp(argv[i], "--dsw2") && i + 1 < argc) dsw2 = strtoul(argv[++i], 0, 16);
        else if (!strcmp(argv[i], "--every") && i + 1 < argc) every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--frames-out") && i + 1 < argc) frames_out = argv[++i];
        else if (!strcmp(argv[i], "--dump-blits") && i + 1 < argc) dump_dir = argv[++i];
        else if (!strcmp(argv[i], "--dump-every") && i + 1 < argc) dump_every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--dump-max") && i + 1 < argc) dump_max = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--dump-filter") && i + 1 < argc) dump_filter = argv[++i];
        else if (!strcmp(argv[i], "--gfx") && i + 1 < argc) {
            FILE *g = fopen(argv[++i], "rb");
            if (!g) { perror(argv[i]); return 1; }
            size_t n = fread(gfxrom, 1, sizeof gfxrom, g); fclose(g);
            blit_init(gfxrom, (int)n);
            gfx_on = 1;
        } else { fprintf(stderr, "unknown option %s\n", argv[i]); return 1; }
    }

    memset(ram, 0, sizeof ram);   /* HDL RAM also powers up as zero in Verilator */
    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68000);
    m68k_pulse_reset();

    for (int fr = 0; fr < frames; fr++) {
        for (int line = 0; line < 263; line++) {
            if (line == 240) {
                fprintf(tr, "%10.2f EV FRAME %d\n", now_us(), fr + 1);
                if (frames_out && gfx_on && (fr + 1) % every == 0) write_frame(frames_out, fr + 1);
                irq4 = 1; m68k_set_irq(4);
            }
            cpu_clock += m68k_execute(LINE_CLKS);
        }
    }
    fclose(tr);
    printf("ran %d frames\n", frames);
    if (gfx_on)
        printf("blitter: %ld runs; commands drawn: %ld sprites, %ld fills, %ld tilemaps (%ld condensed); "
               "zoomed: %ld sprites, %ld tilemaps; rotation fields set: %ld\n",
               blit_stats.runs, blit_stats.sprites, blit_stats.fills, blit_stats.tilemaps,
               blit_stats.condensed, blit_stats.sprite_zoom, blit_stats.tilemap_zoom, blit_stats.rotation);
    if (gfx_on)
        printf("busiest run: %ld pixels visited, %ld active commands\n", blit_stats.px_max_run, blit_stats.cmds_max_run);
    return 0;
}
