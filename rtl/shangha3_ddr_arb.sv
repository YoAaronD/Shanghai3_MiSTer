// DDR3 (MiSTer DDRAM port) sharing between two masters:
//   A: the core's display frame buffer (shangha3_video): Avalon-MM with
//      waitrequest, write bursts of up to 255 beats and read bursts.
//   B: the framework's screen_rotate (HDMI rotation, sys/arcade_video.v):
//      single-beat writes, one-clock pulses, no back-pressure.
// B's writes are queued in a 64-entry FIFO and sent between A's bursts, so an
// A burst is never split. All read data belongs to A (B never reads).
// Command grant is registered: a request is presented unchanged until the
// DDR3 bridge accepts it (Avalon rule), then the arbiter returns to IDLE.
// B is preferred when both wait; it only writes during active video, when A
// only reads (one line per scan line), so neither starves. If the FIFO is
// ever full, B's pixel is dropped, the same as screen_rotate does on its own
// when the bridge is busy (it never looks at DDRAM_BUSY).

module shangha3_ddr_arb (
    input  logic        clk,
    input  logic        reset,

    // master A (full Avalon-MM)
    output logic        a_busy,
    input  logic [7:0]  a_burstcnt,
    input  logic [28:0] a_addr,
    output logic [63:0] a_dout,
    output logic        a_dout_ready,
    input  logic        a_rd,
    input  logic [63:0] a_din,
    input  logic [7:0]  a_be,
    input  logic        a_we,

    // master B (screen_rotate: single-beat write pulses)
    input  logic        b_we,
    input  logic [28:0] b_addr,
    input  logic [63:0] b_din,
    input  logic [7:0]  b_be,

    // DDRAM port
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
    // ------------------------------------------------------------------
    // B FIFO. screen_rotate writes 32-bit pixels as {d, d} with BE = 0F or
    // F0, so only the address, the 32-bit pixel and the half are stored.
    // ------------------------------------------------------------------
    (* ramstyle = "MLAB, no_rw_check" *) logic [61:0] bf [0:63];
    logic [6:0]  bf_wp, bf_rp;
    wire  [6:0]  bf_cnt   = bf_wp - bf_rp;
    wire         bf_empty = (bf_cnt == 7'd0);
    wire         bf_full  = (bf_cnt == 7'd64);
    logic [61:0] bf_head;
    logic        bf_pop;

    always_ff @(posedge clk) if (b_we && !bf_full) bf[bf_wp[5:0]] <= {b_addr, b_be[7], b_din[31:0]};
    assign bf_head = bf[bf_rp[5:0]];

    always_ff @(posedge clk) begin
        if (reset) begin
            bf_wp <= '0;
            bf_rp <= '0;
        end else begin
            if (b_we && !bf_full) bf_wp <= bf_wp + 7'd1;
            if (bf_pop)           bf_rp <= bf_rp + 7'd1;
        end
    end

    // ------------------------------------------------------------------
    // Grant
    // ------------------------------------------------------------------
    typedef enum logic [1:0] { G_IDLE, G_B, G_AW, G_AR } grant_t;
    grant_t      g;
    logic [7:0]  beats_left;            // A write burst: beats still to send

    wire a_accept = !ddr_busy;          // the bridge takes the presented beat/command

    always_ff @(posedge clk) begin
        if (reset) begin
            g <= G_IDLE;
        end else begin
            case (g)
                G_IDLE:
                    if (!bf_empty)  g <= G_B;
                    else if (a_we)  begin g <= G_AW; beats_left <= a_burstcnt; end
                    else if (a_rd)  g <= G_AR;
                G_B:
                    if (a_accept) g <= G_IDLE;
                G_AW:
                    if (a_we && a_accept) begin
                        beats_left <= beats_left - 8'd1;
                        if (beats_left == 8'd1) g <= G_IDLE;
                    end
                G_AR:
                    if (a_accept) g <= G_IDLE;
                default: g <= G_IDLE;
            endcase
        end
    end

    assign bf_pop = (g == G_B) && a_accept;

    always_comb begin
        // defaults: nothing presented, A waits
        ddr_we       = 1'b0;
        ddr_rd       = 1'b0;
        ddr_addr     = a_addr;
        ddr_burstcnt = a_burstcnt;
        ddr_din      = a_din;
        ddr_be       = a_be;
        a_busy       = 1'b1;
        case (g)
            G_B: begin
                ddr_we       = 1'b1;
                ddr_addr     = bf_head[61:33];
                ddr_burstcnt = 8'd1;
                ddr_din      = {bf_head[31:0], bf_head[31:0]};
                ddr_be       = bf_head[32] ? 8'hF0 : 8'h0F;
            end
            G_AW: begin
                ddr_we = a_we;
                a_busy = ddr_busy;
            end
            G_AR: begin
                ddr_rd = a_rd;
                a_busy = ddr_busy;
            end
            default: ;
        endcase
    end

    assign a_dout       = ddr_dout;
    assign a_dout_ready = ddr_dout_ready;
endmodule
