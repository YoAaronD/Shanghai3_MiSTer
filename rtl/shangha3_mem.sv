// Shanghai III ROM storage in SDRAM
//
// SDRAM layout (bytes):
//   000000-07FFFF  68000 program, big-endian 16-bit words
//   080000-27FFFF  blitter graphics, byte order as in the ROM file
//   280000-2BFFFF  OKI M6295 samples
//
// ROM download (MRA, ioctl index 0) arrives as one byte stream:
//   000000-03FFFF  s3j_v11.ic3  -> program high bytes  (even addresses)
//   040000-07FFFF  s3j_v11.ic2  -> program low bytes   (odd addresses)
//   080000-27FFFF  s3j_char-a1.ic43
//   280000-2BFFFF  s3j_v10.ic75
// The two program EPROMs are interleaved here, with byte-masked SDRAM writes,
// so the MRA needs no <interleave> section.
//
// SDRAM channels (sdram.sv priority order: ch2, ch1, ch3, ch4):
//   ch2  CPU program ROM cache line fills (64-bit)
//   ch1  OKI sample bytes
//   ch3  download writes
//   ch4  blitter tile rows (64-bit)
//
// The 68000 reads through a 512-line x 4-word direct-mapped cache (32 KB of
// code), so sequential instruction fetches and loops don't wait on the SDRAM.

