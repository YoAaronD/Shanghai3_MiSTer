// Drives osd_top like Main_MiSTer drawing an info box ("Loading ..."), then
// counts the OSD text pixels and saves the frame as a PPM.
//   osd_tb OUT.ppm CRT_ON HSIZE HPOS VSHIFT [INFOX INFOY INFOW_CHARS INFOH_ROWS]
#include "Vosd_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
static Vosd_top* t;
static void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }
static void spi_word(uint16_t w) {             // one io_strobe pulse with data
    t->io_din = w; t->io_strobe = 1; for (int i = 0; i < 4; i++) tick();
    t->io_strobe = 0; for (int i = 0; i < 4; i++) tick();
}
static void spi_cmd(uint8_t cmd, const std::vector<uint16_t>& data) {
    t->io_osd = 1; tick(); spi_word(cmd);
    for (auto d : data) spi_word(d);
    t->io_osd = 0; for (int i = 0; i < 8; i++) tick();
}
int main(int argc, char** argv) {
    if (argc < 6) { fprintf(stderr, "usage\n"); return 1; }
    t = new Vosd_top;
    t->crt_on = atoi(argv[2]); t->crt_hsize = atoi(argv[3]) & 31; t->crt_hpos = atoi(argv[4]) & 15; t->crt_vshift = atoi(argv[5]) & 15;
    int ix = argc > 6 ? atoi(argv[6]) : 32, iy = argc > 7 ? atoi(argv[7]) : 80;
    int iw = argc > 8 ? atoi(argv[8]) : 24, ih = argc > 9 ? atoi(argv[9]) : 4;   // in 8-pixel units
    t->reset = 1; for (int i = 0; i < 100; i++) tick(); t->reset = 0;
    // OSD buffer: each row is 256 bytes, one byte = 8 vertical pixels of one column.
    // Fill every row with a checker of "character" columns so text pixels are obvious.
    for (int row = 0; row < 8; row++) {
        std::vector<uint16_t> d(256);
        for (int c = 0; c < 256; c++) d[c] = ((c / 8) & 1) ? 0x7E : 0x00;
        spi_cmd(0x20 | row, d);
    }
    // enable in info mode: 0x40 | enable | info, then x, y, w/8, h/8, rotation
    spi_cmd(0x45, { (uint16_t)ix, (uint16_t)iy, (uint16_t)iw, (uint16_t)ih, 0 });
    // run 6 frames, measure the last
    const long FRAME = 512L * 263 * 12;
    long text = 0, box = 0;
    std::vector<uint8_t> img(512 * 263 * 3, 0);
    int x = 0, y = 0, prev_hs = 0, prev_vs = 0;
    long derun = 0, demax = 0, ndeedge = 0; int prev_de = 0;
    for (long c = 0; c < 6 * FRAME; c++) {
        tick();
        if (t->de_out) derun++; else { if (prev_de && c >= 5 * FRAME) { if (derun > demax) demax = derun; ndeedge++; } derun = 0; }
        prev_de = t->de_out;
        { static long br = 0, bmax = 0, lines = 0; uint32_t p = t->dout; bool b = (p >> 21) & 1; if (c >= 5 * FRAME) { if (b) br++; else { if (br) { if (br > bmax) bmax = br; lines++; } br = 0; } } if (c == 6 * FRAME - 1) printf("box runs: %ld, longest %ld clocks\n", lines, bmax); }
        bool last = c >= 5 * FRAME;
        if (t->hs_out && !prev_hs) { x = 0; y++; }
        if (t->vs_out && !prev_vs) { y = 0; }
        prev_hs = t->hs_out; prev_vs = t->vs_out;
        if (t->ce_vid) {
            if (last && t->de_out) {
                uint32_t p = t->dout;
                bool txt = ((p >> 22) & 3) == 3 && ((p >> 14) & 3) == 3 && ((p >> 6) & 3) == 3;
                bool bx = ((p >> 21) & 1) || ((p >> 13) & 1) || ((p >> 5) & 1);   // OSD_COLOR bits (background)
                text += txt; box += bx || txt;
                if (x < 512 && y < 263) { uint8_t* q = &img[(y * 512 + x) * 3]; q[0] = p >> 16; q[1] = p >> 8; q[2] = p; }
            }
            x++;
        }
    }
    FILE* f = fopen(argv[1], "wb"); fprintf(f, "P6 512 263 255\n"); fwrite(img.data(), 1, img.size(), f); fclose(f);
    printf("DE: longest run %ld clocks, %ld DE pulses in the last frame\n", demax, ndeedge);
    printf("crt_on=%d hsize=%d hpos=%d vshift=%d: box pixels %ld, text pixels %ld\n", t->crt_on, t->crt_hsize, t->crt_hpos, t->crt_vshift, box, text);
    delete t; return 0;
}
