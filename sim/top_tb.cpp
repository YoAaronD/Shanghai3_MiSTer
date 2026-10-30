// End-to-end simulation of shangha3_top: MiSTer-style ROM download into a
// pin-level SDRAM model, then the game boots from SDRAM. Video frames are
// captured as .ppm and audio as .wav.
//
// usage: Vshangha3_top --roms DIR --frames N [--frames-out DIR --every N]
//                      [--wav file] [--check-sdram]
//   DIR must hold the four MAME files: s3j_v11.ic3 s3j_v11.ic2
//   s3j_char-a1.ic43 s3j_v10.ic75 (streamed in that order, like the MRA)
#include "Vshangha3_top.h"
#if defined(Z80_PROBE) && !defined(OKI_PROBE) && !defined(DEBUG_CACHE)
#include "Vshangha3_top___024root.h"
#endif
#include "verilated.h"
#include "ddr_model.h"
#if defined(DEBUG_CACHE) || defined(OKI_PROBE)
#include "Vshangha3_top___024root.h"
#endif
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>
#include <unordered_map>

static std::vector<uint8_t> load(const std::string& p) {
    std::vector<uint8_t> d;
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) { perror(p.c_str()); exit(1); }
    fseek(f, 0, SEEK_END); d.resize(ftell(f)); fseek(f, 0, SEEK_SET);
    if (fread(d.data(), 1, d.size(), f) != d.size()) exit(1);
    fclose(f);
    return d;
}

// ---------------------------------------------------------------------------
// SDRAM chip model (IS42S16320-style, as driven by sdram.sv):
//   command pins are sampled once per cycle; READ returns a 4-word sequential
//   burst (wrapping inside the aligned group) starting 3 cycles later (CL=3
//   plus the controller's input register); WRITE stores one word with DQM.
// ---------------------------------------------------------------------------
struct SdramModel {
    std::vector<uint16_t> mem = std::vector<uint16_t>(1u << 25, 0);
    uint16_t open_row[4] = {0, 0, 0, 0};
    std::deque<std::pair<int, uint16_t>> pending;   // (cycles until driven, data)
    long reads = 0, writes = 0, refreshes = 0, mode_sets = 0;
    unsigned mode = 0;

    uint32_t index(int ba, uint16_t row, uint16_t col) {
        return ((uint32_t)ba << 23) | ((uint32_t)(row & 0x1fff) << 10) | (col & 0x3ff);
    }
    // call once per cycle after the clock edge; returns the DQ value to present
    uint16_t cycle(Vshangha3_top* t) {
        int cmd = (t->SDRAM_nRAS << 2) | (t->SDRAM_nCAS << 1) | t->SDRAM_nWE;
        if (!t->SDRAM_nCS) {
            int ba = t->SDRAM_BA;
            uint16_t a = t->SDRAM_A;
            switch (cmd) {
            case 0b011: open_row[ba] = a & 0x1fff; break;                       // ACTIVE
            case 0b101: {                                                       // READ
                uint16_t col = a & 0x3ff;
                for (int i = 0; i < 4; i++) {
                    uint16_t c = (col & ~3) | ((col + i) & 3);
                    pending.push_back({4 + i, mem[index(ba, open_row[ba], c)]});   // on the bus in cycles 3..6 after READ
                }
                reads++;
                break;
            }
            case 0b100: {                                                       // WRITE
                uint16_t col = a & 0x3ff;
                uint16_t& w = mem[index(ba, open_row[ba], col)];
                bool dqmh = (a >> 12) & 1, dqml = (a >> 11) & 1;
                uint16_t d = t->SDRAM_DQ_OUT;
                if (!t->SDRAM_DQ_OE) fprintf(stderr, "SDRAM model: WRITE without DQ driven\n");
                if (!dqmh) w = (w & 0x00ff) | (d & 0xff00);
                if (!dqml) w = (w & 0xff00) | (d & 0x00ff);
                writes++;
                break;
            }
            case 0b001: refreshes++; break;                                     // REFRESH
            case 0b000: mode = a; mode_sets++; break;                           // MODE
            default: break;                                                     // NOP/PRECHARGE
            }
        }
        // advance read pipeline: the entry reaching 0 is on the bus this cycle
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
    std::string roms, frames_out, wav_path, stream_path;
    int game = 0;
    int frames = 10, every = 30;
    bool check_sdram = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--roms") && i + 1 < argc) roms = argv[++i];
        else if (!strcmp(argv[i], "--stream") && i + 1 < argc) stream_path = argv[++i];
        else if (!strcmp(argv[i], "--game") && i + 1 < argc) game = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--frames-out") && i + 1 < argc) frames_out = argv[++i];
        else if (!strcmp(argv[i], "--every") && i + 1 < argc) every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--wav") && i + 1 < argc) wav_path = argv[++i];
        else if (!strcmp(argv[i], "--check-sdram")) check_sdram = true;
    }
    // The download stream, as the MRA builds it (scripts/mra_stream.py MRA ROMDIR OUT)
    std::vector<uint8_t> stream;
    if (stream_path.empty()) { fprintf(stderr, "need --stream <file> (scripts/mra_stream.py)\n"); return 1; }
    stream = load(stream_path);
    printf("ROM stream: %zu bytes\n", stream.size());

