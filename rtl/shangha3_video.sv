// Shanghai III frame buffers and video output
//
//   draw buffer    - 384 x 224 x 12-bit block RAM, the blitter's persistent
//                    canvas (never cleared, as on the PCB)
//   display buffer - what is scanned out, kept in the MiSTer's DDR3
//                    (DDRAM port, byte address 0x30000000), read one line
//                    ahead into a 2-line buffer in block RAM
//
// At the start of vblank the draw buffer is copied to the display buffer.
// The blitter is held off only while the draw buffer is being read
// (86016 clocks = 0.9 ms at 96 MHz, as before); the DDR3 writes finish
// shortly after from a FIFO. Output is tear-free. Each frame shows what
// was drawn before vblank, which puts each blitter result one frame later
// than MAME (measured with scripts/mame_latency.py; see docs/DEVELOPMENT.md).
// How the real PCB buffers its frames is unknown.
//
// The display buffer used to be a second block-RAM copy (~130 of the
// Cyclone V's 553 M10K blocks); the first Quartus fit ran out of M10K.
//
// DDR3 layout: 4 pixels per 64-bit word, pixel i of the word in bits
// [16i+11 : 16i]; 96 words per line, 21504 words per frame.
//
// Scan-out: frame buffer entry -> palette RAM (RGBx_555) -> 8-bit RGB.
// Entries with bit 11 set use the darkened shadow bank (x0.6, as in MAME).

