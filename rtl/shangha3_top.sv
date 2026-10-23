// Shanghai III core: board + ROM storage in SDRAM.
// Used by the MiSTer wrapper (Shanghai3.sv) and by the end-to-end simulation.

module shangha3_top (
    input  logic        clk,            // 96 MHz
    input  logic        reset,          // from MiSTer (menu reset, buttons)
    input  logic        sdram_init,     // hold high until the PLL is locked
    input  logic        pause,          // freeze the game (e.g. while the OSD is open)
    input  logic [2:0]  snd_balance,    // OSD OKI vs YM2149 balance (0 = PCB)

    // ROM download from the MiSTer menu / MRA
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,
    output logic        ioctl_wait,

    // controls, active low as on the PCB
    input  logic [15:0] in_inputs,
    input  logic [6:0]  in_system,
    input  logic [7:0]  dsw1,
    input  logic [7:0]  dsw2,

    // video
    output logic        ce_pix,
    output logic        hsync, vsync, hblank, vblank, vblank_next,
    output logic [7:0]  red, green, blue,

    // DDR3 for the display frame buffer (MiSTer DDRAM port, Avalon-MM)
    input  logic        ddr_busy,
    output logic [7:0]  ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic [7:0]  ddr_be,
    output logic        ddr_we,

    // second DDR3 master: the framework's screen_rotate (HDMI rotation),
    // single-beat write pulses, shared through shangha3_ddr_arb
    input  logic        rot_we,
    input  logic [28:0] rot_addr,
    input  logic [63:0] rot_din,
    input  logic [7:0]  rot_be,

    // audio
    output logic signed [15:0] snd,

    // SDRAM pins
    output logic        SDRAM_CLK,
    output logic        SDRAM_CKE,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
`ifdef VERILATOR
    input  logic [15:0] SDRAM_DQ_IN,
    output logic [15:0] SDRAM_DQ_OUT,
    output logic        SDRAM_DQ_OE,
`else
    inout  wire  [15:0] SDRAM_DQ,
`endif
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nWE
);
    // ------------------------------------------------------------------
    // Resets: ROM storage is reset by downloads too (clears the CPU cache);
    // the board stays in reset until the cache is clear.
    // ------------------------------------------------------------------
    logic mem_reset, mem_ready, board_reset;
    always_ff @(posedge clk) begin
        mem_reset   <= reset || ioctl_download || sdram_init;
        board_reset <= reset || ioctl_download || sdram_init || !mem_ready;
    end

    // ------------------------------------------------------------------
    // DDR3: display frame buffer (board) + screen_rotate share one port
    // ------------------------------------------------------------------
    logic        v_busy, v_dout_ready, v_rd, v_we;
    logic [7:0]  v_burstcnt, v_be;
    logic [28:0] v_addr;
    logic [63:0] v_dout, v_din;

    shangha3_ddr_arb u_ddr_arb (
        .clk, .reset(sdram_init),
        .a_busy(v_busy), .a_burstcnt(v_burstcnt), .a_addr(v_addr), .a_dout(v_dout),
        .a_dout_ready(v_dout_ready), .a_rd(v_rd), .a_din(v_din), .a_be(v_be), .a_we(v_we),
        .b_we(rot_we), .b_addr(rot_addr), .b_din(rot_din), .b_be(rot_be),
        .ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready,
        .ddr_rd, .ddr_din, .ddr_be, .ddr_we
    );

    // ------------------------------------------------------------------
    // Board
    // ------------------------------------------------------------------
    logic [18:1] prog_addr;
    logic        prog_cs, prog_ok;
    logic [15:0] prog_data;
    logic        gfx_req, gfx_ack;
    logic [17:0] gfx_addr;
    logic [63:0] gfx_data;
    logic [17:0] oki_rom_addr;
    logic [7:0]  oki_rom_data;
    logic        oki_rom_ok;

    shangha3_board u_board (
        .clk, .reset(board_reset), .vid_reset(sdram_init), .pause, .snd_balance,
        .prog_addr, .prog_cs, .prog_data, .prog_ok,
        .in_inputs, .in_system, .dsw1, .dsw2,
        .ce_pix, .hsync, .vsync, .hblank, .vblank, .vblank_next, .red, .green, .blue,
        .gfx_req, .gfx_addr, .gfx_ack, .gfx_data,
        .ddr_busy(v_busy), .ddr_burstcnt(v_burstcnt), .ddr_addr(v_addr),
        .ddr_dout(v_dout), .ddr_dout_ready(v_dout_ready),
        .ddr_rd(v_rd), .ddr_din(v_din), .ddr_be(v_be), .ddr_we(v_we),
        .psg_snd(), .oki_snd(), .snd,
        .oki_rom_addr, .oki_rom_data, .oki_rom_ok,
        .dbg_blit_go(), .dbg_irq_ack(), .dbg_gfxlist(), .dbg_flip(), .dbg_coinctrl(),
        .dbg_oki_wr(), .dbg_oki_data(), .dbg_cpu_addr(), .dbg_cpu_cyc_start(),
        .dbg_cpu_rw(), .dbg_cpu_dout(), .dbg_cpu_din(), .dbg_cpu_dtack(),
        .dbg_blit_busy(), .dbg_ram_stall()
    );

    // ------------------------------------------------------------------
    // ROM storage
    // ------------------------------------------------------------------
    logic [26:1] ch1_addr, ch2_addr, ch3_addr, ch4_addr;
    logic        ch1_req, ch2_req, ch3_req, ch4_req;
    logic        ch1_ready, ch2_ready, ch3_ready, ch4_ready;
    logic [31:0] ch1_dout;
    logic [63:0] ch2_dout, ch3_dout, ch4_dout;
    logic [15:0] ch3_din;
    logic [1:0]  ch3_be;
    logic        ch3_rnw;

    shangha3_mem u_mem (
        .clk, .reset(mem_reset), .ready(mem_ready),
        .ioctl_download, .ioctl_index, .ioctl_wr, .ioctl_addr, .ioctl_dout, .ioctl_wait,
        .prog_addr, .prog_cs, .prog_data, .prog_ok,
        .gfx_req, .gfx_addr, .gfx_ack, .gfx_data,
        .oki_rom_addr, .oki_rom_data, .oki_rom_ok,
        .ch1_addr, .ch1_req, .ch1_dout, .ch1_ready,
        .ch2_addr, .ch2_req, .ch2_dout, .ch2_ready,
        .ch3_addr, .ch3_req, .ch3_din, .ch3_be, .ch3_rnw, .ch3_ready,
        .ch4_addr, .ch4_req, .ch4_dout, .ch4_ready
    );

    sdram u_sdram (
        .init      (sdram_init),
        .clk       (clk),
        .doRefresh (1'b0),
`ifdef VERILATOR
        .SDRAM_DQ_IN, .SDRAM_DQ_OUT, .SDRAM_DQ_OE,
`else
        .SDRAM_DQ,
`endif
        .SDRAM_A, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nWE,
        .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_CKE, .SDRAM_CLK,
        .ch1_addr, .ch1_dout, .ch1_req, .ch1_ready,
        .ch2_addr, .ch2_dout, .ch2_req, .ch2_ready,
        .ch3_addr, .ch3_dout, .ch3_din, .ch3_be, .ch3_req, .ch3_rnw, .ch3_ready,
        .ch4_addr, .ch4_dout, .ch4_req, .ch4_ready
    );

endmodule