    auto* top = new Vshangha3_top;
    SdramModel sd;
    uint64_t cycle = 0;
    uint16_t dq_next = 0;

    // capture state
    std::vector<uint8_t> img(384 * 224 * 3, 0);
    std::vector<int16_t> audio;
    int vx = 0, vy = 0, prev_ce = 0, prev_hblank = 1, prev_vblank = 1, frame = 0;

    top->game_id = game;
    top->in_inputs = 0xffff;
    top->in_system = 0x7f;
    top->dsw1 = 0xff;
    top->dsw2 = 0xbf;
    top->ioctl_index = 0;

    DdrModel ddr;
    bool rot_on = false;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--rotate-traffic")) rot_on = true;
    uint32_t rot_rng = 99;
    long rot_sent = 0;
    std::unordered_map<uint32_t, uint64_t> rot_expect;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--ddr-easy")) ddr.stress = false;
    auto tick = [&]() {
        top->SDRAM_DQ_IN = dq_next;
        ddr.step(top);
        // second DDR3 master: screen_rotate-like single-beat writes, one per
        // visible pixel (as on HDMI with rotation on), random addresses in its area
        top->rot_we = 0;
        if (rot_on && top->ce_pix && !top->hblank && !top->vblank) {
            rot_rng = rot_rng * 1103515245u + 12345u;
            uint32_t a = DdrModel::ROT_BASE + ((rot_rng >> 8) % 0x20000);
            uint64_t d = ((uint64_t)(rot_rng ^ 0x5a5a5a5a) << 32) | (rot_rng ^ 0xa5a5a5a5);
            uint32_t px = (uint32_t)d;
            uint8_t be = (rot_rng >> 3 & 1) ? 0xF0 : 0x0F;
            top->rot_we = 1; top->rot_addr = a; top->rot_din = ((uint64_t)px << 32) | px; top->rot_be = be;
            rot_expect[a] = DdrModel::merge(rot_expect[a], ((uint64_t)px << 32) | px, be);
            rot_sent++;
        }
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycle++;
        dq_next = sd.cycle(top);
        // video
        if (prev_ce) {
            if (!top->hblank && !top->vblank) {
                if (vx < 384 && vy < 224) {
                    uint8_t* px = &img[(vy * 384 + vx) * 3];
                    px[0] = top->red; px[1] = top->green; px[2] = top->blue;
                }
                vx++;
            }
            if (top->hblank && !prev_hblank) { if (!top->vblank) vy++; vx = 0; }
            if (top->vblank) vy = 0;
            prev_hblank = top->hblank;
        }
        prev_ce = top->ce_pix;
    };

    // power-up: SDRAM init held while the "PLL locks", then controller startup
    top->reset = 1;
    top->sdram_init = 1;
    for (int i = 0; i < 100; i++) tick();
    top->sdram_init = 0;
    for (int i = 0; i < 14000; i++) tick();

    // ROM download, paced like hps_io: write strobe, then honour ioctl_wait
    top->ioctl_download = 1;
    for (int i = 0; i < 16; i++) tick();
    uint64_t dl_start = cycle;
    for (size_t a = 0; a < stream.size(); a++) {
        top->ioctl_addr = a;
        top->ioctl_dout = stream[a];
        top->ioctl_wr = 1;
        tick();
        top->ioctl_wr = 0;
        tick(); tick();
        while (top->ioctl_wait) tick();
    }
    for (int i = 0; i < 16; i++) tick();
    top->ioctl_download = 0;
    printf("download: %zu bytes in %.1f ms (simulated), %ld SDRAM writes, mode register %03X\n",
           stream.size(), (cycle - dl_start) / 96000.0, sd.writes, sd.mode);

    // optional: verify SDRAM contents against the expected layout
    if (check_sdram) {
        auto word = [&](uint32_t byte_addr) {
            uint32_t w = byte_addr >> 1;                  // controller word address [25:1]
            int ba = (w >> 22) & 3; uint16_t row = (w >> 9) & 0x1fff;
            uint16_t col = ((w >> 24) & 1) << 9 | (w & 0x1ff);
            return sd.mem[sd.index(ba, row, col)];
        };
        long bad = 0;
        for (uint32_t i = 0; i < 0x80000; i++) {          // program: {even EPROM, odd EPROM}
            uint16_t exp = (stream[i] << 8) | stream[0x80000 + i];
            if (word(i * 2) != exp && bad++ < 5) printf("  prog word %05X: %04X != %04X\n", i, word(i * 2), exp);
        }
        for (uint32_t b = 0x100000; b < 0x510000; b += 2) { // Z80, graphics, samples: little-endian words
            uint16_t exp = stream[b] | (stream[b + 1] << 8);
            if (word(b) != exp && bad++ < 10) printf("  byte %06X: %04X != %04X\n", b, word(b), exp);
        }
        printf("SDRAM content check: %s (%ld mismatches)\n", bad ? "FAIL" : "ok", bad);
    }

