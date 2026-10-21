// MiSTer DDRAM (Avalon-MM, 64-bit words) model for the Verilator benches.
//
// Call step(top) once per clock, BEFORE the rising edge: it looks at the
// core's outputs as they are before the edge, decides whether the port is
// busy (waitrequest) for this edge, accepts reads/writes, and drives read
// data with random latency. Random waitrequest stalls and latencies exercise
// the core's handshake the way the HPS bridge can.
#pragma once
#include <cstdint>
#include <cstdio>
#include <deque>
#include <vector>

struct DdrModel {
    static constexpr uint32_t BASE = 0x06000000;   // word address of byte 0x30000000
    std::vector<uint64_t> mem = std::vector<uint64_t>(1u << 16, 0);
    std::deque<std::pair<uint64_t, uint32_t>> rq;  // (cycle data is due, word address)
    uint64_t now = 0;
    uint32_t w_addr = 0;
    int      w_left = 0;
    uint32_t rng = 0x1234567;
    int      stall = 0;
    long     words_written = 0, words_read = 0, errors = 0;
    bool     stress = true;

    uint32_t rnd() { rng = rng * 1103515245u + 12345u; return rng >> 8; }

    uint32_t index(uint32_t a) {
        if (a < BASE || a - BASE >= mem.size()) {
            if (errors++ < 5) printf("DDR: access outside the frame buffer area: %07X\n", a);
            return 0;
        }
        return a - BASE;
    }

    template <class T> void step(T* t) {
        now++;
        // waitrequest: mostly free, sometimes a long stall
        bool busy;
        if (!stress) busy = false;
        else if (stall > 0) { stall--; busy = true; }
        else if (rnd() % 500 == 0) { stall = 50 + rnd() % 200; busy = true; }
        else busy = (rnd() % 4) == 0;
        t->ddr_busy = busy;

        if (!busy && t->ddr_we) {
            if (w_left == 0) { w_addr = t->ddr_addr; w_left = t->ddr_burstcnt; }
            mem[index(w_addr)] = t->ddr_din;
            w_addr++; w_left--; words_written++;
        }
        if (!busy && t->ddr_rd) {
            uint64_t due = now + (stress ? 10 + rnd() % 40 : 10);
            if (!rq.empty() && due <= rq.back().first) due = rq.back().first + 1;
            for (int i = 0; i < t->ddr_burstcnt; i++) {
                rq.push_back({due, t->ddr_addr + i});
                due += (stress && rnd() % 3 == 0) ? 2 : 1;
            }
        }
        t->ddr_dout_ready = 0;
        if (!rq.empty() && rq.front().first <= now) {
            t->ddr_dout = mem[index(rq.front().second)];
            t->ddr_dout_ready = 1;
            rq.pop_front();
            words_read++;
        }
    }
};
