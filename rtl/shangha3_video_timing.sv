// Shanghai III video timing
//
// Source: MAME shangha3.cpp, screen->set_raw(48_MHz_XTAL / 6, 512, 0, 384, 263, 16, 240)
//   pixel clock 8 MHz, 512 pixels per line, 263 lines per frame
//   visible area 384 x 224 (lines 16..239)
//   -> 59.41 Hz refresh. MAME notes "refresh rate is unknown" - verify on PCB later.
//
// HSYNC / VSYNC positions are NOT known (MAME doesn't need them). The values
// below are placeholders chosen to give a standard ~15.6 kHz signal; they
// should be measured on the real board eventually.

module shangha3_video_timing (
    input  logic       clk,
    input  logic       reset,
    input  logic       ce_pix,       // 8 MHz pixel clock enable

    output logic [8:0] hcnt,         // 0..511
    output logic [8:0] vcnt,         // 0..262
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       vblank_start, // one-clock pulse at start of vblank (IRQ4)
    output logic       vblank_next   // vblank state of the NEXT line (for CRT Adjust)
);

    localparam int H_TOTAL   = 512;
    localparam int H_VISIBLE = 384;
    localparam int HS_START  = 416;  // placeholder
    localparam int HS_END    = 448;  // placeholder (4 us)

    localparam int V_TOTAL   = 263;
    localparam int V_FIRST   = 16;   // first visible line
    localparam int V_LAST    = 239;  // last visible line
    localparam int VS_START  = 244;  // placeholder
    localparam int VS_END    = 247;  // placeholder (3 lines)

    always_ff @(posedge clk) begin
        vblank_start <= 1'b0;
        if (reset) begin
            hcnt <= '0;
            vcnt <= '0;
        end else if (ce_pix) begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= '0;
                if (vcnt == V_TOTAL - 1) vcnt <= '0;
                else                     vcnt <= vcnt + 9'd1;
                if (vcnt == V_LAST)      vblank_start <= 1'b1;
            end else begin
                hcnt <= hcnt + 9'd1;
            end
        end
    end

    assign hblank = (hcnt >= H_VISIBLE);
    assign vblank = (vcnt < V_FIRST) || (vcnt > V_LAST);
    wire [8:0] vnext = (vcnt == V_TOTAL - 1) ? 9'd0 : vcnt + 9'd1;
    assign vblank_next = (vnext < V_FIRST) || (vnext > V_LAST);
    assign hsync  = (hcnt >= HS_START) && (hcnt < HS_END);
    assign vsync  = (vcnt >= VS_START) && (vcnt < VS_END);

endmodule
