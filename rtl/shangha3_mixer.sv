// Sound mixer: YM2149 (jt49, unipolar 10-bit) + OKI M6295 (jt6295, signed
// 14-bit) into one signed 16-bit output.
// Balance measured against Aaron's PCB recording (v0.1.6, see CHANGELOG):
// the OKI sits about 8-12 dB higher relative to the YM2149 than the
// first guess (oki*2 + ay*12), so the ratio is now 3x that (oki*8 + ay*16),
// which also brings the overall level up (it peaked around -13 dBFS).
// The YM2149 output is unipolar: a high-pass removes its DC offset, with a
// ~15 Hz corner like an output coupling capacitor (was ~233 Hz, which
// thinned the bass notes).
//   ay_dc += (x - ay_dc) / 16384 at 1.5 MHz  ->  fc = 1.5e6 / (2 pi 16384) = 14.6 Hz
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
        else if (ce_psg) ay_dc <= ay_dc + ((($signed({1'b0, psg_snd}) <<< 16) - ay_dc) >>> 14);
        ay_ac <= $signed({1'b0, psg_snd}) - 11'(ay_dc >>> 16);
    end

    always_ff @(posedge clk) begin
        logic signed [18:0] mix;
        mix = 19'(oki_snd) * 19'sd8 + 19'(ay_ac) * 19'sd16;
        if      (mute)              snd <= 16'sd0;          // silent while the OSD pause is on
        else if (mix >  19'sd32767) snd <= 16'sd32767;
        else if (mix < -19'sd32768) snd <= -16'sd32768;
        else                        snd <= 16'(mix);
    end
endmodule
