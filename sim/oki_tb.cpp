// OKI-through-SDRAM check (see oki_bench.sv).
// Downloads the OKI ROM into SDRAM the way the MiSTer does, then plays every
// valid phrase in the ROM, four at a time on the four channels, on two jt6295s:
// one reading through shangha3_mem + sdram.sv + an SDRAM pin model, one reading
// the ROM image directly. Both must produce identical samples. Background
// SDRAM traffic (CPU cache misses, blitter rows) is generated at the same time.
//
// usage: Voki_bench --oki oki.bin [--no-stress] [--wav out.wav]
#include "Voki_bench.h"
#include "verilated.h"
#include "Voki_bench___024root.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

struct SdramModel {                       // same model as sim/top_tb.cpp
    std::vector<uint16_t> mem = std::vector<uint16_t>(1u << 25, 0);
    uint16_t open_row[4] = {0, 0, 0, 0};
    std::deque<std::pair<int, uint16_t>> pending;
    uint32_t index(int ba, uint16_t row, uint16_t col) {
        return ((uint32_t)ba << 23) | ((uint32_t)(row & 0x1fff) << 10) | (col & 0x3ff);
    }
    uint16_t cycle(Voki_bench* t) {
        int cmd = (t->SDRAM_nRAS << 2) | (t->SDRAM_nCAS << 1) | t->SDRAM_nWE;
        if (!t->SDRAM_nCS) {
            int ba = t->SDRAM_BA; uint16_t a = t->SDRAM_A;
            if (cmd == 0b011) open_row[ba] = a & 0x1fff;
            else if (cmd == 0b101) {
                uint16_t col = a & 0x3ff;
                for (int i = 0; i < 4; i++)
                    pending.push_back({4 + i, mem[index(ba, open_row[ba], (col & ~3) | ((col + i) & 3))]});
            } else if (cmd == 0b100) {
                uint16_t& w = mem[index(ba, open_row[ba], a & 0x3ff)];
                uint16_t d = t->SDRAM_DQ_OUT;
                if (!((a >> 12) & 1)) w = (w & 0x00ff) | (d & 0xff00);
                if (!((a >> 11) & 1)) w = (w & 0xff00) | (d & 0x00ff);
            }
        }
        uint16_t dq = 0;
        for (auto& p : pending) p.first--;
        while (!pending.empty() && pending.front().first <= 0) {
            if (pending.front().first == 0) dq = pending.front().second;
            pending.pop_front();
        }
        return dq;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string oki_path, wav_path;
    bool stress = true;
    size_t max_phrases = 1000;
    int write_gap = 200;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--oki") && i + 1 < argc) oki_path = argv[++i];
        else if (!strcmp(argv[i], "--wav") && i + 1 < argc) wav_path = argv[++i];
        else if (!strcmp(argv[i], "--no-stress")) stress = false;
        else if (!strcmp(argv[i], "--max") && i + 1 < argc) max_phrases = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--gap") && i + 1 < argc) write_gap = atoi(argv[++i]);
    }
    std::vector<uint8_t> rom(0x80000, 0);   // up to 512 KB (heberpop/blocken); sized to the file below
    FILE* f = fopen(oki_path.c_str(), "rb");
    if (!f) { perror(oki_path.c_str()); return 1; }
    size_t n = fread(rom.data(), 1, rom.size(), f); fclose(f);
    rom.resize(n);

    auto* t = new Voki_bench;
    SdramModel sd;
    uint64_t cycle = 0;
    uint16_t dq_next = 0;
    uint32_t b_last = 0xffffffff; int b_wait = 0;
    uint32_t rng = 12345;
    auto rnd = [&]() { rng = rng * 1103515245u + 12345u; return rng >> 8; };
    int prog_timer = 0;
    long gfx_rows = 0, prog_misses = 0;

    long samples = 0, nonzero = 0, mismatches = 0, status_mismatch = 0, status_1sample = 0;
    std::vector<int16_t> wav;
    bool comparing = false;

