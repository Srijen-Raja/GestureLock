`timescale 1ns / 1ps

// confidence_gate.v: Rejects classifications where (top1_score - top2_score) < MIN_MARGIN
module confidence_gate #(
    parameter NUM_CLASSES = 7,
    parameter SCORE_W     = 32,          // Set to 16 if linear_classifier uses 16-bit scores
    parameter signed [SCORE_W-1:0] MIN_MARGIN = 32'sd50
)(
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             cls_done,
    input  wire [3:0]                       class_idx,
    input  wire [NUM_CLASSES*SCORE_W-1:0]   scores_flat,
    output reg                              valid_cls_done,
    output reg  [3:0]                       valid_class_idx,
    output reg                              low_conf_reject
);
    integer i;
    reg signed [SCORE_W-1:0] cur_s;
    reg signed [SCORE_W-1:0] max1, max2;
    reg signed [SCORE_W:0]   margin;

    always @(*) begin
        max1 = {1'b1, {(SCORE_W-1){1'b0}}}; // Minimum signed integer
        max2 = {1'b1, {(SCORE_W-1){1'b0}}};
        for (i = 0; i < NUM_CLASSES; i = i + 1) begin
            cur_s = scores_flat[i*SCORE_W +: SCORE_W];
            if (cur_s >= max1) begin
                max2 = max1;
                max1 = cur_s;
            end else if (cur_s > max2) begin
                max2 = cur_s;
            end
        end
        margin = $signed({max1[SCORE_W-1], max1}) - $signed({max2[SCORE_W-1], max2});
    end

    always @(posedge clk) begin
        valid_cls_done  <= 1'b0;
        low_conf_reject <= 1'b0;
        if (rst) begin
            valid_class_idx <= 4'd0;
        end else if (cls_done) begin
            if (margin >= $signed({MIN_MARGIN[SCORE_W-1], MIN_MARGIN})) begin
                valid_cls_done  <= 1'b1;
                valid_class_idx <= class_idx;
            end else begin
                low_conf_reject <= 1'b1;
            end
        end
    end
endmodule