module shangha3_video (
    input  logic        clk,
    input  logic        reset,        // power-up only (display path and DDR3 master)
    input  logic        clear,        // board reset: blank the screen, clear the draw buffer
    input  logic        ce_pix,
    input  logic [8:0]  hcnt,
    input  logic [8:0]  vcnt,
    input  logic        vblank_start,

    // blitter port (draw buffer)
    input  logic [16:0] fb_addr,
    input  logic        fb_we,
    input  logic [11:0] fb_wdata,
    output logic [11:0] fb_rdata,
    output logic        copying,

    // palette RAM read port (registered: pal_q = pal[pal_addr] one clock later)
    output logic [10:0] pal_addr,
    input  logic [15:0] pal_q,

    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue,

    // DDR3 (MiSTer DDRAM port: Avalon-MM, 64-bit words, clocked by clk)
    input  logic        ddr_busy,
    output logic [7:0]  ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic [7:0]  ddr_be,
    output logic        ddr_we
);
    localparam int FB_SIZE   = 384 * 224;
    localparam int FB_WORDS  = FB_SIZE / 4;          // 21504
    localparam int BURST     = 8;
    localparam logic [28:0] DDR_BASE = 29'h0600_0000; // 64-bit word address of byte 0x30000000

    // ------------------------------------------------------------------
    // Draw buffer: port A = blitter (read/write), port B = copy (read)
    // ------------------------------------------------------------------
    logic [11:0] fb_draw [0:FB_SIZE-1];
    logic [16:0] cp_raddr;
    logic [11:0] cp_q;

    // Board reset (including every ROM download) clears the draw buffer, as
    // MAME starts with an empty bitmap. The sweep takes 86016 clocks (0.9 ms)
    // and runs to the end even if the reset is shorter; the blitter is held
    // meanwhile (via `copying`). Port A is shared with the blitter.
    logic        clearing;
    logic [16:0] clr_addr;
    always_ff @(posedge clk) begin
        if (reset) begin
            clearing <= 1'b0;
            clr_addr <= '0;
        end else if (clear) begin
            clearing <= 1'b1;
            clr_addr <= '0;
        end else if (clearing) begin
            if (clr_addr == 17'(FB_SIZE - 1)) clearing <= 1'b0;
            else clr_addr <= clr_addr + 17'd1;
        end
    end
    wire [16:0] fa_addr  = clearing ? clr_addr : fb_addr;
    wire        fa_we    = clearing ? 1'b1     : fb_we;
    wire [11:0] fa_wdata = clearing ? 12'd0    : fb_wdata;

    always_ff @(posedge clk) begin
        if (fa_we) fb_draw[fa_addr] <= fa_wdata;
        fb_rdata <= fb_draw[fa_addr];
    end
    always_ff @(posedge clk) cp_q <= fb_draw[cp_raddr];

    // ------------------------------------------------------------------
    // vblank copy, part 1: read the draw buffer, pack 4 pixels per word
    // into a 128-word FIFO (MLAB; absorbs DDR3 stalls of up to ~500 clocks
    // without slowing the read of the draw buffer, which holds the blitter)
    // ------------------------------------------------------------------
    (* ramstyle = "MLAB, no_rw_check" *) logic [63:0] wf [0:127];
    logic [7:0]  wf_wp, wf_rp;
    wire  [7:0]  wf_cnt = wf_wp - wf_rp;
    logic        wf_we;
    logic [63:0] wf_wdata;
    always_ff @(posedge clk) if (wf_we) wf[wf_wp[6:0]] <= wf_wdata;
    logic        rd_busy;          // still reading the draw buffer
    logic        cp_v;             // cp_q valid this clock
    logic [1:0]  cp_lane;
    logic [47:0] pack;
    logic        wr_busy;          // DDR3 writes of this copy not finished
    logic        disp_valid;       // a complete frame is in DDR3
    logic        need_fresh, fresh_copy;
    logic        wf_pop;

    assign copying = rd_busy || clearing;   // blitter may write once every pixel has been read

    always_comb begin
        wf_we    = cp_v && cp_lane == 2'd3;
        wf_wdata = {4'b0, cp_q, pack};
    end

    always_ff @(posedge clk) begin
        cp_v <= 1'b0;
        if (reset) begin
            rd_busy  <= 1'b0;
            cp_raddr <= '0;
            wf_wp    <= '0;
        end else begin
            // a new copy starts only if the previous one is completely done
            if (vblank_start && !rd_busy && !wr_busy) begin
                rd_busy  <= 1'b1;
                cp_raddr <= '0;
            end else if (rd_busy && wf_cnt < 8'd127) begin
                cp_v    <= 1'b1;
                cp_lane <= cp_raddr[1:0];
                if (cp_raddr == 17'(FB_SIZE - 1)) rd_busy <= 1'b0;
                else cp_raddr <= cp_raddr + 17'd1;
            end
            if (cp_v) begin
                if (cp_lane == 2'd3) wf_wp <= wf_wp + 8'd1;
                else
                    pack[16*cp_lane +: 16] <= {4'b0, cp_q};
            end
        end
    end

    // ------------------------------------------------------------------
    // DDR3 port: copy write bursts (from the FIFO) and scan-out line reads
    // ------------------------------------------------------------------
    typedef enum logic [1:0] { D_IDLE, D_WR, D_RD } dstate_t;
    dstate_t     dstate;
    logic [14:0] wr_word;          // next frame word to write
    logic [2:0]  beat;
    logic        rd_pending;       // line prefetch requested
    logic [7:0]  rd_line;          // 0..223
    logic        rd_buf;           // line buffer half
    logic [3:0]  rd_burst;         // 0..11 bursts of 8 words per line
    logic [2:0]  rd_cnt;           // words received in this burst
    logic        rd_accepted;
    logic [8:0]  vcnt_q;

    // line buffer: 2 lines x 96 words
    logic [63:0] lbuf [0:255];
    logic [7:0]  lb_waddr, lb_raddr;
    logic [63:0] lb_wdata, lb_q;
    logic        lb_we;
    always_ff @(posedge clk) begin
        if (lb_we) lbuf[lb_waddr] <= lb_wdata;
        lb_q <= lbuf[lb_raddr];
    end

    wire [8:0]  vnext_line = (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;   // 262-line raster
    wire [14:0] rd_base    = {rd_line, 6'b0} + {1'b0, rd_line, 5'b0};   // rd_line * 96

    assign ddr_be = 8'hff;
    assign wf_pop = (dstate == D_WR) && !ddr_busy;

    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (reset) begin
            dstate     <= D_IDLE;
            ddr_we     <= 1'b0;
            ddr_rd     <= 1'b0;
            wf_rp      <= '0;
            wr_word    <= '0;
            wr_busy    <= 1'b0;
            disp_valid <= 1'b0;
            need_fresh <= 1'b1;
            fresh_copy <= 1'b0;
            rd_pending <= 1'b0;
            vcnt_q     <= '0;
        end else begin
            // the screen stays black from a board reset until a whole frame,
            // copied after the draw buffer was cleared, is in DDR3
            if (clear || clearing) begin
                disp_valid <= 1'b0;
                need_fresh <= 1'b1;
            end
            if (vblank_start && !rd_busy && !wr_busy) begin
                wr_busy    <= 1'b1;
                wr_word    <= '0;
                fresh_copy <= need_fresh && !clear && !clearing;
                if (!clear && !clearing) need_fresh <= 1'b0;
            end

            // at the start of each line, fetch the next visible line
            vcnt_q <= vcnt;
            if (vcnt != vcnt_q && vnext_line >= 9'd16 && vnext_line <= 9'd239) begin
                rd_pending <= 1'b1;
                rd_line    <= 8'(vnext_line - 9'd16);
                rd_buf     <= vnext_line[0];
                rd_burst   <= '0;
            end

            case (dstate)
                D_IDLE:
                    if (wr_busy && wf_cnt >= 8'(BURST)) begin
                        ddr_we       <= 1'b1;
                        ddr_addr     <= DDR_BASE + 29'(wr_word);
                        ddr_burstcnt <= 8'(BURST);
                        ddr_din      <= wf[wf_rp[6:0]];
                        beat         <= '0;
                        dstate       <= D_WR;
                    end else if (rd_pending) begin
                        ddr_rd       <= 1'b1;
                        ddr_addr     <= DDR_BASE + 29'(rd_base) + 29'({rd_burst, 3'b000});
                        ddr_burstcnt <= 8'(BURST);
                        rd_cnt       <= '0;
                        rd_accepted  <= 1'b0;
                        dstate       <= D_RD;
                    end

                D_WR:
                    if (!ddr_busy) begin
                        wf_rp   <= wf_rp + 8'd1;
                        ddr_din <= wf[7'(wf_rp[6:0] + 7'd1)];
                        beat    <= beat + 3'd1;
                        if (beat == 3'(BURST - 1)) begin
                            ddr_we  <= 1'b0;
                            dstate  <= D_IDLE;
                            wr_word <= wr_word + 15'(BURST);
                            if (wr_word == 15'(FB_WORDS - BURST)) begin
                                wr_busy    <= 1'b0;
                                if (fresh_copy) disp_valid <= 1'b1;
                            end
                        end
                    end

                D_RD: begin
                    if (!ddr_busy) begin
                        ddr_rd      <= 1'b0;
                        rd_accepted <= 1'b1;
                    end
                    if (ddr_dout_ready) begin
                        lb_we    <= 1'b1;
                        lb_waddr <= {rd_buf, 7'({rd_burst, rd_cnt})};
                        lb_wdata <= ddr_dout;
                        rd_cnt   <= rd_cnt + 3'd1;
                        if (rd_cnt == 3'(BURST - 1)) begin
                            dstate   <= D_IDLE;
                            rd_burst <= rd_burst + 4'd1;
                            if (rd_burst == 4'd11) rd_pending <= 1'b0;
                        end
                    end
                end

                default: dstate <= D_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Scan-out. During pixel (h,v) the colour of the NEXT pixel is fetched;
    // it is presented when ce_pix advances the counters to that pixel.
    // ------------------------------------------------------------------
    logic [3:0] ph;                    // clocks since last ce_pix
    logic [8:0] nh, nv;
    logic       nvis;
    logic       sh;                    // shadow bit of the fetched pixel
    logic [7:0] r_n, g_n, b_n;
    wire  [11:0] so_px = lb_q[{nh[1:0], 4'b0000} +: 12];

    always_comb begin
        nh = (hcnt == 9'd511) ? 9'd0 : hcnt + 9'd1;
        if (hcnt == 9'd511) nv = (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;   // 262-line raster
        else                nv = vcnt;
        nvis = (nh < 9'd384) && (nv >= 9'd16) && (nv <= 9'd239) && disp_valid;
    end

    // 5-bit colour -> 8 bits; shadowed pixels x0.6 (as in MAME). The x0.6
    // is a 32-entry table: the divider it replaces was the slowest path in
    // the first Quartus build (-8.8 ns at 96 MHz).
    function automatic logic [7:0] dark5(input logic [4:0] c);
        case (c)
            5'd0 : dark5 = 8'd0;
            5'd1 : dark5 = 8'd4;
            5'd2 : dark5 = 8'd9;
            5'd3 : dark5 = 8'd14;
            5'd4 : dark5 = 8'd19;
            5'd5 : dark5 = 8'd24;
            5'd6 : dark5 = 8'd29;
            5'd7 : dark5 = 8'd34;
            5'd8 : dark5 = 8'd39;
            5'd9 : dark5 = 8'd44;
            5'd10: dark5 = 8'd49;
            5'd11: dark5 = 8'd54;
            5'd12: dark5 = 8'd59;
            5'd13: dark5 = 8'd64;
            5'd14: dark5 = 8'd69;
            5'd15: dark5 = 8'd73;
            5'd16: dark5 = 8'd79;
            5'd17: dark5 = 8'd84;
            5'd18: dark5 = 8'd88;
            5'd19: dark5 = 8'd93;
            5'd20: dark5 = 8'd99;
            5'd21: dark5 = 8'd103;
            5'd22: dark5 = 8'd108;
            5'd23: dark5 = 8'd113;
            5'd24: dark5 = 8'd118;
            5'd25: dark5 = 8'd123;
            5'd26: dark5 = 8'd128;
            5'd27: dark5 = 8'd133;
            5'd28: dark5 = 8'd138;
            5'd29: dark5 = 8'd143;
            5'd30: dark5 = 8'd148;
            5'd31: dark5 = 8'd153;
        endcase
    endfunction

    function automatic logic [7:0] expand5(input logic [4:0] c, input logic dark);
        expand5 = dark ? dark5(c) : {c, c[4:2]};
    endfunction

    always_ff @(posedge clk) begin
        if (reset || ce_pix) ph <= '0;
        else if (ph != 4'hf) ph <= ph + 4'd1;

        case (ph)
            4'd0: lb_raddr <= {nv[0], nh[8:2]};                              // q at ph 2
            4'd2: begin pal_addr <= so_px[10:0]; sh <= so_px[11]; end     // pal_q at ph 4
            4'd4: begin
                r_n <= nvis ? expand5(pal_q[15:11], sh) : 8'd0;
                g_n <= nvis ? expand5(pal_q[10:6],  sh) : 8'd0;
                b_n <= nvis ? expand5(pal_q[5:1],   sh) : 8'd0;
            end
            default: ;
        endcase

        if (ce_pix) begin
            red   <= r_n;
            green <= g_n;
            blue  <= b_n;
        end
    end

endmodule
