// Sound CPU section of Hebereke no Popoon and Blocken (Sunsoft GA9201 boards
// SUN-06 / KID-07): Z80, 2 KB RAM, YM3438, sound latch.
//
// Behavioural reference: MAME src/mame/sunelectronics/shangha3.cpp
// (heberpop_state::sound_program_map / sound_io_map, heberpop() machine
// config). No MAME code is included here.
//
//   Z80 6 MHz (48/8)      program 0000-F7FF (ROM, through the SDRAM cache),
//                         RAM F800-FFFF
//   I/O (A7..A0)          00-03 YM3438, 80 OKI M6295, C0 sound latch (read)
//                         heberpop also writes 40/41 (unknown; ignored, as MAME)
//   INT                   sound latch "data pending", cleared by reading C0.
//                         The game runs in interrupt mode 0; the board puts FF
//                         (RST 38h) on the bus during the acknowledge, as MAME.
//   NMI                   YM3438 IRQ
//   YM3438 8 MHz (48/6)   jt12
//
// The OKI M6295 itself stays in shangha3_board (one jt6295 for all games);
// this module hands it the Z80's writes and gets its status byte back.
//
// pause freezes the Z80 and the YM3438 (their clock enables stop).

module ga9201_sound (
    input  logic        clk,            // 96 MHz
    input  logic        reset,
    input  logic        pause,          // synchronised, from the board

    // sound latch, written by the 68000
    input  logic        latch_wr,       // one clock
    input  logic [7:0]  latch_din,

    // Z80 program ROM (shangha3_mem's Z80 cache)
    output logic [15:0] rom_addr,
    output logic        rom_cs,
    input  logic [7:0]  rom_data,
    input  logic        rom_ok,

    // OKI M6295 (in the board)
    output logic        oki_wrn,        // low while the Z80 writes port 80
    output logic [7:0]  oki_din,
    input  logic [7:0]  oki_dout,

    // YM3438 output
    output logic signed [15:0] fm_left,
    output logic signed [15:0] fm_right,

    // simulation visibility: every Z80 I/O write
    output logic        dbg_io_wr,
    output logic [7:0]  dbg_io_addr,
    output logic [7:0]  dbg_io_data
);

    // ------------------------------------------------------------------
    // Clock enables: Z80 6 MHz = 96/16, YM3438 8 MHz = 96/12
    // ------------------------------------------------------------------
    logic [3:0] z_div, ym_div;
    logic       cen_z80, cen_ym;
    always_ff @(posedge clk) begin
        if (reset) begin
            z_div   <= '0;
            ym_div  <= '0;
            cen_z80 <= 1'b0;
            cen_ym  <= 1'b0;
        end else begin
            cen_z80 <= 1'b0;
            cen_ym  <= 1'b0;
            if (!pause) begin
                z_div  <= z_div + 4'd1;
                ym_div <= (ym_div == 4'd11) ? 4'd0 : ym_div + 4'd1;
                cen_z80 <= (z_div == 4'd15);
                cen_ym  <= (ym_div == 4'd11);
            end
        end
    end

    // ------------------------------------------------------------------
    // Z80 (tv80, with a clock enable)
    // ------------------------------------------------------------------
    logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
    logic [15:0] A;
    logic [7:0]  z_dout, z_din;
    logic        wait_n, int_n, nmi_n;

    tv80_cen #(.Mode(0), .T2Write(1), .IOWait(1)) u_z80 (
        .reset_n (!reset),
        .clk     (clk),
        .cen     (cen_z80),
        .wait_n  (wait_n),
        .int_n   (int_n),
        .nmi_n   (nmi_n),
        .busrq_n (1'b1),
        .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n, .halt_n, .busak_n,
        .A       (A),
        .di      (z_din),
        .dout    (z_dout)
    );

    wire mem_rd  = !mreq_n && !rd_n;
    wire mem_wr  = !mreq_n && !wr_n;
    wire io_cyc  = !iorq_n && m1_n;            // not an interrupt acknowledge
    wire int_ack = !iorq_n && !m1_n;
    wire io_rd   = io_cyc && !rd_n;
    wire io_wr   = io_cyc && !wr_n;
    wire sel_ram = A[15:11] == 5'b11111;       // F800-FFFF

    // ROM: wait states until the cache has the byte
    assign rom_addr = A;
    assign rom_cs   = mem_rd && !sel_ram;
    assign wait_n   = !(rom_cs && !rom_ok);

    // RAM 2 KB
    logic [7:0] ram [0:2047];
    logic [7:0] ram_q;
    always_ff @(posedge clk) begin
        if (mem_wr && sel_ram) ram[A[10:0]] <= z_dout;
        ram_q <= ram[A[10:0]];
    end

    // ------------------------------------------------------------------
    // I/O decode (A7..A0, as MAME's global_mask(0xff))
    // ------------------------------------------------------------------
    wire sel_ym    = A[7:2] == 6'b000000;      // 00-03
    wire sel_oki   = A[7:0] == 8'h80;
    wire sel_latch = A[7:0] == 8'hC0;

    // one-clock strobes at the start of each I/O write / read
    logic io_wr_d, io_rd_d;
    always_ff @(posedge clk) begin
        io_wr_d <= reset ? 1'b0 : io_wr;
        io_rd_d <= reset ? 1'b0 : io_rd;
    end
    wire io_wr_start = io_wr && !io_wr_d;
    wire io_rd_start = io_rd && !io_rd_d;

    // ------------------------------------------------------------------
    // Sound latch: 68000 writes; INT while pending; Z80 read of C0 clears it
    // ------------------------------------------------------------------
    logic [7:0] latch;
    logic       pending;
    always_ff @(posedge clk) begin
        if (reset) begin
            latch   <= 8'h00;
            pending <= 1'b0;
        end else begin
            if (io_rd_start && sel_latch) pending <= 1'b0;
            if (latch_wr) begin
                latch   <= latch_din;
                pending <= 1'b1;
            end
        end
    end
    assign int_n = !pending;

    // ------------------------------------------------------------------
    // YM3438 (jt12)
    // ------------------------------------------------------------------
    logic [7:0] ym_dout;
    logic       ym_irq_n;
    jt12 u_ym (
        .rst        (reset),
        .clk        (clk),
        .cen        (cen_ym),
        .din        (z_dout),
        .addr       (A[1:0]),
        .cs_n       (!(io_wr_start && sel_ym)),
        .wr_n       (!(io_wr_start && sel_ym)),
        .dout       (ym_dout),
        .irq_n      (ym_irq_n),
        .en_hifi_pcm(1'b0),
        .snd_right  (fm_right),
        .snd_left   (fm_left),
        .snd_sample ()
    );
    assign nmi_n = ym_irq_n;

    // ------------------------------------------------------------------
    // OKI port
    // ------------------------------------------------------------------
    assign oki_wrn = !(io_wr && sel_oki);
    assign oki_din = z_dout;

    // ------------------------------------------------------------------
    // Z80 data in
    // ------------------------------------------------------------------
    always_comb begin
        if (int_ack)                 z_din = 8'hFF;          // IM 0: RST 38h
        else if (!mreq_n)            z_din = sel_ram ? ram_q : rom_data;
        else if (io_cyc) begin
            if (sel_ym)              z_din = ym_dout;
            else if (sel_oki)        z_din = oki_dout;
            else if (sel_latch)      z_din = latch;
            else                     z_din = 8'hFF;
        end
        else                         z_din = 8'hFF;
    end

    assign dbg_io_wr   = io_wr_start;
    assign dbg_io_addr = A[7:0];
    assign dbg_io_data = z_dout;

endmodule
