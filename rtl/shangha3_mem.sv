// GA9201 board ROM storage in SDRAM (Shanghai III, Hebereke no Popoon, Blocken)
//
// One layout for every game (smaller ROMs are padded with FF by the MRA):
// SDRAM (bytes):
//   000000-0FFFFF  68000 program, big-endian 16-bit words (1 MB)
//   100000-10FFFF  Z80 program (heberpop/blocken)
//   110000-48FFFF  blitter graphics, byte order as in the ROM files (3.5 MB)
//   490000-50FFFF  OKI M6295 samples (512 KB)
//
// ROM download (MRA, ioctl index 0) arrives as one byte stream:
//   000000-07FFFF  even program EPROM -> program high bytes
//   080000-0FFFFF  odd program EPROM  -> program low bytes
//   100000-50FFFF  as in SDRAM
// The two program EPROMs are interleaved here, with byte-masked SDRAM writes,
// so the MRA needs no <interleave> section.
//
// SDRAM channels (sdram.sv priority order: ch2, ch1, ch3, ch4):
//   ch2  68000 cache line fills (64-bit): program, and the graphics ROM the
//        heberpop/blocken CPU can read at 800000-B7FFFF
//   ch1  OKI sample bytes
//   ch3  download writes; after the download, Z80 cache line fills (64-bit)
//   ch4  blitter tile rows (64-bit)
//
// The 68000 reads through a 512-line x 4-word direct-mapped cache (32 KB),
// the Z80 through a 256-line x 8-byte one (2 KB), so sequential instruction
// fetches and loops don't wait on the SDRAM.

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

    // board: 68000 ROM reads, as an SDRAM word address (program 000000+,
    // graphics ROM 110000+, which comes back byte-swapped to big-endian)
    input  logic [22:1] prog_addr,
    input  logic        prog_cs,
    output logic [15:0] prog_data,
    output logic        prog_ok,

    // board: Z80 program (heberpop/blocken)
    input  logic [15:0] z80_addr,
    input  logic        z80_cs,
    output logic [7:0]  z80_data,
    output logic        z80_ok,

    // board: blitter graphics
    input  logic        gfx_req,
    input  logic [18:0] gfx_addr,
    output logic        gfx_ack,
    output logic [63:0] gfx_data,

    // board: OKI samples, after the board's bank logic (19-bit, 512 KB)
    input  logic [18:0] oki_rom_addr,
    output logic [7:0]  oki_rom_data,
    output logic        oki_rom_ok,

    // sdram.sv channels
    output logic [26:1] ch1_addr, output logic ch1_req, input logic [31:0] ch1_dout, input logic ch1_ready,
    output logic [26:1] ch2_addr, output logic ch2_req, input logic [63:0] ch2_dout, input logic ch2_ready,
    output logic [26:1] ch3_addr, output logic ch3_req, output logic [15:0] ch3_din,
    output logic [1:0]  ch3_be,   output logic ch3_rnw, input logic ch3_ready, input logic [63:0] ch3_dout,
    output logic [26:1] ch4_addr, output logic ch4_req, input logic [63:0] ch4_dout, input logic ch4_ready
);
    localparam logic [26:0] Z80_BASE = 27'h100000;
    localparam logic [26:0] GFX_BASE = 27'h110000;
    localparam logic [26:0] OKI_BASE = 27'h490000;
    localparam logic [26:0] DL_END   = 27'h510000;

    // ------------------------------------------------------------------
    // Download: one byte-masked SDRAM write per byte (ch3). After the
    // download, ch3 serves Z80 cache line fills (reads).
    // ------------------------------------------------------------------
    logic        dl_busy;
    logic [26:1] dl_addr;
    logic        z_busy;         // Z80 line fill in flight (cache below)
    logic [26:1] z_line_addr;

    always_ff @(posedge clk) begin
        if (reset && !ioctl_download) begin
            dl_busy    <= 1'b0;
            ioctl_wait <= 1'b0;
        end else if (!dl_busy) begin
            if (ioctl_download && ioctl_wr && ioctl_index == 16'd0 && ioctl_addr < DL_END) begin
                logic [26:0] a;
                a = ioctl_addr;
                if (a < 27'h080000) begin              // even EPROM: program high bytes
                    dl_addr  <= a[25:0];                    // word a, high byte
                    ch3_be   <= 2'b10;
                end else if (a < 27'h100000) begin     // odd EPROM: program low bytes
                    dl_addr  <= a[25:0] - 26'h080000;       // word a-0x80000, low byte
                    ch3_be   <= 2'b01;
                end else begin                         // Z80, graphics, samples: byte order kept
                    dl_addr  <= a[26:1];
                    ch3_be   <= a[0] ? 2'b10 : 2'b01;
                end
                ch3_din    <= {ioctl_dout, ioctl_dout};
                dl_busy    <= 1'b1;
                ioctl_wait <= 1'b1;
            end
        end else if (ch3_ready) begin
            dl_busy    <= 1'b0;
            ioctl_wait <= 1'b0;
        end
    end
    assign ch3_rnw  = !dl_busy;
    assign ch3_req  = dl_busy || z_busy;
    assign ch3_addr = dl_busy ? dl_addr : z_line_addr;

    // ------------------------------------------------------------------
    // 68000 ROM cache
    //   SDRAM word address w = prog_addr[22:1]; line = w[21:2]; index = line[8:0]
    //   tag = line[19:9]
    // ------------------------------------------------------------------
    logic [63:0] c_data [0:511];
    logic [11:0] c_tag  [0:511];         // {valid, tag[10:0]}
    logic [63:0] c_data_q;
    logic [11:0] c_tag_q;
    logic [22:1] addr_q;
    logic        cs_q;

    wire  [8:0]  idx     = prog_addr[11:3];
    wire  [8:0]  idx_q   = addr_q[11:3];
    wire  [10:0] tag_q   = addr_q[22:12];

    logic        inv_busy;
    logic [8:0]  inv_idx;
    logic        fill_busy;
    logic        fill_we, fill_we_d;   // tag read is stale for 2 clocks after a fill
    logic [63:0] fill_data;

    wire       tag_we    = fill_we || inv_busy;
    wire [8:0] tag_waddr = inv_busy ? inv_idx : idx_q;
    wire [11:0] tag_wdata = inv_busy ? 12'h000 : {1'b1, tag_q};

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

    // graphics ROM words are stored in file byte order: swap to big-endian
    wire        swap_q   = ({addr_q, 1'b0} >= 23'(GFX_BASE));
    wire [15:0] word_q   = c_data_q[{addr_q[2:1], 4'b0000} +: 16];
    assign prog_ok   = hit;
    assign prog_data = swap_q ? {word_q[7:0], word_q[15:8]} : word_q;
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
                ch2_addr  <= {4'b0, addr_q[22:3], 2'b00};          // line start (word address)
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
    // Z80 program cache (heberpop/blocken): 256 lines x 8 bytes, direct mapped
    //   index = z80_addr[10:3], tag = z80_addr[15:11]
    // Filled through ch3 once the download is over. z80_ok is high only while
    // z80_data belongs to the current z80_addr.
    // ------------------------------------------------------------------
    logic [63:0] zc_data [0:255];
    logic [5:0]  zc_tag  [0:255];        // {valid, tag[4:0]}
    logic [63:0] zc_data_q;
    logic [5:0]  zc_tag_q;
    logic [15:0] zaddr_q;
    logic        zcs_q;
    logic        z_fill_we, z_fill_we_d;
    logic [63:0] z_fill_data;

    always_ff @(posedge clk) begin
        zc_data_q <= zc_data[z80_addr[10:3]];
        zc_tag_q  <= zc_tag[z80_addr[10:3]];
        zaddr_q   <= z80_addr;
        zcs_q     <= z80_cs;
        if (z_fill_we) zc_data[zaddr_q[10:3]] <= z_fill_data;
        if (z_fill_we || inv_busy)
            zc_tag[inv_busy ? inv_idx[7:0] : zaddr_q[10:3]] <= inv_busy ? 6'd0 : {1'b1, zaddr_q[15:11]};
    end

    wire z_hit = zcs_q && z80_cs && (zaddr_q == z80_addr) && !inv_busy && !z_fill_we && !z_fill_we_d &&
                 (zc_tag_q == {1'b1, zaddr_q[15:11]});
    assign z80_ok   = z_hit;
    assign z80_data = zc_data_q[{zaddr_q[2:0], 3'b000} +: 8];

    always_ff @(posedge clk) begin
        z_fill_we   <= 1'b0;
        z_fill_we_d <= z_fill_we;
        if (reset) begin
            z_busy <= 1'b0;
        end else if (!z_busy) begin
            if (!inv_busy && !dl_busy && !ioctl_download &&
                zcs_q && z80_cs && zaddr_q == z80_addr && !z_fill_we && !z_fill_we_d &&
                zc_tag_q != {1'b1, zaddr_q[15:11]}) begin
                z_line_addr <= 26'((Z80_BASE + {11'b0, zaddr_q[15:3], 3'b000}) >> 1);
                z_busy      <= 1'b1;
            end
        end else if (ch3_ready) begin
            z_busy      <= 1'b0;
            z_fill_data <= ch3_dout;
            z_fill_we   <= 1'b1;
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
                ch4_addr <= 26'((GFX_BASE + {5'b0, gfx_addr, 3'b000}) >> 1);
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
    // OKI samples: one byte at a time; ok only while the address is unchanged.
    //
    // The phrase table (first 1 KB of the sample ROM) is also kept in block RAM,
    // filled during the download. jt6295 reads 6 table bytes after every "start"
    // command and drops the next command if that lookup is still running. The
    // game writes OKI commands 2 us apart, too fast for SDRAM-speed lookups,
    // so table reads must be as fast as a direct ROM. Sample data is read
    // within a ~750-clock window and stays in SDRAM. (Found by sim/oki_tb.cpp.)
    // ------------------------------------------------------------------
    // Two 1 KB copies: ROM 00000 and 40000 (heberpop's second bank keeps its
    // own phrase table there). The board's bank logic hands us a 19-bit ROM
    // address; table reads are those in the first 1 KB of either 256 KB half.
    // (Blocken's fixed area holds its table; a bank-2 read at 40000-403FF also
    // finds the right bytes in copy 1, since copy 1 is ROM 40000-403FF.)
    // One write port (copy select = address bit), so this maps to block RAM;
    // with two write statements Quartus built it from 16K registers.
    logic [7:0]  oki_tbl [0:2047];
    logic [7:0]  oki_tbl_q;
    wire         oki_tbl_w0 = ioctl_addr >= OKI_BASE            && ioctl_addr < OKI_BASE + 27'h400;
    wire         oki_tbl_w1 = ioctl_addr >= OKI_BASE + 27'h40000 && ioctl_addr < OKI_BASE + 27'h40400;
    always_ff @(posedge clk) begin
        if (ioctl_download && ioctl_wr && ioctl_index == 16'd0 && (oki_tbl_w0 || oki_tbl_w1))
            oki_tbl[{oki_tbl_w1, ioctl_addr[9:0]}] <= ioctl_dout;
        oki_tbl_q <= oki_tbl[{oki_rom_addr[18], oki_rom_addr[9:0]}];
    end
    logic        oki_busy;
    logic [18:0] oki_cur, oki_req_addr;
    wire         oki_in_tbl = (oki_cur[17:10] == 8'd0);
    logic [1:0]  oki_tbl_wait;
    always_ff @(posedge clk) begin
        if (reset) begin
            oki_busy     <= 1'b0;
            ch1_req      <= 1'b0;
            oki_rom_ok   <= 1'b0;
            oki_cur      <= '1;
            oki_tbl_wait <= '0;
        end else begin
            if (oki_rom_addr != oki_cur) begin
                oki_cur      <= oki_rom_addr;
                oki_rom_ok   <= 1'b0;
                oki_tbl_wait <= 2'd2;
            end else if (oki_in_tbl && !oki_rom_ok) begin
                // table: oki_tbl_q follows the address one clock later
                if (oki_tbl_wait != 2'd0) oki_tbl_wait <= oki_tbl_wait - 2'd1;
                else begin
                    oki_rom_data <= oki_tbl_q;
                    oki_rom_ok   <= 1'b1;
                end
            end
            if (!oki_busy) begin
                if (!oki_rom_ok && oki_rom_addr == oki_cur && !oki_in_tbl) begin
                    oki_req_addr <= oki_cur;
                    ch1_addr     <= 26'((OKI_BASE + {8'b0, oki_cur}) >> 1);
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
