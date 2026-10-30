// Verilator testbench for shangha3_board
//
// Loads a 512 KB program ROM image (big-endian 16-bit words, i.e. the two
// interleaved EPROMs already merged), runs N video frames and writes a bus
// trace that can be compared against MAME.
//
// usage: Vshangha3_board --prog rom.bin [--frames N] [--trace out.txt] [--dsw1 hex] [--dsw2 hex]
//          [--gfx blitter.bin] [--frames-out DIR --every N]   (video output captured as .ppm)

#include "Vshangha3_board.h"
#include "verilated.h"
#include "ddr_model.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::string prog_path, trace_path = "trace.txt";
    int frames = 3;
    unsigned dsw1 = 0xff, dsw2 = 0xbf;   // MAME defaults (DSW2 bit 6 = 0: demo sounds on)
    bool dsw_given = false;
    bool log_rom = true;     // --no-rom-log: skip program ROM reads (opcode fetches) in the trace
    int log_from = 0;        // --log-from N: only trace bus cycles from frame N on
    std::string gfx_path, frames_out, oki_path, wav_path, z80_path;
    int game = 0;            // --game N: 0 shangha3j, 1 heberpop, 2 blocken
    int pause_from = -1, pause_len = 0;   // --pause FROM LEN: hold the pause input for LEN frames from frame FROM
    struct Press { unsigned mask; int from, len; bool sys; };
    std::vector<Press> presses;           // --press MASK FROM LEN: hold SYSTEM bits (hex mask: 01 coin, 08 start) for LEN frames
                                          // --pressin MASK FROM LEN: hold INPUTS bits (hex: 0010 P1 button 1, 0001 right ...)
    int every = 30;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--prog") && i + 1 < argc) prog_path = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--trace") && i + 1 < argc) trace_path = argv[++i];
        else if (!strcmp(argv[i], "--dsw1") && i + 1 < argc) { dsw1 = strtoul(argv[++i], nullptr, 16); dsw_given = true; }
        else if (!strcmp(argv[i], "--dsw2") && i + 1 < argc) { dsw2 = strtoul(argv[++i], nullptr, 16); dsw_given = true; }
        else if (!strcmp(argv[i], "--no-rom-log")) log_rom = false;
        else if (!strcmp(argv[i], "--log-from") && i + 1 < argc) log_from = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--gfx") && i + 1 < argc) gfx_path = argv[++i];
        else if (!strcmp(argv[i], "--z80") && i + 1 < argc) z80_path = argv[++i];
        else if (!strcmp(argv[i], "--game") && i + 1 < argc) game = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--oki") && i + 1 < argc) oki_path = argv[++i];
        else if (!strcmp(argv[i], "--wav") && i + 1 < argc) wav_path = argv[++i];
        else if (!strcmp(argv[i], "--frames-out") && i + 1 < argc) frames_out = argv[++i];
        else if (!strcmp(argv[i], "--pause") && i + 2 < argc) { pause_from = atoi(argv[++i]); pause_len = atoi(argv[++i]); }
        else if (!strcmp(argv[i], "--every") && i + 1 < argc) every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--press") && i + 3 < argc) { Press pr; pr.mask = strtoul(argv[++i], nullptr, 16); pr.from = atoi(argv[++i]); pr.len = atoi(argv[++i]); pr.sys = true; presses.push_back(pr); }
        else if (!strcmp(argv[i], "--pressin") && i + 3 < argc) { Press pr; pr.mask = strtoul(argv[++i], nullptr, 16); pr.from = atoi(argv[++i]); pr.len = atoi(argv[++i]); pr.sys = false; presses.push_back(pr); }
    }
    if (prog_path.empty()) { fprintf(stderr, "need --prog <file>\n"); return 1; }

    std::vector<uint8_t> rom(0x100000, 0xff);   // up to 1 MB, big-endian words (FF beyond the file)
    FILE* f = fopen(prog_path.c_str(), "rb");
    if (!f) { perror(prog_path.c_str()); return 1; }
    size_t n = fread(rom.data(), 1, rom.size(), f);
    fclose(f);
    printf("loaded %zu bytes of program ROM\n", n);

    std::vector<uint8_t> z80rom(0x10000, 0xff);
    if (!z80_path.empty()) {
        FILE* g = fopen(z80_path.c_str(), "rb");
        if (!g) { perror(z80_path.c_str()); return 1; }
        size_t zn = fread(z80rom.data(), 1, z80rom.size(), g);
        fclose(g);
        printf("loaded %zu bytes of Z80 program ROM\n", zn);
    }
    std::vector<uint8_t> gfx(0x380000, 0xff);   // 3.5 MB (shangha3 uses the first 2 MB)
    if (!gfx_path.empty()) {
        FILE* g = fopen(gfx_path.c_str(), "rb");
        if (!g) { perror(gfx_path.c_str()); return 1; }
        size_t gn = fread(gfx.data(), 1, gfx.size(), g);
        fclose(g);
        printf("loaded %zu bytes of graphics ROM\n", gn);
    }
    std::vector<uint8_t> okirom(0x80000, 0x00);
    if (!oki_path.empty()) {
        FILE* g = fopen(oki_path.c_str(), "rb");
        if (!g) { perror(oki_path.c_str()); return 1; }
        size_t on = fread(okirom.data(), 1, okirom.size(), g);
        fclose(g);
        printf("loaded %zu bytes of OKI sample ROM\n", on);
    }
    std::vector<int16_t> audio;            // 48 kHz mono capture of the mixed output
    uint32_t oki_last_addr = 0xffffffff;
    int oki_wait = 0;
    std::vector<uint8_t> img(384 * 224 * 3, 0);
    int vx = 0, vy = 0, prev_ce = 0, prev_hblank = 1;
    int gfx_count = -1;

    FILE* tr = fopen(trace_path.c_str(), "w");
    if (!tr) { perror(trace_path.c_str()); return 1; }

    // heberpop/blocken: MAME's DSW defaults unless given (FFFF / FFBF)
    if (game == 1 && !dsw_given) { dsw1 = 0xff; dsw2 = 0xff; }
    if (game == 2 && !dsw_given) { dsw1 = 0xbf; dsw2 = 0xff; }
    auto* top = new Vshangha3_board;
    top->game_id = game;
    top->in_inputs = 0xffff;
    top->in_system = 0x7f;
    top->dsw1 = dsw1;
    top->dsw2 = dsw2;
    top->prog_ok = 0;

    uint64_t cycle = 0;
    int frame = 0;
    int prev_vblank = 1, prev_dtack = 0;
    unsigned prev_gfxlist = 0, prev_flip = 0, prev_coin = 0, prev_busy = 0;
    uint64_t stall_cycles = 0, busy_cycles = 0;
    unsigned last_rom_addr = 0;
    long reads = 0, writes = 0, irqs = 0, blits = 0, z80io = 0;

    DdrModel ddr;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--ddr-easy")) ddr.stress = false;
    auto tick = [&]() {
        bool gfx_req = top->gfx_req;
        uint32_t gfx_addr = top->gfx_addr;
        ddr.step(top);
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cycle++;
        // graphics ROM model: 8-byte row delivered 8 clocks after the request
        top->gfx_ack = 0;
        if (gfx_req && top->gfx_req) {
            if (gfx_count < 0) gfx_count = 8;
            else if (--gfx_count == 0) {
                uint64_t v = 0;
                for (int k = 7; k >= 0; k--) {
                    uint64_t a = (uint64_t)gfx_addr * 8 + k;
                    v = (v << 8) | (a < gfx.size() ? gfx[a] : 0xff);
                }
                top->gfx_data = v;
                top->gfx_ack = 1;
                gfx_count = -1;
            }
        }
        // OKI sample ROM: data valid 2 clocks after the address changes
        if (top->oki_rom_addr != oki_last_addr) {
            oki_last_addr = top->oki_rom_addr;
            oki_wait = 2;
            top->oki_rom_ok = 0;
        } else if (oki_wait > 0 && --oki_wait == 0) {
            top->oki_rom_data = okirom[oki_last_addr & 0x7ffff];
            top->oki_rom_ok = 1;
        }
        if (!wav_path.empty() && cycle % 2000 == 0) audio.push_back((int16_t)top->snd);
        // video capture: a new pixel appears the clock after ce_pix
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
        // ROM model: data available the clock after cs, like a fast SDRAM port
        // prog_addr is the SDRAM word address: program at 000000, graphics ROM at 110000
        {
            uint32_t b = (uint32_t)top->prog_addr << 1;
            if (b >= 0x110000) {
                uint32_t o = b - 0x110000;
                top->prog_data = ((o < gfx.size() ? gfx[o] : 0xff) << 8) | (o + 1 < gfx.size() ? gfx[o + 1] : 0xff);
            } else {
                top->prog_data = (rom[b & 0xfffff] << 8) | rom[(b | 1) & 0xfffff];
            }
        }
        top->prog_ok = top->prog_cs;
        top->z80_rom_data = z80rom[top->z80_rom_addr];
        top->z80_rom_ok = top->z80_rom_cs;
    };

    top->reset = 1;
    top->vid_reset = 1;
    for (int i = 0; i < 64; i++) tick();
    top->reset = 0;
    top->vid_reset = 0;

    // 1 frame = 512 * 262 pixels * 12 clocks
    const uint64_t max_cycles = (uint64_t)(frames + 1) * 512 * 262 * 12;

    while (frame < frames && cycle < max_cycles && !Verilated::gotFinish()) {
        tick();
        double us = cycle / 96.0;

        bool log_bus = frame >= log_from;
        if (log_bus && top->dbg_cpu_cyc_start && !top->dbg_cpu_rw) {
            fprintf(tr, "%10.2f W %06X %04X\n", us, top->dbg_cpu_addr, top->dbg_cpu_dout);
            writes++;
        }
        if (top->dbg_cpu_dtack && !prev_dtack && top->dbg_cpu_rw) {
            if (log_bus && (log_rom || top->dbg_cpu_addr >= 0x80000))
                fprintf(tr, "%10.2f R %06X %04X\n", us, top->dbg_cpu_addr, top->dbg_cpu_din);
            reads++;
            if (top->dbg_cpu_addr < 0x80000) last_rom_addr = top->dbg_cpu_addr;
        }
        prev_dtack = top->dbg_cpu_dtack;

        if (top->dbg_blit_go) { fprintf(tr, "%10.2f EV BLITTER_GO list=%04X\n", us, top->dbg_gfxlist); blits++; }
        stall_cycles += top->dbg_ram_stall;
        busy_cycles += top->dbg_blit_busy;
        if (top->dbg_blit_busy != prev_busy) {
            fprintf(tr, "%10.2f EV BLIT_%s\n", us, top->dbg_blit_busy ? "BUSY" : "DONE");
            prev_busy = top->dbg_blit_busy;
        }
        if (top->dbg_irq_ack) { fprintf(tr, "%10.2f EV IRQ_ACK\n", us); irqs++; }
        if (top->dbg_oki_wr)  fprintf(tr, "%10.2f EV OKI_WRITE %02X\n", us, top->dbg_oki_data);
        if (top->dbg_latch_wr) fprintf(tr, "%10.2f EV LATCH %02X\n", us, top->dbg_cpu_dout & 0xff);
        if (top->dbg_z80_io_wr) { fprintf(tr, "%10.2f EV Z80IO %02X %02X\n", us, top->dbg_z80_io_addr, top->dbg_z80_io_data); z80io++; }
        if (top->dbg_gfxlist != prev_gfxlist) { fprintf(tr, "%10.2f EV GFXLIST %04X\n", us, top->dbg_gfxlist); prev_gfxlist = top->dbg_gfxlist; }
        if (top->dbg_flip != prev_flip) { fprintf(tr, "%10.2f EV FLIP %d\n", us, top->dbg_flip); prev_flip = top->dbg_flip; }
        if (top->dbg_coinctrl != prev_coin) { fprintf(tr, "%10.2f EV COINCTRL %02X\n", us, top->dbg_coinctrl); prev_coin = top->dbg_coinctrl; }

        if (top->vblank && !prev_vblank) {
            frame++;
            if (frame == pause_from) top->pause = 1;
            if (frame == pause_from + pause_len) top->pause = 0;
            { unsigned held = 0, held_in = 0;
              for (auto& pr : presses) if (frame >= pr.from && frame < pr.from + pr.len) (pr.sys ? held : held_in) |= pr.mask;
              top->in_system = 0x7f & ~held; top->in_inputs = 0xffff & ~held_in; }
            fprintf(tr, "%10.2f EV FRAME %d near_pc=%06X blit_busy=%.1f%% cpu_stall=%.1f%%\n", us, frame,
                    last_rom_addr, 100.0 * busy_cycles / (512 * 262 * 12), 100.0 * stall_cycles / (512 * 262 * 12));
            stall_cycles = busy_cycles = 0;
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

    fclose(tr);
    if (!wav_path.empty()) {
        FILE* w = fopen(wav_path.c_str(), "wb");
        uint32_t data_bytes = audio.size() * 2, rate = 48000, byte_rate = rate * 2;
        uint32_t riff = 36 + data_bytes, fmt_len = 16;
        uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
        fwrite("RIFF", 1, 4, w); fwrite(&riff, 4, 1, w); fwrite("WAVEfmt ", 1, 8, w);
        fwrite(&fmt_len, 4, 1, w); fwrite(&pcm, 2, 1, w); fwrite(&ch, 2, 1, w);
        fwrite(&rate, 4, 1, w); fwrite(&byte_rate, 4, 1, w); fwrite(&align, 2, 1, w); fwrite(&bits, 2, 1, w);
        fwrite("data", 1, 4, w); fwrite(&data_bytes, 4, 1, w);
        fwrite(audio.data(), 2, audio.size(), w);
        fclose(w);
        printf("wrote %zu audio samples to %s\n", audio.size(), wav_path.c_str());
    }
    printf("DDR3 frame buffer: %ld words written, %ld read, %ld bad addresses\n", ddr.words_written, ddr.words_read, ddr.errors);
    printf("ran %d frames, %llu clocks (%.1f ms emulated)\n", frame,
           (unsigned long long)cycle, cycle / 96000.0);
    printf("bus: %ld reads, %ld writes, %ld irq acks, %ld blitter starts, %ld Z80 I/O writes\n",
           reads, writes, irqs, blits, z80io);
    top->final();
    delete top;
    return 0;
}
