// OSD bench top: the core's video timing -> CRT Adjust (as in SunsoftGA9201.sv)
// -> the MiSTer framework's own sys/osd.v, with the HPS side driven by
// osd_tb.cpp the way Main_MiSTer draws its "Loading" info box.
// Approximates arcade_video (Scandoubler Fx None) as DE = !(HBlank | VBlank).
module osd_top (
    input  logic        clk,            // 96 MHz: clk_sys = CLK_VIDEO
    input  logic        reset,
    input  logic        crt_on,
    input  logic [4:0]  crt_hsize,
    input  logic [3:0]  crt_hpos,
    input  logic [3:0]  crt_vshift,
    input  logic        io_osd,
    input  logic        io_strobe,
    input  logic [15:0] io_din,
    output logic [23:0] dout,
    output logic        de_out,
    output logic        hs_out,
    output logic        vs_out,
    output logic        ce_vid
);
    logic [3:0] pix_div;
    always_ff @(posedge clk) pix_div <= reset ? 4'd0 : (pix_div == 4'd11) ? 4'd0 : pix_div + 4'd1;
    wire ce_pix = (pix_div == 4'd11);

    logic hbl, vbl, hs, vs, vbl_next;
    shangha3_video_timing timing (
        .clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(), .vcnt(),
        .hblank(hbl), .vblank(vbl), .hsync(hs), .vsync(vs), .vblank_start(), .vblank_next(vbl_next)
    );

    logic vs_d;
    always_ff @(posedge clk) vs_d <= vs;
    wire av_ce, av_hb, av_vb, av_hs, av_vs;
    wire [23:0] av_rgb;
    s3_crt_adjust #(.SYS_HZ(96_000_000), .PIX_DIV(12), .HTOTAL(512), .VTOTAL(262)) crt_adjust (
        .clk_sys(clk), .ce_pix(ce_pix), .frame_event(vs && !vs_d),
        .osd_on(crt_on), .osd_hsize(crt_hsize), .osd_hpos(crt_hpos), .osd_vshift(crt_vshift),
        .sd_off(1'b1), .rgb_in(24'h000000),               // black: the board is in reset while loading
        .hblank_in(hbl), .vblank_in(vbl), .hsync_in(hs), .vsync_in(vs), .vb_next_in(vbl_next),
        .ce_out(av_ce), .rgb_out(av_rgb), .hblank_out(av_hb), .vblank_out(av_vb),
        .hsync_out(av_hs), .vsync_out(av_vs), .active()
    );

    // arcade_video / video_mixer with no scandoubler: registered on the pixel enable
    logic [23:0] v_rgb; logic v_de, v_hs, v_vs;
    always_ff @(posedge clk) if (av_ce) begin
        v_rgb <= av_rgb; v_de <= !(av_hb | av_vb); v_hs <= av_hs; v_vs <= av_vs;
    end
    assign ce_vid = av_ce;

    osd vga_osd (
        .clk_sys(clk), .io_osd(io_osd), .io_strobe(io_strobe), .io_din(io_din),
        .clk_video(clk), .din(v_rgb), .de_in(v_de), .vs_in(v_vs), .hs_in(v_hs),
        .dout(dout), .de_out(de_out), .vs_out(vs_out), .hs_out(hs_out), .osd_status()
    );
endmodule
