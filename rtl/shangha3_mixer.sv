// Sound mixer: YM2149 (jt49, unipolar 10-bit) + OKI M6295 (jt6295, signed
// 14-bit) into one signed 16-bit output.
// Balance measured against Aaron's PCB recording (v0.1.6, see CHANGELOG):
// the OKI sits about 8-12 dB higher relative to the YM2149 than the
// first guess (oki*2 + ay*12), so the ratio is now 3x that (oki*8 + ay*16),
// which also brings the overall level up (it peaked around -13 dBFS).
// v0.1.7 (Aaron, by ear on his CRT setup): overall level -3 dB, balance kept:
// (oki*45 + ay*90) / 8 = oki*5.625 + ay*11.25.
// v0.1.8: OSD "OKI (drums/FX)" balance. The OKI plays the sound effects and the
// music's drums; the YM2149 plays melody and bass line. Each step moves the OKI
// 3 dB relative to the YM2149, split half up / half down, so the overall
// loudness stays about the same and nothing new clips:
//   sel  label  oki  ay   (sum / 16)   OKI vs YM2149
//   0    PCB     90  180              0 dB (measured against the PCB)
//   1    OKI+   107  151             +3 dB
//   2    OKI++  127  127             +6 dB
//   3    OKI--   64  255             -6 dB
//   4    OKI-    76  214             -3 dB
// (Index 0 must be PCB: the OSD's default is 0, so the list wraps ++ -> -- .)
// The YM2149 output is unipolar: a high-pass removes its DC offset. Its corner
// sets how much bass gets through: v0.1.5 233 Hz (thin), v0.1.6 15 Hz,
// v0.1.7 58 Hz ("a little less bass": the lowest notes, around 100 Hz, about -1.3 dB).
//   ay_dc += (x - ay_dc) / 4096 at 1.5 MHz  ->  fc = 1.5e6 / (2 pi 4096) = 58 Hz
module shangha3_mixer (
    input  logic              clk,
    input  logic              reset,
    input  logic              ce_psg,      // YM2149 clock enable (1.5 MHz)
    input  logic              mute,        // OSD pause
    input  logic [2:0]        balance,     // OSD: 0 PCB, 1 OKI+, 2 OKI++, 3 OKI--, 4 OKI-
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

    // Coefficients from the OSD (static), then multiply, add and saturate,
    // one register stage each: the 96 MHz clock has little slack, and a few
    // clocks of audio latency don't matter.
    logic [6:0] k_oki;
    logic [7:0] k_ay;
    always_ff @(posedge clk) begin
        case (balance)
            3'd1:    begin k_oki <= 7'd107; k_ay <= 8'd151; end
            3'd2:    begin k_oki <= 7'd127; k_ay <= 8'd127; end
            3'd3:    begin k_oki <= 7'd64;  k_ay <= 8'd255; end
            3'd4:    begin k_oki <= 7'd76;  k_ay <= 8'd214; end
            default: begin k_oki <= 7'd90;  k_ay <= 8'd180; end
        endcase
    end

    logic signed [21:0] oki_m, ay_m, sum;
    always_ff @(posedge clk) begin
        logic signed [21:0] mix;
        oki_m <= 22'(oki_snd) * $signed({1'b0, k_oki});
        ay_m  <= 22'(ay_ac)   * $signed({1'b0, k_ay});
        sum   <= oki_m + ay_m;
        mix    = sum >>> 4;
        if      (mute)              snd <= 16'sd0;          // silent while the OSD pause is on
        else if (mix >  22'sd32767) snd <= 16'sd32767;
        else if (mix < -22'sd32768) snd <= -16'sd32768;
        else                        snd <= 16'(mix);
    end
endmodule
