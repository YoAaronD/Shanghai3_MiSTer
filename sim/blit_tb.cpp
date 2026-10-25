// Unit test for shangha3_blitter: replays snapshots dumped by the reference
// model (refmodel --dump-blits) and checks the HDL frame buffer pixel-for-pixel.
//
// usage: Vshangha3_blitter --gfx blitter.bin --dir sim/blits [--latency N] [--save-diff]
#include "Vshangha3_blitter.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <string>
#include <vector>

static std::vector<uint8_t> load(const std::string& p) {
    std::vector<uint8_t> d;
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) return d;
    fseek(f, 0, SEEK_END); d.resize(ftell(f)); fseek(f, 0, SEEK_SET);
    if (fread(d.data(), 1, d.size(), f) != d.size()) d.clear();
    fclose(f);
    return d;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::string gfx_path, dir;
    int latency = 8;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--gfx") && i + 1 < argc) gfx_path = argv[++i];
        else if (!strcmp(argv[i], "--dir") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--latency") && i + 1 < argc) latency = atoi(argv[++i]);
    }
    auto gfx = load(gfx_path);
    if (gfx.empty() || dir.empty()) { fprintf(stderr, "need --gfx and --dir\n"); return 1; }

    std::vector<std::string> cases;
    if (DIR* d = opendir(dir.c_str())) {
        while (dirent* e = readdir(d)) {
            std::string n = e->d_name;
            if (n.size() > 9 && n.substr(n.size() - 9) == "_info.txt") cases.push_back(n.substr(0, n.size() - 9));
        }
        closedir(d);
    }
    std::sort(cases.begin(), cases.end());

    auto* top = new Vshangha3_blitter;
    int failures = 0;
    uint64_t worst_cycles = 0;
    std::string worst_case;

    for (auto& c : cases) {
        auto ramb = load(dir + "/" + c + "_ram.bin");
        auto before = load(dir + "/" + c + "_before.bin");
        auto after = load(dir + "/" + c + "_after.bin");
        auto info = load(dir + "/" + c + "_info.txt");
        unsigned gfxlist = 0; int flip = 0;
        std::string infos(info.begin(), info.end());
        sscanf(infos.c_str(), "%x %d", &gfxlist, &flip);

        std::vector<uint16_t> ram(0x8000), fb(384 * 224), expect(384 * 224);
        for (int i = 0; i < 0x8000; i++) ram[i] = (ramb[2 * i] << 8) | ramb[2 * i + 1];
        memcpy(fb.data(), before.data(), fb.size() * 2);
        memcpy(expect.data(), after.data(), expect.size() * 2);

        // reset
        top->reset = 1; top->start = 0; top->gfx_ack = 0;
        for (int i = 0; i < 4; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
        top->reset = 0;
        top->gfxlist = gfxlist; top->flip = flip; top->shadow_en = 1;

        int gfx_count = -1;
        uint64_t cycles = 0, gfx_fetches = 0;
        bool started = false;
        while (cycles < 20000000) {
            // memory models act on the register outputs of the current cycle
            uint32_t fa = top->fb_addr;
            uint16_t rd = 0;
            if (fa < fb.size()) {
                if (top->fb_we) fb[fa] = top->fb_wdata;
                rd = fb[fa];
            }
            uint32_t ra = top->ram_addr;
            bool req = top->gfx_req;
            uint32_t ga = top->gfx_addr;

            top->start = !started;
            top->clk = 0; top->eval();
            top->clk = 1; top->eval();
            started = true;
            cycles++;

            top->fb_rdata = rd;
            top->ram_q = ram[ra & 0x7fff];
            top->gfx_ack = 0;
            if (req && top->gfx_req) {
                if (gfx_count < 0) gfx_count = latency;
                else if (--gfx_count == 0) {
                    uint64_t v = 0;
                    for (int k = 7; k >= 0; k--) v = (v << 8) | gfx[((uint64_t)ga * 8 + k) % gfx.size()];
                    top->gfx_data = v;
                    top->gfx_ack = 1;
                    gfx_count = -1;
                    gfx_fetches++;
                }
            }
            if (!top->busy && cycles > 2) break;
        }

        int bad = 0, first = -1;
        for (size_t i = 0; i < fb.size(); i++)
            if ((fb[i] & 0xfff) != (expect[i] & 0xfff)) { if (first < 0) first = i; bad++; }
        printf("%s  gfxlist=%04X  %8llu cycles (%5.1f%% of a frame)  %6llu row fetches  %s",
               c.c_str(), gfxlist, (unsigned long long)cycles, 100.0 * cycles / (512 * 262 * 12),
               (unsigned long long)gfx_fetches, bad ? "FAIL" : "ok");
        if (bad) {
            printf("  %d pixels differ, first at x=%d y=%d hdl=%03X ref=%03X", bad, first % 384, first / 384,
                   fb[first], expect[first]);
            failures++;
            std::string out = dir + "/" + c + "_hdl.bin";
            FILE* f = fopen(out.c_str(), "wb"); fwrite(fb.data(), 2, fb.size(), f); fclose(f);
        }
        printf("\n");
        if (cycles > worst_cycles) { worst_cycles = cycles; worst_case = c; }
    }
    printf("\n%zu cases, %d failed. slowest: %s, %llu cycles = %.1f%% of a frame at 96 MHz\n",
           cases.size(), failures, worst_case.c_str(), (unsigned long long)worst_cycles,
           100.0 * worst_cycles / (512 * 262 * 12));
    delete top;
    return failures ? 1 : 0;
}