    auto tick = [&]() {
        t->SDRAM_DQ_IN = dq_next;
        t->clk = 0; t->eval(); t->clk = 1; t->eval();
        cycle++;
        dq_next = sd.cycle(t);
        // direct ROM for oki_b: data 2 clocks after an address change
        if (t->rom_b_addr != b_last) { b_last = t->rom_b_addr; b_wait = 2; t->rom_b_ok = 0; }
        else if (b_wait > 0 && --b_wait == 0) { t->rom_b_data = rom[b_last % rom.size()]; t->rom_b_ok = 1; }
        // background traffic
        if (stress && t->mem_ready && !t->ioctl_download) {
            if (t->gfx_ack) { t->gfx_addr = rnd() % 0x70000; gfx_rows++; }
            t->gfx_req = 1;
            if (++prog_timer >= 24) {            // a new 68000 bus cycle every 24 clocks, random address
                prog_timer = 0;
                if (!t->prog_ok) prog_misses++;
                t->prog_addr = rnd() & 0x3ffff;
                t->prog_cs = 1;
            }
        } else { t->gfx_req = 0; t->prog_cs = 0; }
        {   // probe the SDRAM-fed ROM port: ok must only be high with the right byte
            auto* r = t->rootp;
            static long bad_ok = 0, ok_cycles = 0;
            uint32_t a = r->oki_bench__DOT__rom_a_addr | (t->oki_bank << 18); uint8_t d = r->oki_bench__DOT__rom_a_data;
            static uint32_t prev_a = 0xffffffff; bool stable = (a == prev_a); prev_a = a;
            if (r->oki_bench__DOT__rom_a_ok && stable) { ok_cycles++; if (d != rom[a % rom.size()]) { if (bad_ok < 5) printf("  cycle %llu: ok with addr %05X data %02X, rom has %02X\n", (unsigned long long)cycle, a, d, rom[a % rom.size()]); bad_ok++; } }
            if (cycle % 50000000 == 0 && comparing) printf("  [%llu] ok cycles %ld, bad %ld\n", (unsigned long long)cycle, ok_cycles, bad_ok);
        }
        if (comparing && t->ce_oki) {
            samples++;
            if (t->snd_a != 0 || t->snd_b != 0) nonzero++;
            if (t->snd_a != t->snd_b) { if (mismatches < 5) printf("  sample %ld: sdram %d, direct %d\n", samples, (int16_t)(t->snd_a << 2) >> 2, (int16_t)(t->snd_b << 2) >> 2); mismatches++; }
            // busy flags: the SDRAM path may start a channel one sample later than a
            // direct ROM (the phrase-table copy answers in 3-4 clocks instead of 2,
            // which can cross an OKI clock edge). Count only differences that last
            // more than one sample.
            {   static int run = 0;
                if ((t->oki_dout_a & 0xf) != (t->oki_dout_b & 0xf)) {
                    if (++run == 2) { if (status_mismatch < 3) printf("  status differs from sample %ld (cycle %llu): sdram %X direct %X\n", samples - 1, (unsigned long long)cycle, t->oki_dout_a & 0xf, t->oki_dout_b & 0xf); status_mismatch++; }
                    else if (run == 1) status_1sample++;
                } else run = 0;
            }
            if (!wav_path.empty() && samples % 132 == 0) wav.push_back((int16_t)(t->snd_a << 2));
        }
    };

    t->oki_wrn = 1;
    t->reset = 1; t->sdram_init = 1;
    for (int i = 0; i < 100; i++) tick();
    t->sdram_init = 0;
    for (int i = 0; i < 14000; i++) tick();