module shangha3_mem (
    input  logic        clk,
    input  logic        reset,
    output logic        ready,          // cache cleared; CPU may run

    // download
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,
    output logic        ioctl_wait,

    // board: program ROM
    input  logic [18:1] prog_addr,
    input  logic        prog_cs,
    output logic [15:0] prog_data,
    output logic        prog_ok,

    // board: blitter graphics
    input  logic        gfx_req,
    input  logic [17:0] gfx_addr,
    output logic        gfx_ack,
    output logic [63:0] gfx_data,

    // board: OKI samples
    input  logic [17:0] oki_rom_addr,
    output logic [7:0]  oki_rom_data,
    output logic        oki_rom_ok,

    // sdram.sv channels
    output logic [26:1] ch1_addr, output logic ch1_req, input logic [31:0] ch1_dout, input logic ch1_ready,
    output logic [26:1] ch2_addr, output logic ch2_req, input logic [63:0] ch2_dout, input logic ch2_ready,
    output logic [26:1] ch3_addr, output logic ch3_req, output logic [15:0] ch3_din,
    output logic [1:0]  ch3_be,   output logic ch3_rnw, input logic ch3_ready,
    output logic [26:1] ch4_addr, output logic ch4_req, input logic [63:0] ch4_dout, input logic ch4_ready
);
    localparam logic [26:0] GFX_BASE = 27'h080000;
    localparam logic [26:0] OKI_BASE = 27'h280000;

    // ------------------------------------------------------------------
    // Download: one byte-masked SDRAM write per byte
    // ------------------------------------------------------------------
    logic dl_busy;
    assign ch3_rnw = 1'b0;

    always_ff @(posedge clk) begin
        if (reset && !ioctl_download) begin
            dl_busy    <= 1'b0;
            ch3_req    <= 1'b0;
            ioctl_wait <= 1'b0;
        end else if (!dl_busy) begin
            if (ioctl_download && ioctl_wr && ioctl_index == 16'd0 && ioctl_addr < 27'h2C0000) begin
                logic [26:0] a;
                a = ioctl_addr;
                if (a < 27'h040000) begin              // ic3: program high bytes
                    ch3_addr <= a[25:0];                    // word a, high byte
                    ch3_be   <= 2'b10;
                end else if (a < 27'h080000) begin     // ic2: program low bytes
                    ch3_addr <= a[25:0] - 26'h040000;       // word a-0x40000, low byte
                    ch3_be   <= 2'b01;
                end else begin                         // graphics + samples: byte order kept
                    ch3_addr <= a[26:1];
                    ch3_be   <= a[0] ? 2'b10 : 2'b01;
                end
                ch3_din    <= {ioctl_dout, ioctl_dout};
                ch3_req    <= 1'b1;
                dl_busy    <= 1'b1;
                ioctl_wait <= 1'b1;
            end
        end else if (ch3_ready) begin
            ch3_req    <= 1'b0;
            dl_busy    <= 1'b0;
            ioctl_wait <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // CPU program ROM cache
    //   word address w = prog_addr[18:1]; line = w[17:2]; index = line[8:0]
    //   tag = line[15:9]
    // ------------------------------------------------------------------
    logic [63:0] c_data [0:511];
    logic [7:0]  c_tag  [0:511];         // {valid, tag[6:0]}
    logic [63:0] c_data_q;
    logic [7:0]  c_tag_q;
    logic [18:1] addr_q;
    logic        cs_q;

    wire  [8:0]  idx     = prog_addr[11:3];
    wire  [8:0]  idx_q   = addr_q[11:3];
    wire  [6:0]  tag_q   = addr_q[18:12];

    logic        inv_busy;
    logic [8:0]  inv_idx;
    logic        fill_busy;
    logic        fill_we, fill_we_d;   // tag read is stale for 2 clocks after a fill
    logic [63:0] fill_data;

    wire       tag_we    = fill_we || inv_busy;
    wire [8:0] tag_waddr = inv_busy ? inv_idx : idx_q;
    wire [7:0] tag_wdata = inv_busy ? 8'h00 : {1'b1, tag_q};

    always_ff @(posedge clk) begin
        c_data_q <= c_data[idx];
        c_tag_q  <= c_tag[idx];
        addr_q   <= prog_addr;
        cs_q     <= prog_cs;
        if (fill_we) c_data[idx_q] <= fill_data;
        if (tag_we)  c_tag[tag_waddr] <= tag_wdata;      // one write port: fill or invalidate
    end

    wire hit = cs_q && prog_cs && (addr_q == prog_addr) && !inv_busy && !fill_we && !fill_we_d &&
               (c_tag_q == {1'b1, tag_q});

    assign prog_ok   = hit;
    assign prog_data = c_data_q[{addr_q[2:1], 4'b0000} +: 16];
    assign ready     = !inv_busy;

    always_ff @(posedge clk) begin
        fill_we   <= 1'b0;
        fill_we_d <= fill_we;
        if (reset) begin
            inv_busy  <= 1'b1;
            inv_idx   <= '0;
            fill_busy <= 1'b0;
            ch2_req   <= 1'b0;
        end else if (inv_busy) begin
            inv_idx <= inv_idx + 9'd1;
            if (inv_idx == 9'd511) inv_busy <= 1'b0;
        end else if (!fill_busy) begin
            // miss: the registered lookup for the current address came back wrong
            if (cs_q && prog_cs && addr_q == prog_addr && !fill_we && !fill_we_d && c_tag_q != {1'b1, tag_q}) begin
                ch2_addr  <= {7'b0, addr_q[18:3], 3'b000} >> 1;   // line start, byte address >> 1
                ch2_req   <= 1'b1;
                fill_busy <= 1'b1;
            end
        end else if (ch2_ready) begin
            ch2_req   <= 1'b0;
            fill_busy <= 1'b0;
            fill_data <= ch2_dout;
            fill_we   <= 1'b1;               // written while addr_q still points at this line
        end
    end

    // ------------------------------------------------------------------
    // Blitter tile rows: gfx_addr = row index (8 bytes each)
    // ------------------------------------------------------------------
    logic gfx_busy;
    always_ff @(posedge clk) begin
        gfx_ack <= 1'b0;
        if (reset) begin
            gfx_busy <= 1'b0;
            ch4_req  <= 1'b0;
        end else if (!gfx_busy) begin
            if (gfx_req && !gfx_ack) begin   // not the cycle in which we ack the previous row
                ch4_addr <= 26'((GFX_BASE + {6'b0, gfx_addr, 3'b000}) >> 1);
                ch4_req  <= 1'b1;
                gfx_busy <= 1'b1;
            end
        end else if (ch4_ready) begin
            ch4_req  <= 1'b0;
            gfx_busy <= 1'b0;
            gfx_data <= ch4_dout;
            gfx_ack  <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // OKI samples: one byte at a time; ok only while the address is unchanged
    // ------------------------------------------------------------------
    logic        oki_busy;
    logic [17:0] oki_cur, oki_req_addr;
    always_ff @(posedge clk) begin
        if (reset) begin
            oki_busy   <= 1'b0;
            ch1_req    <= 1'b0;
            oki_rom_ok <= 1'b0;
            oki_cur    <= '1;
        end else begin
            if (oki_rom_addr != oki_cur) begin
                oki_cur    <= oki_rom_addr;
                oki_rom_ok <= 1'b0;
            end
            if (!oki_busy) begin
                if (!oki_rom_ok && oki_rom_addr == oki_cur) begin
                    oki_req_addr <= oki_cur;
                    ch1_addr     <= 26'((OKI_BASE + {9'b0, oki_cur}) >> 1);
                    ch1_req      <= 1'b1;
                    oki_busy     <= 1'b1;
                end
            end else if (ch1_ready) begin
                ch1_req  <= 1'b0;
                oki_busy <= 1'b0;
                if (oki_req_addr == oki_rom_addr) begin
                    oki_rom_data <= oki_req_addr[0] ? ch1_dout[15:8] : ch1_dout[7:0];
                    oki_rom_ok   <= 1'b1;
                end
            end
        end
    end

endmodule
