// Sunsoft GA9201 KA01-0249 blitter (Shanghai III / Hebereke no Popoon / Blocken)
//
// Behavior follows MAME shangha3.cpp's description of the chip and is checked
// pixel-for-pixel against our software model (sim/refmodel/blitter.c).
// How the real chip is built inside is unknown; this is a clean-room state machine.
//
// What it does: when started, walk the command list in work RAM from
// gfxlist*16 bytes up to the end of RAM (16 words per command) and draw into
// the frame buffer:
//   * sprites  - a horizontal strip of 16x16 tiles, optionally zoomed
//   * fills    - zoom <= 1: one tile magnified 256x and clipped (rectangle fill)
//   * tilemaps - a grid of tiles whose codes are read from RAM (normal or
//                "condensed" 8-pixel spacing), with zoomed spacing
// Pen 15 is transparent; pen 14 is a shadow on sprites when shadow_en is set.
//
// Frame buffer: only the visible 384 x 224 area is stored (lines 16..239 of
// the 262-line raster). Pixels outside it can never be seen, so they are
// clipped away here; the visible result is identical.
//   entry = {shadow_bank, color[6:0], pen[3:0]}  (12 bits)
//
// Interfaces (all synchronous to clk):
//   RAM : ram_addr -> ram_q valid 2 clocks later (registered address + BRAM)
//   GFX : hold gfx_req with gfx_addr (= tile*16 + row, one 8-byte row) until
//         gfx_ack; gfx_data[4n+3:4n] is pixel n of that row
//   FB  : fb_addr/fb_we/fb_wdata are registered; fb_rdata = mem[fb_addr] one
//         clock after fb_addr is set (used for shadow read-modify-write)
//
// Not implemented: rotation (command words 11/12) - unused by Shanghai III.

