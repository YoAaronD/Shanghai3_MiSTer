#ifndef BLITTER_H
#define BLITTER_H
#include <stdint.h>

typedef struct {
    long runs, sprites, fills, tilemaps, condensed;
    long sprite_zoom, tilemap_zoom, rotation;
    long px_this_run, px_max_run, cmds_this_run, cmds_max_run;   /* pixels visited (incl. transparent) */
} blit_stats_t;

extern blit_stats_t blit_stats;

void blit_init(const uint8_t *gfxrom, int gfxsize);
void blit_run(const uint16_t *ram, uint16_t gfxlist, int flip_screen, int shadows);
void blit_get_visible(uint16_t *out);                       /* 384*224 entries */
void blit_render_rgb(const uint16_t *pal, uint8_t *rgb);   /* 384*224*3 bytes */

#endif
