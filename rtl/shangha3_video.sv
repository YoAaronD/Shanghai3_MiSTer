// Shanghai III frame buffers and video output
//
// Two 384 x 224 x 12-bit buffers in block RAM:
//   draw buffer    - the blitter's persistent canvas (never cleared, as on the PCB)
//   display buffer - what is scanned out to the screen
// At the start of vblank the draw buffer is copied to the display buffer
// (86016 clocks = 0.9 ms at 96 MHz; vblank lasts 2.5 ms). The blitter is held
// off while the copy runs. This gives tear-free output with the same frame
// timing as MAME (the frame shows what was drawn before vblank).
// How the real PCB buffers its frames is unknown.
//
// Scan-out: frame buffer entry -> palette RAM (RGBx_555) -> 8-bit RGB.
// Entries with bit 11 set use the darkened shadow bank (x0.6, as in MAME).

module shangha3_video (
    input  logic        clk,
    input  logic        reset,
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
    output logic [7:0]  blue
);
    localparam int FB_SIZE = 384 * 224;

    // ------------------------------------------------------------------
    // Draw buffer: port A = blitter (read/write), port B = copy (read)
    // ------------------------------------------------------------------
    logic [11:0] fb_draw [0:FB_SIZE-1];
    logic [16:0] cp_raddr;
    logic [11:0] cp_q;

    always_ff @(posedge clk) begin
        if (fb_we) fb_draw[fb_addr] <= fb_wdata;
        fb_rdata <= fb_draw[fb_addr];
    end
    always_ff @(posedge clk) cp_q <= fb_draw[cp_raddr];

    // ------------------------------------------------------------------
    // Display buffer: port A = copy (write), port B = scan-out (read)
    // ------------------------------------------------------------------
    logic [11:0] fb_disp [0:FB_SIZE-1];
    logic [16:0] cp_waddr;
    logic        cp_we;
    logic [16:0] so_addr;
    logic [11:0] so_q;

    always_ff @(posedge clk) if (cp_we) fb_disp[cp_waddr] <= cp_q;
    always_ff @(posedge clk) so_q <= fb_disp[so_addr];

    // ------------------------------------------------------------------
    // vblank copy
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            copying  <= 1'b0;
            cp_raddr <= '0;
            cp_we    <= 1'b0;
        end else begin
            cp_we    <= copying;           // cp_q for cp_raddr arrives next clock
            cp_waddr <= cp_raddr;
            if (vblank_start) begin
                copying  <= 1'b1;
                cp_raddr <= '0;
            end else if (copying) begin
                if (cp_raddr == 17'(FB_SIZE - 1)) copying <= 1'b0;
                else cp_raddr <= cp_raddr + 17'd1;
            end
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

    always_comb begin
        nh = (hcnt == 9'd511) ? 9'd0 : hcnt + 9'd1;
        if (hcnt == 9'd511) nv = (vcnt == 9'd262) ? 9'd0 : vcnt + 9'd1;
        else                nv = vcnt;
        nvis = (nh < 9'd384) && (nv >= 9'd16) && (nv <= 9'd239);
    end

    function automatic logic [7:0] expand5(input logic [4:0] c, input logic dark);
        logic [7:0] c8;
        c8 = {c, c[4:2]};
        expand5 = dark ? 8'((16'(c8) * 16'd6) / 16'd10) : c8;
    endfunction

    always_ff @(posedge clk) begin
        if (reset || ce_pix) ph <= '0;
        else if (ph != 4'hf) ph <= ph + 4'd1;

        case (ph)
            4'd0: so_addr  <= 17'(32'(nv - 9'd16) * 32'd384 + 32'(nh));   // q at ph 2
            4'd2: begin pal_addr <= so_q[10:0]; sh <= so_q[11]; end       // pal_q at ph 4
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
