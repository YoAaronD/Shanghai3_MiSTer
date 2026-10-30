//============================================================================
//  Shanghai III (Sunsoft, 1993) for MiSTer
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  Based on the MiSTer Template (Sorgelig and contributors).
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

assign FB_FORCE_BLANK = 0;

// Orientation (HDMI only; the native 15 kHz output is never rotated), status[9:8]:
//   Horizontal    as the PCB
//   Vertical CW   HDMI scaler shows the picture turned 90 degrees clockwise
//   Vertical CCW  ... counter-clockwise
// for players with a vertical (TATE) monitor. Uses the framework's screen_rotate
// (framebuffer in DDR3 at 0x24000000), which shares the DDRAM port with the
// core's display buffer through rtl/shangha3_ddr_arb.sv. Needs MISTER_FB (qsf).
wire [1:0] orient     = status[9:8];
wire       direct_video;
wire       no_rotate  = direct_video | (orient == 2'd0) | (orient == 2'd3);
wire       rotate_ccw = (orient == 2'd2);
wire       video_rotated;
wire        rot_we;          // screen_rotate's DDR3 writes, to the arbiter in shangha3_top
wire [28:0] rot_addr;
wire [63:0] rot_din;
wire  [7:0] rot_be;

wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"SunsoftGA9201;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[9:8],Orientation,Horizontal,Vertical CW,Vertical CCW;",
	"O[12:10],OKI (drums/FX),PCB,OKI+,OKI++,OKI--,OKI-;",
	"P1,CRT Adjust;",
	"P1O[96],CRT Adjust,Off,On;",
	"H1P1O[116:112],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[104:101],CRT H-Position,0,+6,+12,+18,+24,+30,+36,+42,-48,-42,-36,-30,-24,-18,-12,-6;",
	"H1P1O[108:105],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	"O[6],Service Mode,Off,On;",
	"O[7],Pause when OSD is open,On,Off;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Button 1,Button 2,Button 3,Start,Coin,Service;",
	"jn,A,B,X,Start,Select,R;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [31:0] joy1, joy2;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.video_rotated(video_rotated),
	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, ~status[96], 1'b0}),   // H1: hide the CRT Adjust amounts while Off

	.joystick_0(joy1),
	.joystick_1(joy2),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;          // 96 MHz: 2 x the PCB's 48 MHz crystal
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1];

/////////////////////   DIP SWITCHES   ///////////////////////////
// The MRA sends the switch bytes on ioctl index 254: [0] = DSW1, [1] = DSW2

reg [7:0] sw[2];
initial begin
	sw[0] = 8'hFF;
	sw[1] = 8'hBF;
end
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[24:1]) sw[ioctl_addr[0]] <= ioctl_dout;

// Game select: the MRA sends one byte at ioctl index 1 (0 = Shanghai III,
// 1 = Hebereke no Popoon, 2 = Blocken). It arrives before the ROMs.
reg [1:0] game_id = 2'd0;
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index == 16'd1) && (ioctl_addr == 27'd0)) game_id <= ioctl_dout[1:0];

//////////////////////////   INPUTS   ////////////////////////////
// MiSTer joystick bits: 0 right, 1 left, 2 down, 3 up,
//                       4 button 1, 5 button 2, 6 start, 7 coin, 8 service
// PCB 200000 (active low): P1 bits 0-5 = right,left,down,up,b1,b2; P2 bits 8-13
// PCB 200002 (active low): 0 coin1, 1 coin2, 2 service, 3 start1, 4 start2, 5 test