    // download only the OKI region of the MRA stream (offset 0x490000)
    t->ioctl_download = 1;
    for (int i = 0; i < 16; i++) tick();
    for (size_t a = 0; a < n; a++) {
        t->ioctl_addr = 0x490000 + a; t->ioctl_dout = rom[a]; t->ioctl_wr = 1;
        tick(); t->ioctl_wr = 0; tick(); tick();
        while (t->ioctl_wait) tick();
    }
    for (int i = 0; i < 16; i++) tick();
    t->ioctl_download = 0;
    t->reset = 0;
    for (int i = 0; i < 2000; i++) tick();
    printf("downloaded %zu sample bytes into SDRAM\n", n);

    auto write = [&](uint8_t v) {
        t->oki_din = v; t->oki_wrn = 0;
        for (int i = 0; i < 8; i++) tick();
        t->oki_wrn = 1;
        for (int i = 0; i < write_gap; i++) tick();   // clocks between CPU writes
    };

    // valid phrases from the ROM's phrase table; with a 512 KB ROM (heberpop),
    // both 256 KB banks (the bank switch is exercised between phrase groups,
    // and bank 1 has its own phrase table at 40000)
    int nbanks = n > 0x40000 ? 2 : 1;
    comparing = true;
    int timeouts = 0;
    size_t total = 0;
    for (int bank = 0; bank < nbanks; bank++) {
        t->oki_bank = bank;
        for (int i = 0; i < 200; i++) tick();
        const uint8_t* base = &rom[bank * 0x40000];
        std::vector<int> phrases;
        for (int p = 1; p < 128; p++) {
            const uint8_t* e = &base[p * 8];
            uint32_t s = ((e[0] << 16) | (e[1] << 8) | e[2]) & 0x3ffff, en = ((e[3] << 16) | (e[4] << 8) | e[5]) & 0x3ffff;
            if (s < en && en < 0x40000 && phrases.size() < max_phrases) phrases.push_back(p);
        }
        printf("bank %d: playing %zu phrases, 4 channels at a time, %s background SDRAM traffic\n",
               bank, phrases.size(), stress ? "with" : "without");
        total += phrases.size();
        for (size_t i = 0; i < phrases.size(); i += 4) {
            for (size_t k = 0; k < 4 && i + k < phrases.size(); k++) {
                write(0x80 | phrases[i + k]);
                write((0x10 << k) | 0x0);             // channel k, no attenuation
            }
            uint64_t start = cycle;
            while (((t->oki_dout_a | t->oki_dout_b) & 0xf) && cycle - start < 96000000ull * 3) tick();
            if (cycle - start >= 96000000ull * 3) timeouts++;
            for (int j = 0; j < 20000; j++) tick();
        }
    }
    comparing = false;

    printf("compared %ld output samples (%.1f s), %ld non-zero\n", samples, samples / 1056000.0, nonzero);
    printf("background traffic: %ld blitter rows, %ld CPU bus cycles that missed the cache\n", gfx_rows, prog_misses);
    printf("output mismatches: %ld, busy-flag mismatches: %ld (plus %ld one-sample start delays), timeouts: %d\n", mismatches, status_mismatch, status_1sample, timeouts);

    if (!wav_path.empty()) {
        FILE* w = fopen(wav_path.c_str(), "wb");
        uint32_t db = wav.size() * 2, rate = 8000, br = 16000, riff = 36 + db, fl = 16;
        uint16_t pcm = 1, ch = 1, al = 2, bits = 16;
        fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w); fwrite(&fl, 4, 1, w);
        fwrite(&pcm, 2, 1, w); fwrite(&ch, 2, 1, w); fwrite(&rate, 4, 1, w); fwrite(&br, 4, 1, w);
        fwrite(&al, 2, 1, w); fwrite(&bits, 2, 1, w); fwrite("data", 1, 4, w); fwrite(&db, 4, 1, w);
        fwrite(wav.data(), 2, wav.size(), w); fclose(w);
    }
    bool pass = mismatches == 0 && status_mismatch == 0 && timeouts == 0 && nonzero > 0;
    printf("%s\n", pass ? "PASS" : "FAIL");
    delete t;
    return pass ? 0 : 1;
}
