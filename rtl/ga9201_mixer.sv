// Hebereke no Popoon / Blocken mixer: YM3438 (both outputs) + OKI M6295 to mono.
//
// Default = MAME's balance and level, measured: MAME's heberpop -wavwrite
// output fitted as a*(fm_left+fm_right) + b*oki, with the core's own jt12 and
// jt6295 replayed from MAME's register log (scripts/snd2_replay.sh,
// scripts/mix_fit.py) over 35 s of the attract mode: a = 0.292, b = 15.80
// (5.6 % residual; 3.6 % over the drum-heavy part). jt6295's output is the
// 12-bit ADPCM sum; MAME scales the OKI to 16 bits (x16). MAME's peak there is
// 31358 of 32767, so the level is kept as MAME's.
//   snd = 0.297 * (fm_left + fm_right) + 15.8 * oki
// (No PCB measurement yet for these games, unlike Shanghai III.)
// The OSD "OKI (drums/FX)" option moves the OKI in 3 dB steps against the FM,
// like the Shanghai III mixer (the FM moves the other way by half as much):
//   balance 0 MAME (shown as "PCB" in the OSD), 1 OKI+, 2 OKI++, 3 OKI--, 4 OKI-
// Coefficients are in 1/64.

module ga9201_mixer (
    input  logic               clk,
    input  logic               reset,
    input  logic               mute,
    input  logic [2:0]         balance,
    input  logic signed [15:0] fm_left,
    input  logic signed [15:0] fm_right,
    input  logic signed [13:0] oki_snd,
    output logic signed [15:0] snd
);
    logic [11:0] k_fm, k_oki;
    always_ff @(posedge clk) begin
        case (balance)
            3'd1:    begin k_fm <= 12'd16; k_oki <= 12'd1428; end   // OKI +3 dB, FM -1.5 dB
            3'd2:    begin k_fm <= 12'd13; k_oki <= 12'd2017; end   // OKI +6 dB, FM -3 dB
            3'd3:    begin k_fm <= 12'd27; k_oki <= 12'd506;  end   // OKI -6 dB, FM +3 dB
            3'd4:    begin k_fm <= 12'd23; k_oki <= 12'd715;  end   // OKI -3 dB, FM +1.5 dB
            default: begin k_fm <= 12'd19; k_oki <= 12'd1011; end   // MAME balance and level
        endcase
    end

    logic signed [16:0] fm_sum;
    logic signed [29:0] fm_m, oki_m;
    logic signed [30:0] sum;
    always_ff @(posedge clk) begin
        if (reset) begin
            fm_sum <= '0; fm_m <= '0; oki_m <= '0; sum <= '0; snd <= '0;
        end else begin
            fm_sum <= fm_left + fm_right;
            fm_m   <= fm_sum * $signed({1'b0, k_fm});
            oki_m  <= oki_snd * $signed({1'b0, k_oki});
            sum    <= fm_m + oki_m;
            if (mute)                         snd <= '0;
            else if ((sum >>> 6) >  31'sd32767)  snd <= 16'sd32767;
            else if ((sum >>> 6) < -31'sd32768)  snd <= -16'sd32768;
            else                              snd <= 16'(sum >>> 6);
        end
    end
endmodule
