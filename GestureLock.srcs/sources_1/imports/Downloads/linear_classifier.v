// Single-layer classifier on the 16x16 stroke image.
//   score[c] = bias[c] + sum over lit pixels p of weight[c][p]      class = argmax (first one on a tie)
// Weights: linear_w.mem (int8, line = class*256 + pixel, pixel = row*16 + column), linear_b.mem (int32).
// Takes about 2 clocks per pixel and class (3.6k clocks for 7 classes). No multipliers.
module linear_classifier #(
    parameter NUM_CLASSES = 7,                    // must match the number of lines in linear_b.mem
    parameter W_FILE = "linear_w.mem",
    parameter B_FILE = "linear_b.mem"
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,                    // pulse (img_valid from stroke_raster)
    input  wire [255:0] img,
    output reg          busy,
    output reg          done,                     // 1-clock pulse, class_idx is valid and stays until the next result
    output reg  [3:0]   class_idx,
    output wire [32*NUM_CLASSES-1:0] scores_flat  // all scores, for debugging
);
    reg signed [7:0]  wrom [0:NUM_CLASSES*256-1];
    reg signed [31:0] brom [0:NUM_CLASSES-1];
    initial begin
        $readmemh(W_FILE, wrom);
        $readmemh(B_FILE, brom);
    end

    reg signed [31:0] score [0:NUM_CLASSES-1];
    genvar g;
    generate for (g = 0; g < NUM_CLASSES; g = g + 1) begin : flat
        assign scores_flat[32*g +: 32] = score[g];
    end endgenerate

    localparam S_IDLE = 3'd0, S_LOAD = 3'd1, S_RD = 3'd2, S_ADD = 3'd3, S_END = 3'd4;
    reg [2:0]  state;
    reg [255:0] img_r;
    reg [3:0]  c;
    reg [7:0]  p;
    reg signed [31:0] acc, best;
    reg [3:0]  besti;
    reg signed [7:0] w_val;
    reg        lit;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            state <= S_IDLE; busy <= 1'b0; class_idx <= 4'd0;
        end else begin
            case (state)
            S_IDLE: if (start) begin
                img_r <= img; c <= 0; busy <= 1'b1; state <= S_LOAD;
            end
            S_LOAD: begin acc <= brom[c]; p <= 8'd0; state <= S_RD; end
            S_RD: begin                                      // registered read of the weight and the pixel
                w_val <= wrom[{c[3:0], p}];
                lit   <= img_r[p];
                state <= S_ADD;
            end
            S_ADD: begin
                if (lit) acc <= acc + w_val;
                if (p == 8'd255) state <= S_END;
                else begin p <= p + 1'b1; state <= S_RD; end
            end
            S_END: begin                                     // acc now holds the final score of class c
                score[c] <= acc;
                if (c == 0 || acc > best) begin best <= acc; besti <= c; end
                if (c == NUM_CLASSES - 1) begin
                    class_idx <= (c == 0 || acc > best) ? c : besti;
                    done <= 1'b1; busy <= 1'b0; state <= S_IDLE;
                end else begin c <= c + 1'b1; state <= S_LOAD; end
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
