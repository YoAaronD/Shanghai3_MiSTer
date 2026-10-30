// Sound-only bench for Hebereke no Popoon / Blocken: the YM3438 (jt12), the
// OKI M6295 (jt6295) and ga9201_mixer, as wired in shangha3_board.sv /
// ga9201_sound.sv, driven by snd2_tb.cpp from MAME's Z80 I/O log
// (tools/mame/sound_log.lua) instead of a Z80.
module snd2_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce_ym,
    input  logic        ce_oki,
    input  logic        ym_wr,           // one clock
    input  logic [1:0]  ym_addr,
    input  logic        oki_wrn,
    input  logic [7:0]  din,
    input  logic [2:0]  balance,
    output logic signed [15:0] fm_left,
    output logic signed [15:0] fm_right,
    output logic signed [13:0] oki_snd,
    output logic signed [15:0] snd,
    output logic [17:0] oki_rom_addr,
    input  logic [7:0]  oki_rom_data,
    input  logic        oki_rom_ok
);
    jt12 u_ym (
        .rst(reset), .clk(clk), .cen(ce_ym), .din(din), .addr(ym_addr),
        .cs_n(!ym_wr), .wr_n(!ym_wr), .dout(), .irq_n(), .en_hifi_pcm(1'b0),
        .snd_right(fm_right), .snd_left(fm_left), .snd_sample()
    );
    jt6295 #(.INTERPOL(0)) u_oki (
        .rst(reset), .clk(clk), .cen(ce_oki), .ss(1'b1), .wrn(oki_wrn), .din(din),
        .dout(), .rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
        .sound(oki_snd), .sample()
    );
    ga9201_mixer u_mix (
        .clk(clk), .reset(reset), .mute(1'b0), .balance(balance),
        .fm_left, .fm_right, .oki_snd, .snd
    );
endmodule
