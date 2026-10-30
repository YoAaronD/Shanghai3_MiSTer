// Unit test of rtl/ga9201_sound.sv (Z80 + RAM + YM3438 + latch) with a
// hand-assembled Z80 program: IM 0 interrupts from the sound latch (the board
// must supply RST 38h), NMI from a YM3438 timer, RAM write/read, I/O writes.
//   scripts/snd_z80_test.sh
#include "Vga9201_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static const uint8_t prog[] = {
    0x31,0x00,0x00,       // 0000 LD SP,0000
    0xED,0x46,            // 0003 IM 0
    0x3E,0x24,0xD3,0x00,  // 0005 OUT (00),24h   timer A high
    0x3E,0xFA,0xD3,0x01,  // 0009 OUT (01),FAh
    0x3E,0x25,0xD3,0x00,  // 000D OUT (00),25h   timer A low
    0x3E,0x00,0xD3,0x01,  // 0011 OUT (01),00h
    0x3E,0x27,0xD3,0x00,  // 0015 OUT (00),27h   load + enable timer A IRQ
    0x3E,0x15,0xD3,0x01,  // 0019 OUT (01),15h
    0x3E,0x5A,            // 001D LD A,5Ah
    0x32,0x00,0xF9,       // 001F LD (F900),A
    0x3E,0x00,            // 0022 LD A,00h
    0x3A,0x00,0xF9,       // 0024 LD A,(F900)
    0xD3,0x43,            // 0027 OUT (43),A      expect 5A
    0xFB,                 // 0029 EI
    0x18,0xFE,            // 002A JR $
};
static const uint8_t isr38[] = { 0xF5, 0xDB,0xC0, 0xD3,0x41, 0xF1, 0xFB, 0xC9 };       // IN A,(C0); OUT (41),A; EI; RET
static const uint8_t nmi66[] = { 0xF5, 0x3E,0x27,0xD3,0x00, 0x3E,0x15,0xD3,0x01,       // reset timer A flag
                                 0x3E,0x99,0xD3,0x42, 0xF1, 0xED,0x45 };               // OUT (42),99h; RETN

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<uint8_t> rom(0x10000, 0xFF);
    for (size_t i = 0; i < sizeof prog; i++) rom[i] = prog[i];
    for (size_t i = 0; i < sizeof isr38; i++) rom[0x38 + i] = isr38[i];
    for (size_t i = 0; i < sizeof nmi66; i++) rom[0x66 + i] = nmi66[i];

    auto* t = new Vga9201_sound;
    uint64_t cyc = 0;
    int rom_wait = 0; uint16_t rom_last = 0xffff;
    auto tick = [&]() {
        t->clk = 0; t->eval(); t->clk = 1; t->eval(); cyc++;
        // ROM with a few clocks of latency (like the SDRAM cache on a miss)
        if (!t->rom_cs) { t->rom_ok = 0; rom_last = 0xffff; }
        else if (t->rom_addr != rom_last) { rom_last = t->rom_addr; rom_wait = 20; t->rom_ok = 0; }
        else if (rom_wait > 0 && --rom_wait == 0) { t->rom_data = rom[rom_last]; t->rom_ok = 1; }
    };
    t->reset = 1; t->pause = 0; t->latch_wr = 0; t->oki_dout = 0;
    for (int i = 0; i < 200; i++) tick();
    t->reset = 0;

    const uint8_t latches[] = { 0x11, 0x22, 0x83, 0xF4 };
    int li = 0, echoes = 0, nmis = 0, ramok = 0, bad = 0;
    for (uint64_t i = 0; i < 96000ull * 20; i++) {        // 20 ms
        if (i % (96000ull * 4) == 96000ull * 2 && li < 4) { t->latch_din = latches[li++]; t->latch_wr = 1; }
        tick();
        t->latch_wr = 0;
        if (t->dbg_io_wr) {
            uint8_t a = t->dbg_io_addr, d = t->dbg_io_data;
            if (a == 0x41) { if (d == latches[echoes]) echoes++; else { bad++; printf("  latch echo %02X, expected %02X\n", d, latches[echoes]); } }
            if (a == 0x42) nmis++;
            if (a == 0x43) { if (d == 0x5A) ramok = 1; else { bad++; printf("  RAM read %02X\n", d); } }
        }
    }
    printf("latch interrupts: %d of %d echoed; YM3438 timer NMIs: %d; RAM test: %s\n",
           echoes, li, nmis, ramok ? "ok" : "FAIL");
    bool pass = echoes == 4 && nmis >= 10 && ramok && !bad;
    printf("%s\n", pass ? "PASS" : "FAIL");
    delete t;
    return pass ? 0 : 1;
}
