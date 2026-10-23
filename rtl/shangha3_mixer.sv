// Sound mixer: YM2149 (jt49, unipolar 10-bit) + OKI M6295 (jt6295, signed
// 14-bit) into one signed 16-bit output.
// Balance measured against Aaron's PCB recording (v0.1.6, see CHANGELOG):
// the OKI sits about 8-12 dB higher relative to the YM2149 than the
// first guess (oki*2 + ay*12), so the ratio is now 3x that (oki*8 + ay*16),
// which also brings the overall level up (it peaked around -13 dBFS).
// v0.1.7 (Aaron, by ear on his CRT setup): overall level -3 dB, balance kept:
// (oki*45 + ay*90) / 8 = oki*5.625 + ay*11.25.
// The YM2149 output is unipolar: a high-pass removes its DC offset. Its corner
// sets how much bass gets through: v0.1.5 233 Hz (thin), v0.1.6 15 Hz,
// v0.1.7 58 Hz ("a little less bass": the lowest notes, around 100 Hz, about -1.3 dB).
//   ay_dc += (x - ay_dc) / 4096 at 1.5 MHz  ->  fc = 1.5e6 / (2 pi 4096) = 58 Hz
module shangha3_mixer (
    input  logic              clk,
    input  logic              reset,
    input  logic              ce_psg,      // YM2149 clock enable (1.5 MHz)
    input  logic              mute,        // OSD pause
    input  logic [9:0]        psg_snd,
    input  logic signed [13:0] oki_snd,
    output logic signed [15:0] snd
);
    logic signed [27:0] ay_dc;          // DC estimate, 10.16 fixed point (+ sign)
    logic signed [10:0] ay_ac;
    always_ff @(posedge clk) begin
        if (reset) ay_dc <= 28'sd512 <<< 16;
        else if (ce_psg) ay_dc <= ay_dc + ((($signed({1'b0, psg_snd}) <<< 16) - ay_dc) >>> 12);
        ay_ac <= $signed({1'b0, psg_snd}) - 11'(ay_dc >>> 16);
    end

    // Three register stages (constant multiplies, add, saturate): the 96 MHz
    // clock has little slack, and a few clocks of audio latency don't matter.
    logic signed [20:0] oki_m, ay_m, sum;
    always_ff @(posedge clk) begin
        logic signed [20:0] mix;
        oki_m <= 21'(oki_snd) * 21'sd45;
        ay_m  <= 21'(ay_ac) * 21'sd90;
        sum   <= oki_m + ay_m;
        mix    = sum >>> 3;
        if      (mute)              snd <= 16'sd0;          // silent while the OSD pause is on
        else if (mix >  21'sd32767) snd <= 16'sd32767;
        else if (mix < -21'sd32768) snd <= -16'sd32768;
        else                        snd <= 16'(mix);
    end
endmodule
