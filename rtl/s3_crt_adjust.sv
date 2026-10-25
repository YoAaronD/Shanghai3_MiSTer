// Shanghai III MiSTer core -- CRT Adjust glue
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Adapted from Kyle Lester's Nostradamus core (rtl/nost/nost_crt_adjust.sv,
// github.com/kyledlester/Nostradamus_Magical_Cat_Adventure_MiSTer), itself from
// his hardware-confirmed Namco NA-1/NA-2 integration. Changed here: module name,
// raster parameters, and the H-Position limit table, which depends on the raster.
// Wraps the UNMODIFIED upstream rtl/vendor/crt_adjust.sv
// (MiSTer-CRT-Adjust @c682de9, Umberto Parisi / rmonic79, GPL-3.0-or-later).
//
// OSD bits:
//   [96]      CRT Adjust Off / On (Off = default = TRUE bypass: native stream, zero latency)
//   [116:112] H-Size index -> -12..+10, one step = 1 % (+ = wider)
//   [104:101] H-Position signed -8..+7, one step = 6 pixels (module HPOS_SYNCSHIFT)
//   [108:105] V-Shift    signed -8..+7, one step = 1 line
// Controls are sampled once per frame (frame_event, inside vertical blanking). The adjust
// is gated off while the scandoubler is active. Read CE: the real pixel CE while H-Size
// is 0, else an exact rational NCO READ_INC = PIXEL_HZ - hsize * STEP, STEP = PIXEL_HZ / 100.
module s3_crt_adjust #(
    parameter integer SYS_HZ  = 96_000_000,
    parameter integer PIX_DIV = 12,
    parameter integer HTOTAL  = 512,
    parameter integer VTOTAL  = 262
) (
    input  wire        clk_sys,
    input  wire        ce_pix,
    input  wire        frame_event,     // one pulse per frame, inside vertical blanking
    input  wire        osd_on,          // status[96]
    input  wire [4:0]  osd_hsize,       // status[116:112]
    input  wire [3:0]  osd_hpos,        // status[104:101]
    input  wire [3:0]  osd_vshift,      // status[108:105]
    input  wire        sd_off,          // scandoubler off (Fx None and not forced)
    input  wire [23:0] rgb_in,
    input  wire        hblank_in,
    input  wire        vblank_in,
    input  wire        hsync_in,
    input  wire        vsync_in,
    input  wire        vb_next_in,      // vertical blank of the line after the current one
    output wire        ce_out,
    output wire [23:0] rgb_out,
    output wire        hblank_out,
    output wire        vblank_out,
    output wire        hsync_out,
    output wire        vsync_out,
    output wire        active
);
    reg crt_on = 1'b0;
    reg signed [4:0] hsize_s = 5'sd0;
    reg signed [3:0] hpos_s  = 4'sd0;
    reg signed [3:0] vsh_s   = 4'sd0;
    always @(posedge clk_sys) if (frame_event) begin
        crt_on  <= osd_on;
        hsize_s <= (osd_hsize <= 5'd10) ? $signed(osd_hsize)
                 : (osd_hsize <= 5'd22) ? $signed(osd_hsize - 5'd23)
                 : 5'sd0;
        hpos_s  <= $signed(osd_hpos);
        vsh_s   <= $signed(osd_vshift);
    end
    assign active = crt_on && sd_off;

    // H-Position limits for the Shanghai III raster (512 dots: active 0..383, HSync rises at
    // 416 - a placeholder until measured on the PCB). In HPOS_SYNCSHIFT the module records each
    // line from its shifted HSync (rise at 416 + 6p) to the next, so:
    //   (a) the shifted HSync must stay in the horizontal blank: 416 + 6p >= 384 -> p >= -5
    //   (b) the widened read-out, ending (480 - 6p) / (1 - h/100) dots after it, must end
    //       before the next HSync (512 dots).
    // Settings beyond the limit are clamped (the picture stops moving). Checked in simulation
    // over every H-Size at both H-Position extremes (sim/tb_crt.sv, scripts/crt_test.sh).
    // If HS_START in shangha3_video_timing.sv changes, recompute this table.
    reg signed [3:0] lmax;
    always_comb begin
        case (hsize_s)
            5'sd1:  lmax = -4'sd4;
            5'sd2:  lmax = -4'sd3;
            5'sd3:  lmax = -4'sd2;
            5'sd4:  lmax = -4'sd1;
            5'sd5:  lmax = 4'sd0;     // formula gives -1 with only 0.4 dot margin; bench shows the last pixel cut
            5'sd6:  lmax = 4'sd0;
            5'sd7:  lmax = 4'sd1;
            5'sd8:  lmax = 4'sd2;
            5'sd9:  lmax = 4'sd3;
            5'sd10: lmax = 4'sd4;
            default: lmax = -4'sd5;     // H-Size 0 and narrower pictures
        endcase
    end
    reg signed [3:0] hpos_c = 4'sd0;
    always @(posedge clk_sys) hpos_c <= (hpos_s < lmax) ? lmax : hpos_s;   // frame-stable inputs
    // sign-extended explicitly (a bare size cast of a signed value evaluates unsigned)
    wire signed [8:0] hoffset = active ? ($signed({{5{hpos_c[3]}}, hpos_c}) * 9'sd6) : 9'sd0;
    wire signed [5:0] voffset = active ? $signed({{2{vsh_s[3]}}, vsh_s}) : 6'sd0;

    localparam integer PIXEL_HZ = SYS_HZ / PIX_DIV;
    localparam integer STEP     = (PIXEL_HZ + 50) / 100;
    wire hs_ref;
    reg  hs_ref_d = 1'b0;
    always @(posedge clk_sys) hs_ref_d <= hs_ref;
    wire hs_ref_rise = hs_ref && !hs_ref_d;
    // registered: hsize_s changes only at a frame event, so one clock late is exact (timing)
    reg  signed [31:0] read_inc = PIXEL_HZ;
    always @(posedge clk_sys) read_inc <= PIXEL_HZ - (hsize_s * STEP);
    reg  [26:0] phase = 27'd0;
    wire [27:0] phase_sum = {1'b0, phase} + read_inc[26:0];
    wire rd_tick = (phase_sum >= SYS_HZ);
    always @(posedge clk_sys) begin
        if (hs_ref_rise)  phase <= 27'd0;
        else if (rd_tick) phase <= phase_sum - SYS_HZ;
        else              phase <= phase_sum[26:0];
    end
    reg use_nco = 1'b0;
    always @(posedge clk_sys) use_nco <= active && (hsize_s != 5'sd0);
    wire rd_ce = use_nco ? rd_tick : ce_pix;

    // Vertical blank: the module fills its line buffer in windows that start at its (possibly
    // shifted) HSync and emits each line one window later. vb_wr = blank of the line whose
    // active dots follow, latched at the end of the previous active area, so every HSync
    // position inside the horizontal blank samples the right line; the vertical blank sent on
    // is that of the line being READ (one window later).
    reg hb_in_d = 1'b1, vb_wr = 1'b1;
    always @(posedge clk_sys) if (ce_pix) begin
        hb_in_d <= hblank_in;
        if (hblank_in && !hb_in_d) vb_wr <= vb_next_in;
    end
    reg hs_ref_q = 1'b0, vb_l1 = 1'b1, vb_rd = 1'b1;
    always @(posedge clk_sys) if (ce_pix) begin
        hs_ref_q <= hs_ref;
        if (hs_ref && !hs_ref_q) begin vb_l1 <= vb_wr; vb_rd <= vb_l1; end
    end

    wire [23:0] a_rgb;
    wire a_hs, a_vs, a_hb, a_vb;
    crt_adjust #(.VTOTAL(VTOTAL), .HTOTAL(HTOTAL), .HPOS_MODE(0)) crt_adjust (
        .clk(clk_sys), .pxl_cen(ce_pix), .pxl2_cen(rd_ce),
        .active(active),
        .hsize(hsize_s), .hoffset(hoffset), .voffset(voffset),
        .r_in(rgb_in[23:16]), .g_in(rgb_in[15:8]), .b_in(rgb_in[7:0]),
        .hs_in(hsync_in), .vs_in(vsync_in), .hb_in(hblank_in), .vb_in(vb_wr),
        .r_out(a_rgb[23:16]), .g_out(a_rgb[15:8]), .b_out(a_rgb[7:0]),
        .hs_out(a_hs), .vs_out(a_vs), .hb_out(a_hb), .vb_out(a_vb),
        .hs_ref_out(hs_ref));

    // TRUE bypass when Off: the native stream, zero added latency
    assign ce_out     = active ? rd_ce : ce_pix;
    assign rgb_out    = active ? a_rgb : rgb_in;
    assign hblank_out = active ? a_hb  : hblank_in;
    assign vblank_out = active ? vb_rd : vblank_in;
    assign hsync_out  = active ? a_hs  : hsync_in;
    assign vsync_out  = active ? a_vs  : vsync_in;
endmodule