    // run the game
    top->reset = 0;
#ifdef DEBUG_CACHE
    for (int i = 0; i < 4000; i++) {
        tick();
        auto* r = top->rootp;
        printf("%3d cs=%d addr=%05X ok=%d data=%04X fill=%d ch2req=%d ch2rdy=%d inv=%d brst=%d\n", i,
            r->shangha3_top__DOT__prog_cs, r->shangha3_top__DOT__prog_addr << 1, r->shangha3_top__DOT__prog_ok,
            r->shangha3_top__DOT__prog_data, r->shangha3_top__DOT__u_mem__DOT__fill_busy,
            r->shangha3_top__DOT__ch2_req, r->shangha3_top__DOT__ch2_ready,
            r->shangha3_top__DOT__u_mem__DOT__inv_busy, r->shangha3_top__DOT__board_reset);
    }
    return 0;
#endif
    uint64_t run_start = cycle;
    while (frame < frames) {
        tick();
        if (!wav_path.empty() && cycle % 2000 == 0) audio.push_back((int16_t)top->snd);
#ifdef OKI_PROBE
        {   // count OKI output samples that are non-zero, and OKI ROM reads served by SDRAM
            static long nz = 0, okireads = 0; static int last_ok = 0;
            auto* r = top->rootp;
            if (cycle % 2000 == 0 && (int16_t)(r->shangha3_top__DOT__u_board__DOT__oki_snd << 2) != 0) nz++;
            int ok = r->shangha3_top__DOT__oki_rom_ok;
            if (ok && !last_ok) okireads++;
            last_ok = ok;
            if (top->vblank && !prev_vblank && (frame + 1) % 100 == 0)
                printf("frame %d: OKI ROM bytes read %ld, non-zero OKI output samples %ld\n", frame + 1, okireads, nz);
        }
#endif
#ifdef Z80_PROBE
        {   // heberpop/blocken: log every Z80 I/O write (port, data), for comparing with MAME's sound_log
            static FILE* zl = fopen("z80_io_top.txt", "w");
            static int last = 0;
            auto* r = top->rootp;
            int w = r->shangha3_top__DOT__u_board__DOT__u_snd__DOT__io_wr_d;
            if (w && !last) fprintf(zl, "%02X %02X\n", r->shangha3_top__DOT__u_board__DOT__u_snd__DOT__A & 0xff,
                                    r->shangha3_top__DOT__u_board__DOT__u_snd__DOT__z_dout);
            last = w;
        }
#endif
        if (top->vblank && !prev_vblank) {
            frame++;
            if (!frames_out.empty() && frame % every == 0) {
                char path[512];
                snprintf(path, sizeof path, "%s/frame_%05d.ppm", frames_out.c_str(), frame);
                if (FILE* o = fopen(path, "wb")) {
                    fprintf(o, "P6\n384 224\n255\n");
                    fwrite(img.data(), 1, img.size(), o);
                    fclose(o);
                }
            }
        }
        prev_vblank = top->vblank;
    }
    printf("DDR3 frame buffer: %ld words written, %ld read, %ld bad addresses\n", ddr.words_written, ddr.words_read, ddr.errors);
    if (rot_on) {
        long bad = 0;
        for (auto& kv : rot_expect) if (ddr.rot[kv.first] != kv.second) bad++;
        printf("DDR3 second master: %ld writes sent, %ld arrived, %zu addresses, %ld wrong%s\n",
               rot_sent, ddr.rot_writes, rot_expect.size(), bad, (bad || ddr.rot_writes != rot_sent) ? "  FAIL" : "  ok");
    }
    printf("ran %d frames from SDRAM (%.1f ms); SDRAM reads %ld, refreshes %ld\n",
           frames, (cycle - run_start) / 96000.0, sd.reads, sd.refreshes);

    if (!wav_path.empty()) {
        FILE* w = fopen(wav_path.c_str(), "wb");
        uint32_t data_bytes = audio.size() * 2, rate = 48000, byte_rate = rate * 2, riff = 36 + data_bytes, fl = 16;
        uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
        fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w); fwrite(&fl, 4, 1, w);
        fwrite(&pcm, 2, 1, w); fwrite(&ch, 2, 1, w); fwrite(&rate, 4, 1, w); fwrite(&byte_rate, 4, 1, w);
        fwrite(&align, 2, 1, w); fwrite(&bits, 2, 1, w); fwrite("data", 1, 4, w); fwrite(&data_bytes, 4, 1, w);
        fwrite(audio.data(), 2, audio.size(), w);
        fclose(w);
    }
    delete top;
    return 0;
}
