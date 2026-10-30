// OKI-through-SDRAM bench: two jt6295 instances get identical commands.
//   oki_a reads its samples through shangha3_mem + sdram.sv + the SDRAM pin model
//   oki_b reads them straight from the ROM image (the path the board sim used)
// The testbench (oki_tb.cpp) checks both outputs sample for sample.
module oki_bench (
    input  logic        clk,            // 96 MHz
    input  logic        reset,
    input  logic        sdram_init,

    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,
    output logic        ioctl_wait,

    // OKI CPU port (shared by both chips)
    input  logic        oki_wrn,
    input  logic [7:0]  oki_din,
    output logic [7:0]  oki_dout_a,
    output logic [7:0]  oki_dout_b,

    // direct ROM for oki_b, served by the testbench
    output logic [18:0] rom_b_addr,
    input  logic [7:0]  rom_b_data,
    input  logic        rom_b_ok,

    // background SDRAM traffic, driven by the testbench
    input  logic [22:1] prog_addr,
    input  logic        prog_cs,
    output logic        prog_ok,
    input  logic        gfx_req,
    input  logic [18:0] gfx_addr,
    input  logic        oki_bank,       // heberpop-style bank: ROM half for oki_a and oki_b
    output logic        gfx_ack,

    output logic signed [13:0] snd_a,
    output logic signed [13:0] snd_b,
    output logic        ce_oki,
    output logic        mem_ready,

    output logic        SDRAM_CLK, SDRAM_CKE,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    input  logic [15:0] SDRAM_DQ_IN,
    output logic [15:0] SDRAM_DQ_OUT,
    output logic        SDRAM_DQ_OE,
    output logic        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nWE
);
    // 1.056 MHz enable, exactly as in shangha3_board.sv (96 MHz * 11/1000)
    logic [9:0] oki_acc;
    always_ff @(posedge clk) begin
        if (reset) begin oki_acc <= '0; ce_oki <= 1'b0; end
        else if (oki_acc + 10'd11 >= 10'd1000) begin oki_acc <= oki_acc + 10'd11 - 10'd1000; ce_oki <= 1'b1; end
        else begin oki_acc <= oki_acc + 10'd11; ce_oki <= 1'b0; end
    end

    logic [17:0] rom_a_addr, rom_b_chip;
    assign rom_b_addr = {oki_bank, rom_b_chip};
    logic [7:0]  rom_a_data;
    logic        rom_a_ok;

    jt6295 #(.INTERPOL(0)) oki_a (.rst(reset), .clk(clk), .cen(ce_oki), .ss(1'b1),
        .wrn(oki_wrn), .din(oki_din), .dout(oki_dout_a),
        .rom_addr(rom_a_addr), .rom_data(rom_a_data), .rom_ok(rom_a_ok),
        .sound(snd_a), .sample());
    jt6295 #(.INTERPOL(0)) oki_b (.rst(reset), .clk(clk), .cen(ce_oki), .ss(1'b1),
        .wrn(oki_wrn), .din(oki_din), .dout(oki_dout_b),
        .rom_addr(rom_b_chip), .rom_data(rom_b_data), .rom_ok(rom_b_ok),
        .sound(snd_b), .sample());

    logic [26:1] ch1_addr, ch2_addr, ch3_addr, ch4_addr;
    logic        ch1_req, ch2_req, ch3_req, ch4_req, ch1_ready, ch2_ready, ch3_ready, ch4_ready;
    logic [31:0] ch1_dout;
    logic [63:0] ch2_dout, ch3_dout, ch4_dout;
    logic [15:0] ch3_din;
    logic [1:0]  ch3_be;
    logic        ch3_rnw;

    shangha3_mem u_mem (
        .clk, .reset(reset || ioctl_download || sdram_init), .ready(mem_ready),
        .ioctl_download, .ioctl_index(16'd0), .ioctl_wr, .ioctl_addr, .ioctl_dout, .ioctl_wait,
        .prog_addr, .prog_cs, .prog_data(), .prog_ok,
        .gfx_req, .gfx_addr, .gfx_ack, .gfx_data(),
        .z80_addr(16'h0), .z80_cs(1'b0), .z80_data(), .z80_ok(),
        .oki_rom_addr({oki_bank, rom_a_addr}), .oki_rom_data(rom_a_data), .oki_rom_ok(rom_a_ok),
        .ch1_addr, .ch1_req, .ch1_dout, .ch1_ready,
        .ch2_addr, .ch2_req, .ch2_dout, .ch2_ready,
        .ch3_addr, .ch3_req, .ch3_din, .ch3_be, .ch3_rnw, .ch3_ready, .ch3_dout,
        .ch4_addr, .ch4_req, .ch4_dout, .ch4_ready);

    sdram u_sdram (.init(sdram_init), .clk(clk), .doRefresh(1'b0),
        .SDRAM_DQ_IN, .SDRAM_DQ_OUT, .SDRAM_DQ_OE,
        .SDRAM_A, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nWE,
        .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE, .SDRAM_CLK,
        .ch1_addr, .ch1_dout, .ch1_req, .ch1_ready,
        .ch2_addr, .ch2_dout, .ch2_req, .ch2_ready,
        .ch3_addr, .ch3_dout, .ch3_din, .ch3_be, .ch3_req, .ch3_rnw, .ch3_ready,
        .ch4_addr, .ch4_dout, .ch4_req, .ch4_ready);
endmodule
