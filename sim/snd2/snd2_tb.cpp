// Replays MAME's heberpop/blocken sound log (tools/mame/sound_log.lua:
// "<t> Z80W <port> <data>", "<t> COIN <data>") through jt12 + jt6295 +
// ga9201_mixer, for comparing with MAME's -wavwrite output.
//   snd2_tb LOG OKIROM GAME OUT.raw [OUT.wav]      GAME: 1 heberpop, 2 blocken
// OUT.raw: float32 x4 per 48 kHz sample: fm_left, fm_right, oki, snd.
#include "Vsnd2_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
struct Ev { double t; int kind; int port; int v; };   // kind 0 Z80W, 1 COIN
int main(int argc, char** argv) {
    if (argc < 5) { fprintf(stderr, "usage: snd2_tb LOG OKIROM GAME OUT.raw [OUT.wav]\n"); return 1; }
    std::vector<Ev> ev;
    FILE* f = fopen(argv[1], "r"); char line[256], kind[16]; double t; unsigned a, b;
    while (fgets(line, sizeof line, f)) {
        int n = sscanf(line, "%lf %15s %x %x", &t, kind, &a, &b);
        if (n == 4 && !strcmp(kind, "Z80W")) ev.push_back({t, 0, (int)a, (int)b});
        else if (n >= 3 && !strcmp(kind, "COIN")) ev.push_back({t, 1, 0, (int)a});
    }
    fclose(f);
    std::vector<uint8_t> rom(0x80000, 0);
    f = fopen(argv[2], "rb"); fread(rom.data(), 1, rom.size(), f); fclose(f);
    int game = atoi(argv[3]);
    FILE* out = fopen(argv[4], "wb");
    double t_end = ev.empty() ? 0 : ev.back().t + 1.0;
    if (getenv("SND_SECONDS")) t_end = atof(getenv("SND_SECONDS"));
    auto* top = new Vsnd2_top;
    const double CLK = 96e6;
    uint64_t end = (uint64_t)(t_end * CLK);
    size_t ei = 0; int busy = 0, okiwait = 0, ymdiv = 0, oki_acc = 0, coin = 0, isoki = 0;
    uint32_t okilast = 0xffffffff;
    std::vector<int16_t> wav;
    top->balance = getenv("SND_BALANCE") ? atoi(getenv("SND_BALANCE")) : 0;
    top->oki_wrn = 1;
    top->reset = 1;
    for (int i = 0; i < 2000; i++) { top->ce_ym = (i % 12) == 11; top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
    top->reset = 0;
    for (uint64_t cyc = 0; cyc < end; cyc++) {
        top->ce_ym = (ymdiv == 11); ymdiv = (ymdiv + 1) % 12;
        if (oki_acc + 11 >= 1000) { oki_acc += 11 - 1000; top->ce_oki = 1; } else { oki_acc += 11; top->ce_oki = 0; }
        top->ym_wr = 0;
        if (busy == 0) {
            while (ei < ev.size() && ev[ei].t * CLK <= cyc && ev[ei].kind == 1) { coin = ev[ei].v; ei++; }
            if (ei < ev.size() && ev[ei].t * CLK <= cyc && ev[ei].kind == 0) {
                const Ev& e = ev[ei++];
                top->din = e.v;
                if (e.port <= 3) { top->ym_addr = e.port; top->ym_wr = 1; busy = 64; isoki = 0; }
                else if (e.port == 0x80) { isoki = 1; busy = 64; }
                else busy = 1;
            }
        }
        top->oki_wrn = !(isoki && busy > 32);
        if (busy) { busy--; if (!busy) isoki = 0; }
        // OKI ROM through the board's bank logic
        uint32_t ca = top->oki_rom_addr, ra;
        if (game == 1)                    ra = ((coin >> 3) & 1) << 18 | ca;
        else if (game == 2 && (ca >> 17)) ra = ((coin >> 4) & 3) << 17 | (ca & 0x1ffff);
        else                              ra = ca;
        if (ra != okilast) { okilast = ra; okiwait = 2; top->oki_rom_ok = 0; }
        else if (okiwait > 0 && --okiwait == 0) { top->oki_rom_data = rom[okilast & 0x7ffff]; top->oki_rom_ok = 1; }
        top->clk = 0; top->eval(); top->clk = 1; top->eval();
        if (cyc % 2000 == 0) {
            float fr[4] = { (float)(int16_t)top->fm_left, (float)(int16_t)top->fm_right,
                            (float)(int16_t)(top->oki_snd << 2) / 4.0f, (float)(int16_t)top->snd };
            fwrite(fr, 4, 4, out);
            wav.push_back((int16_t)top->snd);
        }
    }
    fclose(out);
    if (argc > 5) {
        FILE* w = fopen(argv[5], "wb");
        uint32_t data_bytes = wav.size() * 2, rate = 48000, byte_rate = rate * 2, riff = 36 + data_bytes, fmt_len = 16;
        uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
        fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w);
        fwrite(&fmt_len, 4, 1, w); fwrite(&pcm, 2, 1, w); fwrite(&ch, 2, 1, w);
        fwrite(&rate, 4, 1, w); fwrite(&byte_rate, 4, 1, w); fwrite(&align, 2, 1, w); fwrite(&bits, 2, 1, w);
        fwrite("data", 1, 4, w); fwrite(&data_bytes, 4, 1, w); fwrite(wav.data(), 2, wav.size(), w); fclose(w);
    }
    printf("replayed %zu events, %.1f s\n", ev.size(), t_end);
    delete top;
    return 0;
}
