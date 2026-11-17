`timescale 1ns / 1ps

// confidence_gate.v: 5-stage pipelined fixed-point Softmax probability gate.
// Accepts a prediction only when:
//   1) Top-1 probability > MIN_TOP_PCT (default 60%)
//   2) (Top-1 probability - Top-2 probability) > MIN_DIFF_PCT (default 20%)
module confidence_gate #(
    parameter NUM_CLASSES  = 7,
    parameter SCORE_W      = 32,
    parameter MIN_TOP_PCT  = 60,   // Highest prediction must be > 60%
    parameter MIN_DIFF_PCT = 20,   // Highest must exceed 2nd-highest by > 20%
    parameter LOGIT_UNIT   = 24   // Raw logit delta corresponding to ln(2)
)(
    input  wire                           clk,
    input  wire                           rst,
    input  wire                           cls_done,
    input  wire [3:0]                     class_idx,
    input  wire [NUM_CLASSES*SCORE_W-1:0] scores_flat,
    output reg                            valid_cls_done,
    output reg  [3:0]                     valid_class_idx,
    output reg                            low_conf_reject
);
    localparam signed [SCORE_W-1:0] MIN_SIGNED = {1'b1, {(SCORE_W-1){1'b0}}};
    localparam [15:0] RECIP_SCALE = 16'd65536 / LOGIT_UNIT;

    // 16-entry LUT for 2^(-frac/16) scaled by 1024 (frac = 0..15)
    function [10:0] exp2_frac_lut;
        input [3:0] frac;
        begin
            case (frac)
                4'd0:  exp2_frac_lut = 11'd1024;
                4'd1:  exp2_frac_lut = 11'd981;
                4'd2:  exp2_frac_lut = 11'd939;
                4'd3:  exp2_frac_lut = 11'd899;
                4'd4:  exp2_frac_lut = 11'd861;
                4'd5:  exp2_frac_lut = 11'd825;
                4'd6:  exp2_frac_lut = 11'd790;
                4'd7:  exp2_frac_lut = 11'd756;
                4'd8:  exp2_frac_lut = 11'd724;
                4'd9:  exp2_frac_lut = 11'd693;
                4'd10: exp2_frac_lut = 11'd664;
                4'd11: exp2_frac_lut = 11'd636;
                4'd12: exp2_frac_lut = 11'd609;
                4'd13: exp2_frac_lut = 11'd583;
                4'd14: exp2_frac_lut = 11'd558;
                4'd15: exp2_frac_lut = 11'd535;
                default: exp2_frac_lut = 11'd1024;
            endcase
        end
    endfunction

    function signed [SCORE_W-1:0] smax2;
        input signed [SCORE_W-1:0] a, b;
        begin
            smax2 = (a >= b) ? a : b;
        end
    endfunction

    // Merge two {top1, top2} pairs of 11-bit unsigned weights in 2 comparisons
    function [21:0] top2_merge;
        input [21:0] pa, pb;
        reg [10:0] a1, a2, b1, b2, r1, r2;
        begin
            a1 = pa[21:11]; a2 = pa[10:0];
            b1 = pb[21:11]; b2 = pb[10:0];
            if (a1 >= b1) begin
                r1 = a1;
                r2 = (a2 >= b1) ? a2 : b1;
            end else begin
                r1 = b1;
                r2 = (b2 >= a1) ? b2 : a1;
            end
            top2_merge = {r1, r2};
        end
    endfunction

    // ------------------------------------------------------------------------
    // Stage 1A: First level of 32-bit max comparator tree (1 comparison deep)
    // ------------------------------------------------------------------------
    wire signed [SCORE_W-1:0] s_in [0:7];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_pad
            assign s_in[g] = (g < NUM_CLASSES) ? $signed(scores_flat[g*SCORE_W +: SCORE_W]) : MIN_SIGNED;
        end
    endgenerate

    wire signed [SCORE_W-1:0] m01_comb = smax2(s_in[0], s_in[1]);
    wire signed [SCORE_W-1:0] m23_comb = smax2(s_in[2], s_in[3]);
    wire signed [SCORE_W-1:0] m45_comb = smax2(s_in[4], s_in[5]);
    wire signed [SCORE_W-1:0] m67_comb = smax2(s_in[6], s_in[7]);

    reg                       st1a_valid;
    reg [3:0]                 st1a_cls;
    reg signed [SCORE_W-1:0]  st1a_m01, st1a_m23, st1a_m45, st1a_m67;
    reg signed [SCORE_W-1:0]  st1a_scores [0:NUM_CLASSES-1];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            st1a_valid <= 1'b0;
            st1a_cls   <= 4'd0;
            st1a_m01   <= MIN_SIGNED;
            st1a_m23   <= MIN_SIGNED;
            st1a_m45   <= MIN_SIGNED;
            st1a_m67   <= MIN_SIGNED;
            for (i = 0; i < NUM_CLASSES; i = i + 1)
                st1a_scores[i] <= MIN_SIGNED;
        end else begin
            st1a_valid <= cls_done;
            if (cls_done) begin
                st1a_cls <= class_idx;
                st1a_m01 <= m01_comb;
                st1a_m23 <= m23_comb;
                st1a_m45 <= m45_comb;
                st1a_m67 <= m67_comb;
                for (i = 0; i < NUM_CLASSES; i = i + 1)
                    st1a_scores[i] <= s_in[i];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Stage 1B: Remaining 2 levels of 32-bit max comparator tree
    // ------------------------------------------------------------------------
    wire signed [SCORE_W-1:0] m0123_comb     = smax2(st1a_m01, st1a_m23);
    wire signed [SCORE_W-1:0] m4567_comb     = smax2(st1a_m45, st1a_m67);
    wire signed [SCORE_W-1:0] max_logit_comb = smax2(m0123_comb, m4567_comb);

    reg                       st1b_valid;
    reg [3:0]                 st1b_cls;
    reg signed [SCORE_W-1:0]  st1b_max_logit;
    reg signed [SCORE_W-1:0]  st1b_scores [0:NUM_CLASSES-1];

    always @(posedge clk) begin
        if (rst) begin
            st1b_valid     <= 1'b0;
            st1b_cls       <= 4'd0;
            st1b_max_logit <= MIN_SIGNED;
            for (i = 0; i < NUM_CLASSES; i = i + 1)
                st1b_scores[i] <= MIN_SIGNED;
        end else begin
            st1b_valid <= st1a_valid;
            if (st1a_valid) begin
                st1b_cls       <= st1a_cls;
                st1b_max_logit <= max_logit_comb;
                for (i = 0; i < NUM_CLASSES; i = i + 1)
                    st1b_scores[i] <= st1a_scores[i];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Stage 2: Compute fixed-point Softmax weights w_i in [0..1024]
    // ------------------------------------------------------------------------
    reg signed [SCORE_W:0] diff;
    reg        [27:0]      scaled_prod;
    reg        [7:0]       x_q4;
    reg        [10:0]      w_comb [0:NUM_CLASSES-1];

    always @(*) begin
        for (i = 0; i < NUM_CLASSES; i = i + 1) begin
            diff = $signed({st1b_max_logit[SCORE_W-1], st1b_max_logit}) -
                   $signed({st1b_scores[i][SCORE_W-1], st1b_scores[i]});
            if (diff <= 0) begin
                w_comb[i] = 11'd1024;
            end else if (diff >= (11 * LOGIT_UNIT)) begin
                w_comb[i] = 11'd0;
            end else begin
                scaled_prod = diff[15:0] * RECIP_SCALE;
                x_q4        = scaled_prod[19:12];
                w_comb[i]   = exp2_frac_lut(x_q4[3:0]) >> x_q4[7:4];
            end
        end
    end

    reg        st2_valid;
    reg [3:0]  st2_cls;
    reg [10:0] st2_w [0:7];

    always @(posedge clk) begin
        if (rst) begin
            st2_valid <= 1'b0;
            st2_cls   <= 4'd0;
            for (i = 0; i < 8; i = i + 1)
                st2_w[i] <= 11'd0;
        end else begin
            st2_valid <= st1b_valid;
            if (st1b_valid) begin
                st2_cls <= st1b_cls;
                for (i = 0; i < 8; i = i + 1)
                    st2_w[i] <= (i < NUM_CLASSES) ? w_comb[i] : 11'd0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Stage 3: Balanced tree for w_sum, w_max1, w_max2, and w_diff
    // ------------------------------------------------------------------------
    wire [13:0] w_sum_comb = ({3'd0, st2_w[0]} + {3'd0, st2_w[1]}) +
                             ({3'd0, st2_w[2]} + {3'd0, st2_w[3]}) +
                             ({3'd0, st2_w[4]} + {3'd0, st2_w[5]}) +
                             ({3'd0, st2_w[6]} + {3'd0, st2_w[7]});

    wire [21:0] p01   = top2_merge({st2_w[0], 11'd0}, {st2_w[1], 11'd0});
    wire [21:0] p23   = top2_merge({st2_w[2], 11'd0}, {st2_w[3], 11'd0});
    wire [21:0] p45   = top2_merge({st2_w[4], 11'd0}, {st2_w[5], 11'd0});
    wire [21:0] p67   = top2_merge({st2_w[6], 11'd0}, {st2_w[7], 11'd0});
    wire [21:0] p0123 = top2_merge(p01, p23);
    wire [21:0] p4567 = top2_merge(p45, p67);
    wire [21:0] pall  = top2_merge(p0123, p4567);

    wire [10:0] w_max1_comb = pall[21:11];
    wire [10:0] w_max2_comb = pall[10:0];

    reg        st3_valid;
    reg [3:0]  st3_cls;
    reg [10:0] st3_w_max1;
    reg [10:0] st3_w_diff;
    reg [13:0] st3_w_sum;

    always @(posedge clk) begin
        if (rst) begin
            st3_valid  <= 1'b0;
            st3_cls    <= 4'd0;
            st3_w_max1 <= 11'd0;
            st3_w_diff <= 11'd0;
            st3_w_sum  <= 14'd0;
        end else begin
            st3_valid <= st2_valid;
            if (st2_valid) begin
                st3_cls    <= st2_cls;
                st3_w_max1 <= w_max1_comb;
                st3_w_diff <= w_max1_comb - w_max2_comb;
                st3_w_sum  <= w_sum_comb;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Stage 4: Percentage threshold check (DSP multiply + compare)
    // ------------------------------------------------------------------------
    wire [21:0] lhs_top  = 22'd100 * {11'd0, st3_w_max1};
    wire [21:0] rhs_top  = MIN_TOP_PCT * {8'd0, st3_w_sum};
    wire [21:0] lhs_diff = 22'd100 * {11'd0, st3_w_diff};
    wire [21:0] rhs_diff = MIN_DIFF_PCT * {8'd0, st3_w_sum};

    always @(posedge clk) begin
        valid_cls_done  <= 1'b0;
        low_conf_reject <= 1'b0;
        if (rst) begin
            valid_class_idx <= 4'd0;
        end else if (st3_valid) begin
            if ((lhs_top > rhs_top) && (lhs_diff > rhs_diff)) begin
                valid_cls_done  <= 1'b1;
                valid_class_idx <= st3_cls;
            end else begin
                low_conf_reject <= 1'b1;
            end
        end
    end
endmodule