wire [15:0] in_inputs = ~{1'b0, joy2[6:0], 1'b0, joy1[6:0]};   // bit 6/14: Button 3 (Blocken)
// SYSTEM (MAME shangha3): 0 coin1, 1 coin2, 2 service1 (service credit), 3 start1, 4 start2,
// 5 service-mode switch (OSD "Service Mode"). Joystick: 7 Start, 8 Coin, 9 Service.
wire  [6:0] in_system = ~{1'b0, status[6], joy2[7], joy1[7], joy1[9] | joy2[9], joy2[8], joy1[8]};

//////////////////////////   CORE   //////////////////////////////

wire        ce_pix, hs, vs, hbl, vbl, vbl_next;
wire  [7:0] r, g, b;
wire signed [15:0] snd;

assign DDRAM_CLK = clk_sys;           // DDR3 holds the display frame buffer (see rtl/shangha3_video.sv)

shangha3_top core
(
	.clk(clk_sys),
	.reset(reset),
	.sdram_init(~pll_locked),
	.pause(OSD_STATUS & ~status[7]),   // freeze the game while the menu is open (option, default On)
	.snd_balance(status[12:10]),       // OKI (drums/FX) balance, 0 = PCB
	.game_id(game_id),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.in_inputs(in_inputs),
	.in_system(in_system),
	.dsw1(sw[0]),
	.dsw2(sw[1]),

	.ce_pix(ce_pix),
	.hsync(hs),
	.vsync(vs),
	.hblank(hbl),
	.vblank(vbl),
	.vblank_next(vbl_next),
	.red(r),
	.green(g),
	.blue(b),

	.snd(snd),

	.ddr_busy(DDRAM_BUSY),
	.ddr_burstcnt(DDRAM_BURSTCNT),
	.ddr_addr(DDRAM_ADDR),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY),
	.ddr_rd(DDRAM_RD),
	.ddr_din(DDRAM_DIN),
	.ddr_be(DDRAM_BE),
	.ddr_we(DDRAM_WE),
	.rot_we(rot_we),
	.rot_addr(rot_addr),
	.rot_din(rot_din),
	.rot_be(rot_be),

	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE)
);

//////////////////////////   VIDEO   /////////////////////////////
// 384 x 224 visible, 8 MHz pixel clock, 512 x 262 total (59.64 Hz, as measured on the PCB)

// During a ROM download the board is held in reset, but the video timing
// keeps running (sync never stops, so CRTs stay locked) and the picture is
// black. The MiSTer menu draws its own "Loading / Sending ROM" progress box on
// top, so the core draws none (an earlier version did, and showed two bars).
wire [23:0] core_rgb = {r, g, b};

// CRT Adjust (analog CRT geometry: H-Size, H-Position, V-Shift). Off = exact bypass.
reg  vs_d = 1'b0;
always @(posedge clk_sys) vs_d <= vs;
wire frame_event = vs && !vs_d;            // once per frame, inside vertical blanking

wire        av_ce, av_hb, av_vb, av_hs, av_vs;
wire [23:0] av_rgb;
s3_crt_adjust #(.SYS_HZ(96_000_000), .PIX_DIV(12), .HTOTAL(512), .VTOTAL(262)) crt_adjust
(
	.clk_sys(clk_sys),
	.ce_pix(ce_pix),
	.frame_event(frame_event),
	.osd_on(status[96]),
	.osd_hsize(status[116:112]),
	.osd_hpos(status[104:101]),
	.osd_vshift(status[108:105]),
	.sd_off((status[5:3] == 3'd0) && !forced_scandoubler),
	.rgb_in(core_rgb),
	.hblank_in(hbl),
	.vblank_in(vbl),
	.hsync_in(hs),
	.vsync_in(vs),
	.vb_next_in(vbl_next),
	.ce_out(av_ce),
	.rgb_out(av_rgb),
	.hblank_out(av_hb),
	.vblank_out(av_vb),
	.hsync_out(av_hs),
	.vsync_out(av_vs),
	.active()
);

arcade_video #(.WIDTH(384), .DW(24)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(av_ce),

	.RGB_in(av_rgb),
	.HBlank(av_hb),
	.VBlank(av_vb),
	.HSync(av_hs),
	.VSync(av_vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),

	.rotate_ccw(rotate_ccw),
	.no_rotate(no_rotate),
	.flip(1'b0),
	.video_rotated(video_rotated),

	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),

	.DDRAM_CLK(),                       // DDRAM_CLK is clk_sys (assigned above); CLK_VIDEO is the same clock
	.DDRAM_BUSY(1'b0),                  // screen_rotate ignores it; the arbiter queues its writes
	.DDRAM_BURSTCNT(),
	.DDRAM_ADDR(rot_addr),
	.DDRAM_DIN(rot_din),
	.DDRAM_BE(rot_be),
	.DDRAM_WE(rot_we),
	.DDRAM_RD()
);

//////////////////////////   AUDIO   /////////////////////////////

assign AUDIO_L   = snd;
assign AUDIO_R   = snd;
assign AUDIO_S   = 1;      // signed samples
assign AUDIO_MIX = 0;

assign LED_USER  = ioctl_download;

endmodule
