// Sound-only bench top: the board's YM2149 (jt49_bus), OKI M6295 (jt6295) and
// mixer (shangha3_mixer), instantiated as in shangha3_board.sv, with the bus driven by
// snd_tb.cpp from a time-stamped register-write log (e.g. from MAME).
module snd_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce_psg,
    input  logic        ce_oki,
    input  logic        ay_bdir,
    input  logic        ay_bc1,
    input  logic        oki_wrn,
    input  logic [7:0]  din,
    output logic [9:0]  psg_snd,
    output logic signed [13:0] oki_snd,
    input  logic [2:0]  balance,            // mixer balance (0 = PCB)
    output logic signed [15:0] snd,         // the board's mixer output
    output logic [17:0] oki_rom_addr,
    input  logic [7:0]  oki_rom_data,
    input  logic        oki_rom_ok
);
    jt49_bus u_ay (
        .rst_n(!reset), .clk(clk), .clk_en(ce_psg), .bdir(ay_bdir), .bc1(ay_bc1),
        .din(din), .sel(1'b1), .dout(), .sound(psg_snd), .A(), .B(), .C(), .sample(),
        .IOA_in(8'hff), .IOA_out(), .IOA_oe(), .IOB_in(8'hff), .IOB_out(), .IOB_oe()
    );
    jt6295 #(.INTERPOL(0)) u_oki (
        .rst(reset), .clk(clk), .cen(ce_oki), .ss(1'b1), .wrn(oki_wrn), .din(din),
        .dout(), .rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
        .sound(oki_snd), .sample()
    );
    shangha3_mixer u_mix (
        .clk(clk), .reset(reset), .ce_psg(ce_psg), .mute(1'b0), .balance(balance),
        .psg_snd(psg_snd), .oki_snd(oki_snd), .snd(snd)
    );
endmodule
