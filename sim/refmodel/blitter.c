/* Software model of the Sunsoft GA9201 KA01-0249 blitter (Shanghai III).
 *
 * Written from the behaviour documented in MAME's shangha3.cpp driver
 * (command format, tile layout, zoom maths); this is our own code, meant as
 * the "golden" model the HDL blitter will be checked against pixel by pixel.
 *
 * Frame buffer: 512 x 263 entries of 12 bits
 *   bits 10..0  palette index (color * 16 + pen)
 *   bit  11     shadow bank (darkened copy of the palette)
 * The frame buffer is never cleared; the game overdraws it.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "blitter.h"

#define FB_W 512
#define FB_H 263

static uint16_t fb[FB_H][FB_W];
static const uint8_t *gfx;          /* 2 MB tile ROM, 16384 tiles of 128 bytes */
static int gfx_tiles;

blit_stats_t blit_stats;

void blit_init(const uint8_t *gfxrom, int gfxsize) {
    gfx = gfxrom;
    gfx_tiles = gfxsize / 128;
    memset(fb, 0, sizeof fb);
}

/* Pixel x,y (0..15) of a tile: 8 bytes per row, low nibble = left pixel */
static inline int tile_pixel(int code, int x, int y) {
    const uint8_t *t = gfx + (code % gfx_tiles) * 128 + y * 8 + (x >> 1);
    return (x & 1) ? (*t >> 4) : (*t & 0x0f);
}

typedef struct { int x0, x1, y0, y1; } clip_t;

/* pen 15 transparent; pen 14 = shadow when shadows enabled */
static inline void plot(int x, int y, int color, int pen, int shadows) {
    blit_stats.px_this_run++;
    if (pen == 15) return;
    uint16_t *d = &fb[y][x];
    if (pen == 14 && shadows) {
        /* MAME: shangha3 maps destination colours 0-127 to 128-255;
           everything else goes to the generic darkened bank. */
        if ((*d & 0x7ff) < 128 && !(*d & 0x800)) *d = *d + 128;
        else *d |= 0x800;
        return;
    }
    *d = (uint16_t)(((color & 0x7f) << 4) | pen);
}

/* Draw one 16x16 tile scaled by scalex/scaley (16.16 fixed point, 0x10000 = 1x).
   Same stepping as a typical scaled sprite renderer, so results match MAME. */
static void draw_tile_zoom(const clip_t *c, int code, int color, int flipx, int flipy,
                           int destx, int desty, uint32_t scalex, uint32_t scaley, int shadows) {
    uint32_t dstw = (uint32_t)(((uint64_t)scalex * 16 + 0x8000) >> 16);
    uint32_t dsth = (uint32_t)(((uint64_t)scaley * 16 + 0x8000) >> 16);
    if (dstw < 1 || dsth < 1) return;
    int32_t dx = (16 << 16) / dstw, dy = (16 << 16) / dsth;

    int32_t endx = destx + dstw - 1, endy = desty + dsth - 1;
    if (destx > c->x1 || endx < c->x0 || desty > c->y1 || endy < c->y0) return;
    int32_t srcx = 0, srcy = 0;
    if (destx < c->x0) { srcx = (c->x0 - destx) * dx; destx = c->x0; }
    if (endx > c->x1) endx = c->x1;
    if (desty < c->y0) { srcy = (c->y0 - desty) * dy; desty = c->y0; }
    if (endy > c->y1) endy = c->y1;
    if (flipx) { srcx = (int32_t)(dstw - 1) * dx - srcx; dx = -dx; }
    if (flipy) { srcy = (int32_t)(dsth - 1) * dy - srcy; dy = -dy; }

    for (int y = desty; y <= endy; y++, srcy += dy) {
        int32_t sx = srcx;
        for (int x = destx; x <= endx; x++, sx += dx)
            plot(x, y, color, tile_pixel(code, sx >> 16, srcy >> 16), shadows);
    }
}

/* Unscaled tile with pen 15 transparent and no shadows (used for tilemaps) */
static void draw_tile(const clip_t *c, int code, int color, int flipx, int flipy, int destx, int desty) {
    for (int ty = 0; ty < 16; ty++) {
        int y = desty + ty;
        if (y < c->y0 || y > c->y1) continue;
        for (int tx = 0; tx < 16; tx++) {
            int x = destx + tx;
            if (x < c->x0 || x > c->x1) continue;
            plot(x, y, color, tile_pixel(code, flipx ? 15 - tx : tx, flipy ? 15 - ty : ty), 0);
        }
    }
}

