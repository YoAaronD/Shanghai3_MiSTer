// Shanghai III (Sunsoft, 1993) - board top level
//
// Behavioural reference: MAME src/mame/sunelectronics/shangha3.cpp
// (BSD-3-Clause, Nicola Salmoria). No MAME code is included here.
//
// Clocking: everything runs from one 96 MHz clock (2 x the board's 48 MHz
// crystal) using clock enables:
//   68000   16 MHz   (48/3)  -> phi enable every 3 clocks
//   pixel    8 MHz   (48/6)  -> every 12 clocks
//   YM2149 1.5 MHz   (48/32) -> every 64 clocks
//
// STATUS
//   done : 68000, memory map, work RAM, palette RAM, inputs, DIPs via YM2149,
//          protection read, vblank IRQ4 + ack, video timing,
//          GA9201 blitter, frame buffers, palette output
//          OKI M6295 sound and mixer
//   ROMs are reached through simple request ports; the MiSTer top level
//   connects them to SDRAM.

module shangha3_board (
    input  logic        clk,          // 96 MHz
    input  logic        reset,

    // program ROM (512 KB, 16-bit, big-endian words)
    output logic [18:1] prog_addr,
    output logic        prog_cs,
    input  logic [15:0] prog_data,
    input  logic        prog_ok,

    // controls, all active low as on the PCB
    input  logic [15:0] in_inputs,    // 0x200000: P1 in [7:0], P2 in [15:8]
    input  logic [6:0]  in_system,    // 0x200002 bits 6..0 (bit 7 = vblank, added here)
    input  logic [7:0]  dsw1,         // YM2149 port A
    input  logic [7:0]  dsw2,         // YM2149 port B

    // video
    output logic        ce_pix,
    output logic        hsync,
    output logic        vsync,
    output logic        hblank,
    output logic        vblank,
    output logic        vblank_next,      // vblank of the next line (CRT Adjust glue)
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue,

    // graphics ROM (2 MB) for the blitter: one 8-byte tile row per request
    output logic        gfx_req,
    output logic [17:0] gfx_addr,
    input  logic        gfx_ack,
    input  logic [63:0] gfx_data,

    // audio
    output logic [9:0]  psg_snd,          // YM2149 raw (unsigned)
    output logic signed [13:0] oki_snd,   // OKI M6295 raw (signed)
    output logic signed [15:0] snd,       // mixed, signed 16-bit

    // OKI sample ROM (256 KB): rom_ok must be high only when rom_data matches oki_rom_addr
    output logic [17:0] oki_rom_addr,
    input  logic [7:0]  oki_rom_data,
    input  logic        oki_rom_ok,

    // debug / simulation visibility
    output logic        dbg_blit_go,
    output logic        dbg_irq_ack,
    output logic [15:0] dbg_gfxlist,
    output logic        dbg_flip,
    output logic [7:0]  dbg_coinctrl,
    output logic        dbg_oki_wr,
    output logic [7:0]  dbg_oki_data,
    output logic [23:0] dbg_cpu_addr,
    output logic        dbg_cpu_cyc_start,
    output logic        dbg_cpu_rw,
    output logic [15:0] dbg_cpu_dout,
    output logic [15:0] dbg_cpu_din,
    output logic        dbg_cpu_dtack,
    output logic        dbg_blit_busy,
    output logic        dbg_ram_stall      // CPU write waiting for the blitter
);

    // ------------------------------------------------------------------
    // Clock enables
    // ------------------------------------------------------------------
    logic [1:0] cpu_div;
    logic       cpu_phase;
    logic       en_phi1, en_phi2;
    logic [3:0] pix_div;
    logic [5:0] psg_div;
    logic       ce_psg;

    always_ff @(posedge clk) begin
        if (reset) begin
            cpu_div   <= '0;
            cpu_phase <= 1'b0;
            pix_div   <= '0;
            psg_div   <= '0;
        end else begin
            cpu_div <= (cpu_div == 2'd2) ? 2'd0 : cpu_div + 2'd1;
            if (cpu_div == 2'd2) cpu_phase <= ~cpu_phase;
            pix_div <= (pix_div == 4'd11) ? 4'd0 : pix_div + 4'd1;
            psg_div <= psg_div + 6'd1;
        end
    end

    assign en_phi1 = (cpu_div == 2'd2) && !cpu_phase;
    assign en_phi2 = (cpu_div == 2'd2) &&  cpu_phase;
    assign ce_pix  = (pix_div == 4'd11);
    assign ce_psg  = (psg_div == 6'd63);

    // ------------------------------------------------------------------
    // Video timing
    // ------------------------------------------------------------------
    logic [8:0] hcnt, vcnt;
    logic       vblank_start;

    shangha3_video_timing u_timing (
        .clk, .reset, .ce_pix,
        .hcnt, .vcnt, .hblank, .vblank, .hsync, .vsync, .vblank_start, .vblank_next
    );


    // ------------------------------------------------------------------
    // 68000 (fx68k)
    // ------------------------------------------------------------------
    logic        cpu_rw, cpu_as_n, cpu_uds_n, cpu_lds_n;
    logic [2:0]  cpu_fc;
    logic [23:1] cpu_eab;
    logic [15:0] cpu_dout, cpu_din;
    logic        cpu_dtack_n, cpu_vpa_n;
    logic [2:0]  cpu_ipl_n;

    fx68k u_cpu (
        .clk       (clk),
        .HALTn     (1'b1),
        .extReset  (reset),
        .pwrUp     (reset),
        .enPhi1    (en_phi1),
        .enPhi2    (en_phi2),
        .eRWn      (cpu_rw),
        .ASn       (cpu_as_n),
        .LDSn      (cpu_lds_n),
        .UDSn      (cpu_uds_n),
        .E         (),
        .VMAn      (),
        .FC0       (cpu_fc[0]),
        .FC1       (cpu_fc[1]),
        .FC2       (cpu_fc[2]),
        .BGn       (),
        .oRESETn   (),
        .oHALTEDn  (),
        .DTACKn    (cpu_dtack_n),
        .VPAn      (cpu_vpa_n),
        .BERRn     (1'b1),
        .BRn       (1'b1),
        .BGACKn    (1'b1),
        .IPL0n     (cpu_ipl_n[0]),
        .IPL1n     (cpu_ipl_n[1]),
        .IPL2n     (cpu_ipl_n[2]),
        .iEdb      (cpu_din),
        .oEdb      (cpu_dout),
        .eab       (cpu_eab)
    );

    wire [23:0] cpu_addr = {cpu_eab, 1'b0};
    wire        cpu_uds  = !cpu_uds_n;
    wire        cpu_lds  = !cpu_lds_n;
    wire        cpu_iack = !cpu_as_n && (cpu_fc == 3'b111);
    wire        cpu_cyc  = !cpu_as_n && (cpu_uds || cpu_lds) && !cpu_iack;
    // On writes the 68000 asserts UDS/LDS one state later than AS. DTACK
    // timing counts from AS so writes don't pick up an extra wait state;
    // the actual write strobes still wait for UDS/LDS (cpu_cyc).
    wire        cpu_as_cyc = !cpu_as_n && !cpu_iack;

    logic cpu_cyc_d;
    always_ff @(posedge clk) cpu_cyc_d <= reset ? 1'b0 : cpu_cyc;
    wire cyc_start = cpu_cyc && !cpu_cyc_d;

    // ------------------------------------------------------------------
    // Address decode (MAME shangha3_state::program_map)
    // ------------------------------------------------------------------
    wire sel_rom  = cpu_addr[23:19] == 5'h00;           // 000000-07FFFF
    wire sel_pal  = cpu_addr[23:12] == 12'h100;         // 100000-100FFF
    wire sel_io   = cpu_addr[23:8]  == 16'h2000;        // 2000xx
    wire sel_ram  = cpu_addr[23:16] == 8'h30;           // 300000-30FFFF
    wire sel_flip = cpu_addr[23:1]  == 23'h1A0000;      // 340000/1
    wire sel_gfxl = cpu_addr[23:1]  == 23'h1B0000;      // 360000/1

    wire [6:0] io_reg = cpu_addr[7:1];
    localparam logic [6:0] IO_INPUTS = 7'h00,  // 200000
                           IO_SYSTEM = 7'h01,  // 200002
                           IO_BLIT   = 7'h04,  // 200008
                           IO_IRQACK = 7'h05,  // 20000A
                           IO_COIN   = 7'h06,  // 20000C (even byte)
                           IO_AY_RD  = 7'h0F,  // 20001F
                           IO_AY_DAT = 7'h17,  // 20002F
                           IO_AY_ADR = 7'h1F,  // 20003F
                           IO_PROT   = 7'h27,  // 20004E
                           IO_OKI    = 7'h37;  // 20006F

    wire io_wr = cyc_start && sel_io && !cpu_rw;
    wire io_rd = cyc_start && sel_io &&  cpu_rw;

    // ------------------------------------------------------------------
    // Program ROM
    // ------------------------------------------------------------------
    assign prog_addr = cpu_addr[18:1];
    assign prog_cs   = cpu_cyc && sel_rom && cpu_rw;

    // ------------------------------------------------------------------
    // Work / graphics RAM 300000-30FFFF (32K x 16)
    // The blitter will need a second port on this later.
    // ------------------------------------------------------------------
    logic [7:0]  ram_hi [0:32767];
    logic [7:0]  ram_lo [0:32767];
    logic [15:0] ram_q;
    wire  [14:0] ram_a  = cpu_addr[15:1];
    logic        ram_we;       // driven below, after the blitter arbitration logic

    always_ff @(posedge clk) begin
        if (ram_we && cpu_uds) ram_hi[ram_a] <= cpu_dout[15:8];
        if (ram_we && cpu_lds) ram_lo[ram_a] <= cpu_dout[7:0];
        ram_q <= {ram_hi[ram_a], ram_lo[ram_a]};
    end

    // second (read-only) port for the blitter
    logic [14:0] blit_ram_addr;
    logic [15:0] blit_ram_q;
    always_ff @(posedge clk) blit_ram_q <= {ram_hi[blit_ram_addr], ram_lo[blit_ram_addr]};

    // ------------------------------------------------------------------
    // Palette RAM 100000-100FFF (2048 x 16, RGBx_555)
    // ------------------------------------------------------------------
    logic [7:0]  pal_hi [0:2047];
    logic [7:0]  pal_lo [0:2047];
    logic [15:0] pal_q;
    wire  [10:0] pal_a  = cpu_addr[11:1];
    wire         pal_we = cyc_start && sel_pal && !cpu_rw;

    always_ff @(posedge clk) begin
        if (pal_we && cpu_uds) pal_hi[pal_a] <= cpu_dout[15:8];
        if (pal_we && cpu_lds) pal_lo[pal_a] <= cpu_dout[7:0];
        pal_q <= {pal_hi[pal_a], pal_lo[pal_a]};
    end

    // second (read-only) port for video scan-out
    logic [10:0] vid_pal_addr;
    logic [15:0] vid_pal_q;
    always_ff @(posedge clk) vid_pal_q <= {pal_hi[vid_pal_addr], pal_lo[vid_pal_addr]};

    // ------------------------------------------------------------------
    // Blitter + frame buffers
    // ------------------------------------------------------------------
    logic [16:0] fb_addr;
    logic        fb_we;
    logic [11:0] fb_wdata, fb_rdata;
    logic        fb_copying;
    logic        blit_busy;
    logic [18:0] blit_scan_from;
    logic [13:0] blit_tm_from;

    shangha3_blitter u_blitter (
        .clk, .reset,
        .start     (dbg_blit_go),
        .gfxlist   (dbg_gfxlist),
        .flip      (dbg_flip),
        .shadow_en (1'b1),             // Shanghai III uses pen-14 shadows
        .hold      (fb_copying),
        .busy      (blit_busy),
        .scan_from (blit_scan_from),
        .tm_from   (blit_tm_from),
        .ram_addr  (blit_ram_addr),
        .ram_q     (blit_ram_q),
        .gfx_req, .gfx_addr, .gfx_ack, .gfx_data,
        .fb_addr, .fb_we, .fb_wdata, .fb_rdata
    );

    shangha3_video u_video (
        .clk, .reset, .ce_pix, .hcnt, .vcnt, .vblank_start,
        .fb_addr, .fb_we, .fb_wdata, .fb_rdata,
        .copying   (fb_copying),
        .pal_addr  (vid_pal_addr),
        .pal_q     (vid_pal_q),
        .red, .green, .blue
    );

    // ------------------------------------------------------------------
    // Protection at 20004E: MAME returns this sequence on successive reads
    // ------------------------------------------------------------------
    logic [3:0] prot_cnt;
    logic [3:0] prot_q;
    function automatic logic [3:0] prot_value(input logic [3:0] n);
        case (n)
            4'd0: prot_value = 4'h0;  4'd1: prot_value = 4'h1;
            4'd2: prot_value = 4'h3;  4'd3: prot_value = 4'h7;
            4'd4: prot_value = 4'hf;  4'd5: prot_value = 4'he;
            4'd6: prot_value = 4'hc;  4'd7: prot_value = 4'h8;
            default: prot_value = 4'h0;
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            prot_cnt <= '0;
            prot_q   <= '0;
        end else if (io_rd && io_reg == IO_PROT) begin
            prot_q   <= prot_value(prot_cnt);
            prot_cnt <= (prot_cnt == 4'd8) ? 4'd0 : prot_cnt + 4'd1;
        end
    end

    // ------------------------------------------------------------------
    // Simple write registers
    // ------------------------------------------------------------------
    logic irq4;

    always_ff @(posedge clk) begin
        dbg_blit_go <= 1'b0;
        dbg_irq_ack <= 1'b0;
        dbg_oki_wr  <= 1'b0;
        if (reset) begin
            dbg_gfxlist  <= '0;
            dbg_flip     <= 1'b0;
            dbg_coinctrl <= '0;
            dbg_oki_data <= '0;
            irq4         <= 1'b0;
        end else begin
            if (vblank_start) irq4 <= 1'b1;
            if (io_wr) begin
                case (io_reg)
                    IO_BLIT:   dbg_blit_go <= 1'b1;
                    IO_IRQACK: begin dbg_irq_ack <= 1'b1; irq4 <= 1'b0; end
                    IO_COIN:   if (cpu_uds) dbg_coinctrl <= cpu_dout[15:8];
                    IO_OKI:    if (cpu_lds) begin dbg_oki_wr <= 1'b1; dbg_oki_data <= cpu_dout[7:0]; end
                    default: ;
                endcase
            end
            if (cyc_start && !cpu_rw && sel_flip && cpu_lds) dbg_flip <= cpu_dout[7];
            if (cyc_start && !cpu_rw && sel_gfxl) begin
                if (cpu_uds) dbg_gfxlist[15:8] <= cpu_dout[15:8];
                if (cpu_lds) dbg_gfxlist[7:0]  <= cpu_dout[7:0];
            end
        end
    end

    assign cpu_ipl_n = irq4 ? 3'b011 : 3'b111;   // level 4 -> IPL2n=0

    // ------------------------------------------------------------------
    // YM2149 (jt49) - also reads DIP switches on its ports A/B
    // ------------------------------------------------------------------
    logic       ay_bdir, ay_bc1;
    logic [7:0] ay_dout;

    always_ff @(posedge clk) begin
        if (reset) begin
            {ay_bdir, ay_bc1} <= 2'b00;
        end else if (io_wr && io_reg == IO_AY_ADR && cpu_lds) begin
            {ay_bdir, ay_bc1} <= 2'b11;              // latch address
        end else if (io_wr && io_reg == IO_AY_DAT && cpu_lds) begin
            {ay_bdir, ay_bc1} <= 2'b10;              // write data
        end else if (cpu_cyc && sel_io && cpu_rw && io_reg == IO_AY_RD) begin
            {ay_bdir, ay_bc1} <= 2'b01;              // read data
        end else begin
            {ay_bdir, ay_bc1} <= 2'b00;
        end
    end

    jt49_bus u_ay (
        .rst_n   (!reset),
        .clk     (clk),
        .clk_en  (ce_psg),
        .bdir    (ay_bdir),
        .bc1     (ay_bc1),
        .din     (cpu_dout[7:0]),
        .sel     (1'b1),
        .dout    (ay_dout),
        .sound   (psg_snd),
        .A       (), .B(), .C(),
        .sample  (),
        .IOA_in  (dsw1), .IOA_out(), .IOA_oe(),
        .IOB_in  (dsw2), .IOB_out(), .IOB_oe()
    );

    // ------------------------------------------------------------------
    // OKI M6295 (jt6295) at 1.056 MHz, pin 7 high (sample rate = clk/132 = 8 kHz)
    // 96 MHz * 11/1000 = 1.056 MHz exactly
    // ------------------------------------------------------------------
    logic [9:0] oki_acc;
    logic       ce_oki;
    always_ff @(posedge clk) begin
        if (reset) begin
            oki_acc <= '0;
            ce_oki  <= 1'b0;
        end else if (oki_acc + 10'd11 >= 10'd1000) begin
            oki_acc <= oki_acc + 10'd11 - 10'd1000;
            ce_oki  <= 1'b1;
        end else begin
            oki_acc <= oki_acc + 10'd11;
            ce_oki  <= 1'b0;
        end
    end

    logic [7:0] oki_dout;
    wire oki_wrn = !(cpu_cyc && sel_io && !cpu_rw && io_reg == IO_OKI && cpu_lds);

    jt6295 #(.INTERPOL(0)) u_oki (
        .rst      (reset),
        .clk      (clk),
        .cen      (ce_oki),
        .ss       (1'b1),
        .wrn      (oki_wrn),
        .din      (cpu_dout[7:0]),
        .dout     (oki_dout),
        .rom_addr (oki_rom_addr),
        .rom_data (oki_rom_data),
        .rom_ok   (oki_rom_ok),
        .sound    (oki_snd),
        .sample   ()
    );

    // ------------------------------------------------------------------
    // Mixer. MAME: YM2149 at 0.30 per channel, OKI at 1.0. The YM2149 output
    // is unipolar, so a slow high-pass removes its DC offset first.
    // Levels are a starting point; adjust by ear on real hardware.
    // ------------------------------------------------------------------
    logic signed [21:0] ay_dc;          // DC estimate, 10.12 fixed point
    logic signed [10:0] ay_ac;
    always_ff @(posedge clk) begin
        if (reset) ay_dc <= 22'sd512 <<< 12;
        else if (ce_psg) ay_dc <= ay_dc + ((($signed({1'b0, psg_snd}) <<< 12) - ay_dc) >>> 10);
        ay_ac <= $signed({1'b0, psg_snd}) - 11'(ay_dc >>> 12);
    end

    always_ff @(posedge clk) begin
        logic signed [17:0] mix;
        mix = 18'(oki_snd) * 18'sd2 + 18'(ay_ac) * 18'sd12;
        if      (mix >  18'sd32767) snd <= 16'sd32767;
        else if (mix < -18'sd32768) snd <= -16'sd32768;
        else                        snd <= 16'(mix);
    end

    // ------------------------------------------------------------------
    // CPU read data + DTACK
    // ------------------------------------------------------------------
    logic [3:0] wait_cnt;
    logic       ready;
    wire        blit_wr_conflict = blit_busy && !cpu_rw &&
                                   ({4'b0, ram_a} >= blit_scan_from ||
                                    ({1'b0, ram_a} >= {1'b0, blit_tm_from} && ram_a < 15'h2000));

    // work RAM write: once per bus cycle, as soon as there is no conflict
    logic ram_wr_done;
    always_ff @(posedge clk) begin
        if (reset || !cpu_cyc) ram_wr_done <= 1'b0;
        else if (ram_we)       ram_wr_done <= 1'b1;
    end
    assign ram_we = cpu_cyc && sel_ram && !cpu_rw && !ram_wr_done && !blit_wr_conflict;

    always_comb begin
        if (sel_rom)                 ready = prog_ok && wait_cnt >= 4'd2;
        // MAME's blitter is instantaneous. Ours first snapshots the command
        // list (and tilemap RAM if used) in ~1% of a frame, then draws from
        // the snapshot. Only CPU writes to words not yet snapshotted wait.
        // Real PCB arbitration is unknown; the real board runs the attract
        // mode smoothly, so the real chip can't hold the CPU up for long.
        else if (sel_ram)            ready = wait_cnt >= 4'd2 && !blit_wr_conflict;
        else if (sel_pal)            ready = wait_cnt >= 4'd2;
        else                         ready = wait_cnt >= 4'd4;   // I/O: give jt49 time
    end

    always_ff @(posedge clk) begin
        if (reset || !cpu_as_cyc) wait_cnt <= '0;
        else if (wait_cnt != 4'hf) wait_cnt <= wait_cnt + 4'd1;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            cpu_din     <= 16'hffff;
            cpu_dtack_n <= 1'b1;
            cpu_vpa_n   <= 1'b1;
        end else begin
            cpu_vpa_n   <= !cpu_iack;                 // autovectored interrupts
            cpu_dtack_n <= !(cpu_as_cyc && ready);

            if      (sel_rom) cpu_din <= prog_data;
            else if (sel_ram) cpu_din <= ram_q;
            else if (sel_pal) cpu_din <= pal_q;
            else if (sel_io) begin
                case (io_reg)
                    IO_INPUTS: cpu_din <= in_inputs;
                    IO_SYSTEM: cpu_din <= {8'hff, !vblank, in_system};
                    IO_AY_RD:  cpu_din <= {8'hff, ay_dout};
                    IO_PROT:   cpu_din <= {12'h000, prot_q};
                    IO_OKI:    cpu_din <= {8'hff, oki_dout};
                    default:   cpu_din <= 16'hffff;
                endcase
            end
            else cpu_din <= 16'hffff;                     // unmapped
        end
    end

    // ------------------------------------------------------------------
    // Debug taps
    // ------------------------------------------------------------------
    assign dbg_cpu_addr      = cpu_addr;
    assign dbg_cpu_cyc_start = cyc_start;
    assign dbg_cpu_rw        = cpu_rw;
    assign dbg_cpu_dout      = cpu_dout;
    assign dbg_cpu_din       = cpu_din;
    assign dbg_cpu_dtack     = !cpu_dtack_n;
    assign dbg_blit_busy     = blit_busy;
    assign dbg_ram_stall     = cpu_cyc && sel_ram && blit_wr_conflict;

endmodule