module shangha3_blitter (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,        // pulse: CPU wrote 200008
    input  logic [15:0] gfxlist,      // CPU-written list address (360000)
    input  logic        flip,         // flipscreen
    input  logic        shadow_en,    // shangha3 = 1, heberpop/blocken = 0
    input  logic        big_gfx,      // heberpop/blocken: 3.5 MB graphics ROM, 28,672 tiles (shangha3: 2 MB, 16,384)
    input  logic        hold,         // don't start a new list (frame buffer copy running)
    output logic        busy,
    output logic        px_step,      // one pulse per destination pixel processed (bus-hold model)
    output logic [18:0] scan_from,    // CPU writes at/after this RAM word must wait (list not yet copied)
    output logic [13:0] tm_from,      // CPU writes to tilemap RAM words [tm_from, 0x2000) must wait

    output logic [14:0] ram_addr,
    input  logic [15:0] ram_q,

    output logic        gfx_req,
    output logic [18:0] gfx_addr,
    input  logic        gfx_ack,
    input  logic [63:0] gfx_data,

    output logic [16:0] fb_addr,
    output logic        fb_we,
    output logic [11:0] fb_wdata,
    input  logic [11:0] fb_rdata
);

    // Visible window in raster coordinates
    localparam logic signed [15:0] VIS_X0 = 16'sd0,  VIS_X1 = 16'sd383;
    localparam logic signed [15:0] VIS_Y0 = 16'sd16, VIS_Y1 = 16'sd239;

    // 0x100000 / width for zoomed tile widths 1..32 (16.16 source step)
    function automatic logic [31:0] dx_for_width(input logic [5:0] w);
        case (w)
            6'd1: dx_for_width = 32'd1048576;
            6'd2: dx_for_width = 32'd524288;
            6'd3: dx_for_width = 32'd349525;
            6'd4: dx_for_width = 32'd262144;
            6'd5: dx_for_width = 32'd209715;
            6'd6: dx_for_width = 32'd174762;
            6'd7: dx_for_width = 32'd149796;
            6'd8: dx_for_width = 32'd131072;
            6'd9: dx_for_width = 32'd116508;
            6'd10: dx_for_width = 32'd104857;
            6'd11: dx_for_width = 32'd95325;
            6'd12: dx_for_width = 32'd87381;
            6'd13: dx_for_width = 32'd80659;
            6'd14: dx_for_width = 32'd74898;
            6'd15: dx_for_width = 32'd69905;
            6'd16: dx_for_width = 32'd65536;
            6'd17: dx_for_width = 32'd61680;
            6'd18: dx_for_width = 32'd58254;
            6'd19: dx_for_width = 32'd55188;
            6'd20: dx_for_width = 32'd52428;
            6'd21: dx_for_width = 32'd49932;
            6'd22: dx_for_width = 32'd47662;
            6'd23: dx_for_width = 32'd45590;
            6'd24: dx_for_width = 32'd43690;
            6'd25: dx_for_width = 32'd41943;
            6'd26: dx_for_width = 32'd40329;
            6'd27: dx_for_width = 32'd38836;
            6'd28: dx_for_width = 32'd37449;
            6'd29: dx_for_width = 32'd36157;
            6'd30: dx_for_width = 32'd34952;
            6'd31: dx_for_width = 32'd33825;
            default: dx_for_width = 32'd32768;   // 32
        endcase
    endfunction

    // Zoom register -> drawn tile width: round((0x200 - zoom) / 16), 1..32
    function automatic logic [5:0] width_for_zoom(input logic [15:0] zoom);
        logic [9:0] zf;
        zf = 10'h200 - zoom[9:0];          // zoom < 0x1f0 guaranteed by validity check
        width_for_zoom = 6'((zf + 10'd8) >> 4);
    endfunction

    typedef enum logic [4:0] {
        S_IDLE, S_CHECK, S_NEXT_CMD, S_CMD_RD, S_CMD_EARLY, S_SNAP_STORE,
        S_TM_COPY, S_P2_WAIT, S_P2_FETCH, S_P2_LOAD, S_P2_NEXT, S_CMD_DEC, S_CMD_CLIP, S_DISPATCH,
        S_SPR_NEXT,
        S_TM_SETUP, S_TM_CELL, S_TM_RD, S_TM_POS, S_TM_NEXT,
        S_D_PRE0, S_D_PRE1, S_D_SETUP, S_D_SETUP2, S_D_ROW, S_D_PIXSTART, S_D_PIX,
        S_D_SH1, S_D_SH2
    } state_t;

    state_t state, ret_state;
    // Starts that arrive while a run is in progress are queued (up to 3).
    // MAME's blitter draws instantly at "go", so a queued run must see RAM
    // exactly as it was at its go: while a run is queued, the board holds
    // every CPU write to the list and tilemap areas until that run's own
    // snapshot has copied them (scan_from / tm_from below). Found on real
    // hardware: at boot the game issues two gos ~8 us apart and then
    // reuses that RAM; without the hold the second run drew a screen of
    // stale tiles instead of "INTTURUPT WAIT".
    logic [1:0]  pend_cnt;
    logic [15:0] pend_list;            // list address of the oldest queued run
    wire         start_pending = (pend_cnt != 2'd0);

    // ------------------------------------------------------------------
    // Command fields
    // ------------------------------------------------------------------
    logic [18:0] offs;                 // word offset of current command
    logic [1:0]  rd_wait;              // tilemap cell read wait
    logic [3:0]  issue_k, seq_end;     // command read pipeline
    logic        p1_valid, p2_valid;
    logic [3:0]  p1_idx, p2_idx;
    logic [15:0] w11, w12;             // rotation: not read (unused by Shanghai III)

    // order in which command words are fetched
    function automatic logic [3:0] word_seq(input logic [3:0] k);
        case (k)
            4'd0: word_seq = 4'd6;   4'd1: word_seq = 4'd7;
            4'd2: word_seq = 4'd10;  4'd3: word_seq = 4'd13;
            4'd4: word_seq = 4'd1;   4'd5: word_seq = 4'd2;
            4'd6: word_seq = 4'd3;   4'd7: word_seq = 4'd4;
            4'd8: word_seq = 4'd5;   4'd9: word_seq = 4'd8;
            default: word_seq = 4'd9;
        endcase
    endfunction
    logic [15:0] w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w13;

    logic signed [15:0] sx, sy;
    logic        fx, fy;
    logic [6:0]  color;
    logic signed [15:0] cx0, cx1, cy0, cy1;   // clip rectangle

    // sprite strip state
    logic [5:0]  spr_n, spr_i;
    logic [15:0] spr_code;
    logic [5:0]  spr_w, spr_h;

    // tilemap state
    logic [7:0]  tm_w, tm_h, tm_x, tm_y;
    logic [11:0] tm_srcx, tm_srcy;
    logic [3:0]  tm_dispx, tm_dispy;
    logic        tm_cond;
    logic [15:0] tm_tile;

    // ------------------------------------------------------------------
    // Draw engine registers (one tile, scaled, clipped)
    // ------------------------------------------------------------------
    logic [15:0]        e_code;
    logic [14:0]        e_tile;       // e_code wrapped to the ROM's tile count, as MAME's code % total
    logic [6:0]         e_color;
    logic               e_fx, e_fy, e_shadow;
    logic signed [15:0] e_destx, e_desty;
    logic [12:0]        e_dstw, e_dsth;
    logic signed [31:0] e_dx, e_dy;

    logic signed [15:0] d_x0, d_x1, d_y0, d_y1, d_curx, d_cury;
    logic signed [31:0] d_srcx, d_srcy, d_cursrcx;
    logic [16:0]        d_fbrow;
    logic [63:0]        row_data;
    logic [18:0]        cache_addr;
    logic               cache_valid;
    // fetch unit: one outstanding ROM request, one prefetched row
    logic               pf_valid;
    logic [18:0]        pf_addr;
    logic [63:0]        pf_data;

    // ------------------------------------------------------------------
    // Two phases, so the CPU is almost never held up:
    //   1. snapshot: walk the list in RAM, copying valid commands into cmdbuf
    //      (fast: ~4 RAM reads per disabled command, 11 per valid one)
    //      and, if any command is a tilemap, the 8K-word tilemap area
    //   2. draw from the snapshots; work RAM is not touched
    // The board holds CPU writes to RAM the blitter has yet to read, which
    // gives the same result as MAME's instantaneous blitter.
    // ------------------------------------------------------------------
    logic [175:0] cmdbuf [0:2047];     // up to (0x8000 words / 16) commands
    logic [175:0] cb_q;
    logic [11:0]  cb_n, cb_rd;
    logic         has_tm, phase1;

    always_ff @(posedge clk) cb_q <= cmdbuf[cb_rd[10:0]];

    logic [15:0]  tmbuf [0:8191];      // tilemap RAM snapshot (words 0..0x1fff)
    logic [15:0]  tm_q;
    logic [12:0]  tm_raddr;
    logic [13:0]  tc_issue;
    logic         tc_p1v, tc_p2v;
    logic [12:0]  tc_p1a, tc_p2a;
    always_ff @(posedge clk) tm_q <= tmbuf[tm_raddr];

    // Block RAM write ports, kept in their own processes so Quartus infers M10K
    always_ff @(posedge clk)
        if (state == S_SNAP_STORE) cmdbuf[cb_n[10:0]] <= {w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w13};
    always_ff @(posedge clk)
        if (state == S_TM_COPY && tc_p2v) tmbuf[tc_p2a] <= ram_q;

    assign busy = (state != S_IDLE) || start_pending;
    wire [18:0] run_scan_from = (state == S_IDLE) ? {gfxlist, 3'b000} : (phase1 ? offs : 19'h8000);
    wire [18:0] pend_from     = {pend_list, 3'b000};
    assign scan_from = (start_pending && pend_from < run_scan_from) ? pend_from : run_scan_from;
    // tilemap RAM words not yet snapshotted: [tm_from, 0x2000)
    assign tm_from = (state == S_IDLE)    ? 14'h0000 :
                     start_pending        ? 14'h0000 :      // queued run: whole tilemap pending
                     (state == S_TM_COPY) ? tc_issue :
                     phase1               ? 14'h0000 : 14'h2000;

    // Tile number from a 16-bit code, wrapped to the graphics ROM size as
    // MAME's gfx element does (code % total): 16,384 tiles (2 MB) on
    // Shanghai III, 28,672 (3.5 MB, 0x7000) on heberpop/blocken.
    function automatic logic [14:0] tile_of(input logic [15:0] c, input logic big);
        logic [15:0] t;
        if (!big) tile_of = {1'b0, c[13:0]};
        else begin
            t = c;
            if (t >= 16'h7000) t = t - 16'h7000;
            if (t >= 16'h7000) t = t - 16'h7000;
            tile_of = t[14:0];
        end
    endfunction

    // combinational helpers
    wire [18:0]        row_sum  = {e_tile, 4'b0} + 19'(d_srcy >>> 16);
    wire [18:0]        row_addr = big_gfx ? row_sum : {1'b0, row_sum[17:0]};   // shangha3: 18-bit wrap as before
    wire signed [31:0] next_srcy = d_srcy + e_dy;
    wire [18:0]        next_row_sum  = {e_tile, 4'b0} + 19'(next_srcy >>> 16);
    wire [18:0]        next_row_addr = big_gfx ? next_row_sum : {1'b0, next_row_sum[17:0]};
    wire [3:0]         pix_col  = d_cursrcx[19:16];
    wire [3:0]         pen      = row_data[{pix_col, 2'b00} +: 4];
    wire [16:0]        pix_addr = d_fbrow + 17'(d_curx);

    // shadow: set bit 7 of the palette index (colours 0-127 -> 128-255, where
    // the game keeps their darkened versions). Idempotent, as on the PCB: a
    // shadow drawn over an existing shadow (overlapping tile shadows, the hand
    // cursor's shadow over them) leaves it unchanged. MAME darkens a second
    // time through its generic shadow bank, which the PCB does not
    // (Aaron's cursor videos, 20261024). The bit-11 shadow bank is unused now.
    function automatic logic [11:0] shadow_of(input logic [11:0] p);
        shadow_of = p | 12'h080;
    endfunction

    // ------------------------------------------------------------------
    // Arithmetic pipelines (free-running, registered). The first Quartus
    // build missed 96 MHz timing, so the multiplies are split into
    // register stages; the state machine waits for them:
    //   tilemap cell offsets: tm_x/tm_y change at least 4 clocks before
    //     S_TM_POS (S_TM_CELL + 3 x S_TM_RD), the pipeline needs 3
    //   clip/flip products: S_D_PRE0/S_D_PRE1 wait 2 clocks after the
    //     draw parameters (e_destx, e_dx, ...) are set, before S_D_SETUP
    // ------------------------------------------------------------------
    // tilemap cell position (before flip): base*x*(0x200-zoom)/256 - disp
    logic [9:0]  tm_zfx, tm_zfy;
    logic [17:0] tm_px, tm_py;
    logic [31:0] tm_offx, tm_offy;
    always_ff @(posedge clk) begin
        tm_zfx  <= 10'h200 - w10[9:0];
        tm_zfy  <= 10'h200 - w13[9:0];
        tm_px   <= tm_x * tm_zfx;               // 8 x 10 bits: one DSP
        tm_py   <= tm_y * tm_zfy;
        tm_offx <= ((32'(tm_px) << (tm_cond ? 3 : 4)) >> 8) - 32'(tm_dispx);
        tm_offy <= ((32'(tm_py) << (tm_cond ? 3 : 4)) >> 8) - 32'(tm_dispy);
    end

    // clip/flip start offsets: 16-bit x 22-bit products (one DSP each); the
    // low 32 bits match the 32-bit wrap-around arithmetic of the C model
    logic signed [15:0] clip_dx, clip_dy, span_w, span_h;
    logic signed [21:0] p_dx, p_dy;
    logic signed [37:0] clipx_prod, clipy_prod, spanx_prod, spany_prod;
    logic signed [15:0] endx, endy;
    always_ff @(posedge clk) begin
        clip_dx    <= cx0 - e_destx;
        clip_dy    <= cy0 - e_desty;
        span_w     <= $signed({3'b0, e_dstw} - 16'd1);
        span_h     <= $signed({3'b0, e_dsth} - 16'd1);
        p_dx       <= $signed({1'b0, e_dx[20:0]});
        p_dy       <= $signed({1'b0, e_dy[20:0]});
        clipx_prod <= clip_dx * p_dx;
        clipy_prod <= clip_dy * p_dy;
        spanx_prod <= span_w * p_dx;
        spany_prod <= span_h * p_dy;
        endx       <= e_destx + $signed({3'b0, e_dstw}) - 16'sd1;
        endy       <= e_desty + $signed({3'b0, e_dsth}) - 16'sd1;
    end
    wire [11:0] tm_xx = 12'(tm_x) + tm_srcx;
    wire [11:0] tm_yy = 12'(tm_y) + tm_srcy;
    wire [12:0] tm_cell_addr = tm_cond ? {tm_xx[7:0], tm_yy[4:0]}
                                       : {tm_yy[4], tm_xx[7:0], tm_yy[3:0]};

    always_ff @(posedge clk) begin
        fb_we <= 1'b0;
        px_step <= 1'b0;

        if (reset) begin
            state         <= S_IDLE;
            pend_cnt      <= '0;
            gfx_req       <= 1'b0;
            cache_valid   <= 1'b0;
            pf_valid      <= 1'b0;
            phase1        <= 1'b0;
            ram_addr      <= '0;
        end else begin
            // queue of starts: +1 for a go, -1 when S_IDLE takes a queued one
            begin
                logic take_q;
                take_q = (state == S_IDLE) && start_pending;
                if (start && !(state == S_IDLE && !start_pending)) begin
                    if (!start_pending || take_q) pend_list <= gfxlist;
                    if (!take_q && pend_cnt != 2'd3) pend_cnt <= pend_cnt + 2'd1;
                end else if (take_q)
                    pend_cnt <= pend_cnt - 2'd1;
            end

            // fetch unit: a row arrives -> prefetch buffer
            if (gfx_req && gfx_ack) begin
                gfx_req  <= 1'b0;
                pf_valid <= 1'b1;
                pf_addr  <= gfx_addr;
                pf_data  <= gfx_data;
            end

            case (state)
            // --------------------------------------------------------------
            S_IDLE: if (start_pending || start) begin
                offs          <= start_pending ? {pend_list, 3'b000} : {gfxlist, 3'b000};
                cb_n          <= '0;
                has_tm        <= 1'b0;
                phase1        <= 1'b1;
                state         <= S_CHECK;
            end

            S_CHECK: begin
                if (offs >= 19'h8000) begin                 // list always ends at RAM end
                    tc_issue <= '0;
                    tc_p1v   <= 1'b0;
                    tc_p2v   <= 1'b0;
                    if (has_tm) state <= S_TM_COPY;
                    else begin
                        phase1 <= 1'b0;
                        state  <= S_P2_WAIT;
                    end
                end
                else begin
                    issue_k <= 4'd0;
                    seq_end <= 4'd4;                          // phase A: words 6,7,10,13
                    p1_valid <= 1'b0;
                    p2_valid <= 1'b0;
                    state   <= S_CMD_RD;
                end
            end

            S_NEXT_CMD: begin
                offs  <= offs + 19'd16;
                state <= S_CHECK;
            end

            // Pipelined command read: one address per clock, data 2 clocks later.
            // Phase A reads the size/zoom words so disabled commands (most of
            // the list) are skipped after 4 reads; phase B reads the rest.
            S_CMD_RD: begin
                if (issue_k < seq_end) begin
                    ram_addr <= 15'(offs + 19'(word_seq(issue_k)));
                    p1_valid <= 1'b1;
                    p1_idx   <= word_seq(issue_k);
                    issue_k  <= issue_k + 4'd1;
                end else
                    p1_valid <= 1'b0;
                p2_valid <= p1_valid;
                p2_idx   <= p1_idx;
                if (p2_valid) begin
                    case (p2_idx)
                        4'd1: w1 <= ram_q;   4'd2: w2 <= ram_q;   4'd3: w3 <= ram_q;
                        4'd4: w4 <= ram_q;   4'd5: w5 <= ram_q;   4'd6: w6 <= ram_q;
                        4'd7: w7 <= ram_q;   4'd8: w8 <= ram_q;   4'd9: w9 <= ram_q;
                        4'd10: w10 <= ram_q;
                        default: w13 <= ram_q;
                    endcase
                    if (p2_idx == word_seq(seq_end - 4'd1))
                        state <= (seq_end == 4'd4) ? S_CMD_EARLY : S_SNAP_STORE;
                end
            end

            // phase 1: keep a copy of each valid command
            S_SNAP_STORE: begin
                cb_n         <= cb_n + 12'd1;
                if (w4[3]) has_tm <= 1'b1;
                state        <= S_NEXT_CMD;
            end

            // phase 1b: lists with tilemaps also snapshot tilemap RAM (8K words)
            S_TM_COPY: begin
                if (!tc_issue[13]) begin
                    ram_addr <= {2'b00, tc_issue[12:0]};
                    tc_p1v   <= 1'b1;
                    tc_p1a   <= tc_issue[12:0];
                    tc_issue <= tc_issue + 14'd1;
                end else
                    tc_p1v <= 1'b0;
                tc_p2v <= tc_p1v;
                tc_p2a <= tc_p1a;
                if (tc_p2v) begin
                    if (tc_p2a == 13'h1fff) begin
                        phase1 <= 1'b0;
                        state  <= S_P2_WAIT;
                    end
                end
            end

            // phase 2: draw the snapshot (waits while the frame buffer copy runs)
            S_P2_WAIT: if (!hold) begin
                cb_rd <= '0;
                state <= S_P2_FETCH;
            end

            S_P2_FETCH: state <= (cb_rd == cb_n) ? S_IDLE : S_P2_LOAD;   // cb_q valid next clock

            S_P2_LOAD: begin
                {w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w13} <= cb_q;
                state <= S_CMD_DEC;
            end

            S_P2_NEXT: begin
                cb_rd <= cb_rd + 12'd1;
                state <= S_P2_FETCH;
            end

            S_CMD_EARLY: begin
                // both sizes 0 = disabled; range checks reject power-on garbage
                if ((w6 == 16'd0 && w7 == 16'd0) || w6 >= 16'd512 || w7 >= 16'd256 ||
                    w10 >= 16'h1f0 || w13 >= 16'h1f0)
                    state <= S_NEXT_CMD;
                else begin
                    seq_end <= 4'd11;                         // phase B: 1,2,3,4,5,8,9
                    state   <= S_CMD_RD;
                end
            end

            S_CMD_DEC: begin
                logic signed [15:0] sxa, sya;
                sxa = $signed({7'b0, w2[12:4]}) - ((w2[12:4] >= 9'h180) ? 16'sd512 : 16'sd0);
                sya = $signed({7'b0, w3[12:4]}) - (w3[12]               ? 16'sd512 : 16'sd0);
                color <= w5[6:0];
                if (flip) begin
                    sx <= 16'sd383 - sxa - $signed(w6);
                    sy <= 16'sd255 - sya - $signed(w7);
                    fx <= !w4[0];
                    fy <= !w4[1];
                end else begin
                    sx <= sxa;  sy <= sya;
                    fx <= w4[0]; fy <= w4[1];
                end
                // both sizes 0 = disabled; range checks reject power-on garbage
                if ((w6 == 16'd0 && w7 == 16'd0) || w6 >= 16'd512 || w7 >= 16'd256 ||
                    w10 >= 16'h1f0 || w13 >= 16'h1f0)
                    state <= S_P2_NEXT;
                else
                    state <= S_CMD_CLIP;
            end

            S_CMD_CLIP: begin
                logic signed [15:0] ex, ey;
                ex = sx + $signed(w6);
                ey = sy + $signed(w7);
                cx0 <= (sx > VIS_X0) ? sx : VIS_X0;
                cx1 <= (ex < VIS_X1) ? ex : VIS_X1;
                cy0 <= (sy > VIS_Y0) ? sy : VIS_Y0;
                cy1 <= (ey < VIS_Y1) ? ey : VIS_Y1;
                state <= S_DISPATCH;
            end

            S_DISPATCH: begin
                if (cx0 > cx1 || cy0 > cy1) state <= S_P2_NEXT;      // nothing visible
                else if (w4[3])             state <= S_TM_SETUP;
                else if (w10 <= 16'd1 && w13 <= 16'd1) begin
                    // fill: one tile at 256x (16*4096/... -> 4096 px wide, step 1/256)
                    e_code <= w1; e_tile <= tile_of(w1, big_gfx); e_color <= w5[6:0]; e_fx <= fx; e_fy <= fy;
                    e_destx <= sx; e_desty <= sy;
                    e_dstw <= 13'd4096; e_dsth <= 13'd4096;
                    e_dx <= 32'sd256;   e_dy <= 32'sd256;
                    e_shadow <= shadow_en;
                    ret_state <= S_IDLE;           // marker: go to next command
                    state <= S_D_PRE0;
                end else begin
                    spr_n    <= 6'((w6 + 16'd15) >> 4);
                    spr_i    <= 6'd0;
                    spr_code <= w1;
                    spr_w    <= width_for_zoom(w10);
                    spr_h    <= width_for_zoom(w13);
                    if (((w6 + 16'd15) >> 4) == 16'd0) state <= S_P2_NEXT;
                    else begin
                        e_code <= w1; e_tile <= tile_of(w1, big_gfx); e_color <= w5[6:0]; e_fx <= fx; e_fy <= fy;
                        e_destx <= sx; e_desty <= sy;
                        e_dstw <= 13'(width_for_zoom(w10)); e_dsth <= 13'(width_for_zoom(w13));
                        e_dx <= $signed(dx_for_width(width_for_zoom(w10)));
                        e_dy <= $signed(dx_for_width(width_for_zoom(w13)));
                        e_shadow <= shadow_en;
                        ret_state <= S_SPR_NEXT;
                        state <= S_D_PRE0;
                    end
                end
            end

            S_SPR_NEXT: begin
                logic [15:0] nc;
                nc = (spr_code[3:0] == 4'hf) ? ((spr_code + 16'h100) & 16'hfff0) : spr_code + 16'd1;
                spr_code <= nc;
                if (spr_i + 6'd1 == spr_n) state <= S_P2_NEXT;
                else begin
                    spr_i   <= spr_i + 6'd1;
                    e_code  <= nc;
                    e_tile  <= tile_of(nc, big_gfx);
                    e_dx    <= $signed(dx_for_width(spr_w));   // undo any flip negation
                    e_dy    <= $signed(dx_for_width(spr_h));
                    e_destx <= sx + $signed({6'b0, spr_i + 6'd1, 4'b0});
                    e_desty <= sy;
                    ret_state <= S_SPR_NEXT;
                    state   <= S_D_PRE0;
                end
            end

            // --------------------------------------------------------------
            S_TM_SETUP: begin
                logic [11:0] bx, by;
                bx = w8[15:4];
                by = w9[15:4];
                tm_dispx <= bx[3:0];
                tm_dispy <= by[3:0];
                tm_cond  <= w4[2];
                if (w4[2]) begin
                    tm_w <= 8'((((w6 + 16'd15) >> 4) + 16'd1) << 1);
                    tm_h <= 8'((((w7 + 16'd15) >> 4) + 16'd1) << 1);
                    tm_srcx <= bx >> 3;
                    tm_srcy <= by >> 3;
                end else begin
                    tm_w <= 8'(((w6 + 16'd15) >> 4) + 16'd1);
                    tm_h <= 8'(((w7 + 16'd15) >> 4) + 16'd1);
                    tm_srcx <= bx >> 4;
                    tm_srcy <= by >> 4;
                end
                tm_x  <= '0;
                tm_y  <= '0;
                state <= S_TM_CELL;
            end

            S_TM_CELL: begin
                tm_raddr <= tm_cell_addr;
                rd_wait  <= 2'd0;
                state    <= S_TM_RD;
            end

            S_TM_RD: begin
                if (rd_wait != 2'd2) rd_wait <= rd_wait + 2'd1;
                else begin
                    tm_tile <= tm_q;
                    state   <= S_TM_POS;
                end
            end

            S_TM_POS: begin
                e_code   <= {w1[15:12], tm_tile[11:0]};
                e_tile   <= tile_of({w1[15:12], tm_tile[11:0]}, big_gfx);
                e_color  <= {color[6:4], tm_tile[15:12]};
                e_fx     <= fx;
                e_fy     <= fy;
                e_destx  <= fx ? (sx + $signed(w6) - 16'sd15 - $signed(tm_offx[15:0])) : (sx + $signed(tm_offx[15:0]));
                e_desty  <= fy ? (sy + $signed(w7) - 16'sd15 - $signed(tm_offy[15:0])) : (sy + $signed(tm_offy[15:0]));
                e_dstw   <= 13'd16;  e_dsth <= 13'd16;
                e_dx     <= 32'sd65536; e_dy <= 32'sd65536;
                e_shadow <= 1'b0;                // tilemaps: pen 15 transparent only
                ret_state <= S_TM_NEXT;
                state    <= S_D_PRE0;
            end

            S_TM_NEXT: begin
                if (tm_x + 8'd1 != tm_w) begin
                    tm_x  <= tm_x + 8'd1;
                    state <= S_TM_CELL;
                end else if (tm_y + 8'd1 != tm_h) begin
                    tm_x  <= '0;
                    tm_y  <= tm_y + 8'd1;
                    state <= S_TM_CELL;
                end else
                    state <= S_P2_NEXT;
            end

            // --------------------------------------------------------------
            // Draw engine: one tile, scaled, clipped to cx0..cx1 / cy0..cy1
            // --------------------------------------------------------------
            S_D_PRE0: state <= S_D_PRE1;       // let the clip/flip pipeline settle
            S_D_PRE1: state <= S_D_SETUP;

            S_D_SETUP: begin
                if (e_destx > cx1 || endx < cx0 || e_desty > cy1 || endy < cy0)
                    state <= draw_return(ret_state);
                else begin
                    d_x0   <= (e_destx < cx0) ? cx0 : e_destx;
                    d_srcx <= (e_destx < cx0) ? clipx_prod[31:0] : 32'sd0;
                    d_x1   <= (endx > cx1) ? cx1 : endx;
                    d_y0   <= (e_desty < cy0) ? cy0 : e_desty;
                    d_srcy <= (e_desty < cy0) ? clipy_prod[31:0] : 32'sd0;
                    d_y1   <= (endy > cy1) ? cy1 : endy;
                    state  <= S_D_SETUP2;
                end
            end

            S_D_SETUP2: begin
                if (e_fx) begin
                    d_srcx <= spanx_prod[31:0] - d_srcx;
                    e_dx   <= -e_dx;
                end
                if (e_fy) begin
                    d_srcy <= spany_prod[31:0] - d_srcy;
                    e_dy   <= -e_dy;
                end
                d_cury <= d_y0;
                state  <= S_D_ROW;
            end

            S_D_ROW: begin
                if (d_cury > d_y1) state <= draw_return(ret_state);
                else if (cache_valid && cache_addr == row_addr) state <= S_D_PIXSTART;
                else if (pf_valid && pf_addr == row_addr) begin
                    row_data    <= pf_data;
                    cache_addr  <= pf_addr;
                    cache_valid <= 1'b1;
                    state       <= S_D_PIXSTART;
                end else if (!gfx_req) begin
                    gfx_req  <= 1'b1;                       // fetch, then wait here
                    gfx_addr <= row_addr;
                end
            end

            S_D_PIXSTART: begin
                d_curx    <= d_x0;
                d_cursrcx <= d_srcx;
                d_fbrow   <= 17'(32'(d_cury - VIS_Y0) * 32'sd384);
                // prefetch the next row of this tile while this one is drawn
                if (d_cury != d_y1 && next_row_addr != cache_addr && !gfx_req &&
                    !(pf_valid && pf_addr == next_row_addr)) begin
                    gfx_req  <= 1'b1;
                    gfx_addr <= next_row_addr;
                end
                state     <= S_D_PIX;
            end

            S_D_PIX: begin
                if (pen != 4'hf) begin
                    fb_addr <= pix_addr;
                    if (pen == 4'he && e_shadow)
                        state <= S_D_SH1;                 // read-modify-write
                    else begin
                        fb_we    <= 1'b1;
                        fb_wdata <= {1'b0, e_color, pen};
                    end
                end
                if (!(pen == 4'he && e_shadow)) begin advance_pixel(); px_step <= 1'b1; end
            end

            S_D_SH1: state <= S_D_SH2;                   // fb_rdata arrives next clock

            S_D_SH2: begin
                fb_we    <= 1'b1;
                fb_wdata <= shadow_of(fb_rdata);
                state    <= S_D_PIX;
                advance_pixel();
                px_step  <= 1'b1;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    // next pixel / next row bookkeeping (called from S_D_PIX and S_D_SH2)
    task automatic advance_pixel();
        if (d_curx == d_x1) begin
            d_cury <= d_cury + 16'sd1;
            d_srcy <= d_srcy + e_dy;
            state  <= S_D_ROW;
        end else begin
            d_curx    <= d_curx + 16'sd1;
            d_cursrcx <= d_cursrcx + e_dx;
            state     <= S_D_PIX;
        end
    endtask

    // after a tile: ret_state S_IDLE is used as "go to next command"
    function automatic state_t draw_return(input state_t r);
        draw_return = (r == S_IDLE) ? S_P2_NEXT : r;
    endfunction

endmodule
