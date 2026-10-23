// Replays a sound-register log through the core's YM2149 + OKI and writes
// the two sources separately, so the mix can be studied offline.
//   snd_tb LOG OKIROM OUT.raw
// LOG lines: "<seconds> AYA|AYD|OKI <hex byte>" (tools/mame snd_log format).
// OUT.raw: float32 frames at 48 kHz: psg_snd (raw 0..1023), oki_snd (signed),
// snd (the RTL mixer's output, shangha3_mixer.sv). OUT.wav (if given): snd.
// Build and run with scripts/snd_replay.sh.
#include "Vsnd_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
struct Ev { double t; int kind; int v; };
int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage: snd_tb LOG OKIROM OUT.raw [OUT.wav]\n"); return 1; }
    std::vector<Ev> ev;
    FILE* f = fopen(argv[1], "r"); char kind[16]; double t; unsigned v;
    char line[256];
    while (fgets(line, sizeof line, f))
        if (sscanf(line, "%lf %15s %x", &t, kind, &v) == 3) {
            int k = !strcmp(kind, "AYA") ? 0 : !strcmp(kind, "AYD") ? 1 : !strcmp(kind, "OKI") ? 2 : -1;
            if (k >= 0) ev.push_back({t, k, (int)v});
        }
    fclose(f);
    std::vector<uint8_t> rom(0x40000, 0);
    f = fopen(argv[2], "rb"); fread(rom.data(), 1, rom.size(), f); fclose(f);
    FILE* out = fopen(argv[3], "wb");
    double t_end = ev.empty() ? 0 : ev.back().t + 1.0;
    Vsnd_top* top = new Vsnd_top;
    const double CLK = 96e6;
    uint64_t cyc = 0, end = (uint64_t)(t_end * CLK);
    size_t ei = 0; int busy = 0, phase = 0;   // write in progress: busy clocks left
    int psg_div = 0, oki_acc = 0, okiwait = 0; uint32_t okilast = 0xffffffff;
    std::vector<int16_t> wav;
    top->balance = getenv("SND_BALANCE") ? atoi(getenv("SND_BALANCE")) : 0;   // mixer balance setting
    top->reset = 1;
    for (int i = 0; i < 100; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
    top->reset = 0;
    for (; cyc < end; cyc++) {
        // clock enables, as in shangha3_board.sv
        top->ce_psg = (psg_div == 63);
        psg_div = (psg_div + 1) & 63;
        if (oki_acc + 11 >= 1000) { oki_acc += 11 - 1000; top->ce_oki = 1; } else { oki_acc += 11; top->ce_oki = 0; }
        // bus: each write holds for 24 clocks (one 68000 bus cycle), then idles 24
        if (busy == 0 && ei < ev.size() && ev[ei].t * CLK <= cyc) { busy = 48; phase = ev[ei].kind; top->din = ev[ei].v; ei++; }
        bool act = busy > 24;
        top->ay_bdir = act && phase < 2;
        top->ay_bc1  = act && phase == 0;
        top->oki_wrn = !(act && phase == 2);
        if (busy) busy--;
        // OKI ROM: data valid 2 clocks after the address changes
        if (top->oki_rom_addr != okilast) { okilast = top->oki_rom_addr; okiwait = 2; top->oki_rom_ok = 0; }
        else if (okiwait > 0 && --okiwait == 0) { top->oki_rom_data = rom[okilast & 0x3ffff]; top->oki_rom_ok = 1; }
        top->clk = 0; top->eval(); top->clk = 1; top->eval();
        if (cyc % 2000 == 0) {
            float fr[3] = { (float)top->psg_snd, (float)(int16_t)(top->oki_snd << 2) / 4.0f, (float)(int16_t)top->snd };
            fwrite(fr, 4, 3, out);
            wav.push_back((int16_t)top->snd);
        }
    }
    fclose(out);
    if (argc > 4) {
        FILE* w = fopen(argv[4], "wb");
        uint32_t db = wav.size() * 2, rate = 48000, br = rate * 2, riff = 36 + db, fl = 16;
        uint16_t pcm = 1, ch = 1, al = 2, bits = 16;
        fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w);
        fwrite(&fl, 4, 1, w); fwrite(&pcm, 2, 1, w); fwrite(&ch, 2, 1, w);
        fwrite(&rate, 4, 1, w); fwrite(&br, 4, 1, w); fwrite(&al, 2, 1, w); fwrite(&bits, 2, 1, w);
        fwrite("data", 1, 4, w); fwrite(&db, 4, 1, w); fwrite(wav.data(), 2, wav.size(), w); fclose(w);
    }
    printf("replayed %zu writes, %.1f s\n", ev.size(), t_end);
    delete top; return 0;
}