/* Process the command list. ram = the 32K-word work/graphics RAM at 300000. */
void blit_run(const uint16_t *ram, uint16_t gfxlist, int flip_screen, int shadows) {
    blit_stats.runs++;
    blit_stats.px_this_run = 0;
    blit_stats.cmds_this_run = 0;
    for (int offs = gfxlist << 3; offs < 0x8000; offs += 16) {
        const uint16_t *cmd = &ram[offs];
        int code  = cmd[1];
        int color = cmd[5] & 0x7f;
        int flipx = cmd[4] & 1, flipy = (cmd[4] >> 1) & 1;
        int sx = (cmd[2] & 0x1ff0) >> 4; if (sx >= 0x180) sx -= 0x200;
        int sy = (cmd[3] & 0x1ff0) >> 4; if (sy >= 0x100) sy -= 0x200;
        int sizex = cmd[6], sizey = cmd[7];
        int zoomx = cmd[10], zoomy = cmd[13];

        if (flip_screen) {
            sx = 383 - sx - sizex; sy = 255 - sy - sizey;
            flipx = !flipx; flipy = !flipy;
        }
        /* both sizes 0 = disabled; the range checks reject power-on garbage */
        if (!(sizex || sizey) || sizex >= 512 || sizey >= 256 || zoomx >= 0x1f0 || zoomy >= 0x1f0)
            continue;

        clip_t c = { sx, sx + sizex, sy, sy + sizey };
        if (c.x0 < 0) c.x0 = 0;
        if (c.y0 < 0) c.y0 = 0;
        if (c.x1 > FB_W - 1) c.x1 = FB_W - 1;
        if (c.y1 > FB_H - 1) c.y1 = FB_H - 1;
        if (c.x0 > c.x1 || c.y0 > c.y1) continue;

        blit_stats.cmds_this_run++;
        if (cmd[11] || cmd[12]) blit_stats.rotation++;

        if (cmd[4] & 0x08) {                       /* tilemap */
            blit_stats.tilemaps++;
            int condensed = cmd[4] & 0x04;
            int srcx = cmd[8] / 16, srcy = cmd[9] / 16;
            int dispx = srcx & 0x0f, dispy = srcy & 0x0f;
            int h = (sizey + 15) / 16 + 1, w = (sizex + 15) / 16 + 1;
            if (condensed) { h *= 2; w *= 2; srcx /= 8; srcy /= 8; blit_stats.condensed++; }
            else { srcx /= 16; srcy /= 16; }
            if (zoomx != 0x100 || zoomy != 0x100) blit_stats.tilemap_zoom++;

            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int addr, dx, dy;
                    if (condensed) {
                        addr = ((y + srcy) & 0x1f) | (((x + srcx) & 0xff) << 5);
                        dx = 8 * x * (0x200 - zoomx) / 0x100 - dispx;
                        dy = 8 * y * (0x200 - zoomy) / 0x100 - dispy;
                    } else {
                        addr = ((y + srcy) & 0x0f) | (((x + srcx) & 0xff) << 4) | (((y + srcy) & 0x10) << 8);
                        dx = 16 * x * (0x200 - zoomx) / 0x100 - dispx;
                        dy = 16 * y * (0x200 - zoomy) / 0x100 - dispy;
                    }
                    int tile = ram[addr & 0x7fff];
                    dx = flipx ? sx + sizex - 15 - dx : sx + dx;
                    dy = flipy ? sy + sizey - 15 - dy : sy + dy;
                    draw_tile(&c, (tile & 0x0fff) | (code & 0xf000), (tile >> 12) | (color & 0x70),
                              flipx, flipy, dx, dy);
                }
            }
        } else {                                   /* sprite */
            if (zoomx <= 1 && zoomy <= 1) {
                /* magnified 256x and clipped: in practice a rectangle fill */
                blit_stats.fills++;
                draw_tile_zoom(&c, code, color, flipx, flipy, sx, sy, 0x1000000, 0x1000000, shadows);
            } else {
                blit_stats.sprites++;
                if (zoomx != 0x100 || zoomy != 0x100) blit_stats.sprite_zoom++;
                int w = (sizex + 15) / 16;
                for (int x = 0; x < w; x++) {
                    draw_tile_zoom(&c, code, color, flipx, flipy, sx + 16 * x, sy,
                                   (0x200 - zoomx) * 0x100, (0x200 - zoomy) * 0x100, shadows);
                    if ((code & 0x000f) == 0x0f) code = (code + 0x100) & 0xfff0;
                    else code++;
                }
            }
        }
    }
    if (blit_stats.px_this_run > blit_stats.px_max_run) blit_stats.px_max_run = blit_stats.px_this_run;
    if (blit_stats.cmds_this_run > blit_stats.cmds_max_run) blit_stats.cmds_max_run = blit_stats.cmds_this_run;
}

/* Convert the visible area (384 x 224, lines 16..239) to 8-bit RGB.
   pal = 2048 palette words, RGBx_555 (R 15..11, G 10..6, B 5..1). */
void blit_render_rgb(const uint16_t *pal, uint8_t *rgb) {
    for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 384; x++) {
            uint16_t e = fb[y + 16][x];
            uint16_t p = pal[e & 0x7ff];
            int r = (p >> 11) & 0x1f, g = (p >> 6) & 0x1f, b = (p >> 1) & 0x1f;
            r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
            if (e & 0x800) { r = r * 6 / 10; g = g * 6 / 10; b = b * 6 / 10; }
            *rgb++ = r; *rgb++ = g; *rgb++ = b;
        }
    }
}

void blit_get_visible(uint16_t *out) {
    for (int y = 0; y < 224; y++)
        for (int x = 0; x < 384; x++)
            *out++ = fb[y + 16][x];
}
