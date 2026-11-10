`timescale 1ns / 1ps
`include "quant_params.vh"

module cnn_engine #(
    parameter C = NUM_CLASSES
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         image_valid,      // Pulse from rasterizer
    input  wire [255:0] image_in,         // 16x16 binary image
    output reg  [2:0]   predicted_class,  // 0..C-1
    output reg          class_valid       // 1-clock pulse on completion
);
    // Weight & bias arrays
    reg signed [7:0]  conv1_w [0:71];     // 8 x 1 x 3 x 3
    reg signed [31:0] conv1_b [0:7];
    reg signed [7:0]  conv2_w [0:1151];   // 16 x 8 x 3 x 3
    reg signed [31:0] conv2_b [0:15];
    reg signed [7:0]  fc_w    [0:1791];   // C x 256
    reg signed [31:0] fc_b    [0:6];

    initial begin
        $readmemh("conv1_w.mem", conv1_w);
        $readmemh("conv1_b.mem", conv1_b);
        $readmemh("conv2_w.mem", conv2_w);
        $readmemh("conv2_b.mem", conv2_b);
        $readmemh("fc_w.mem",    fc_w);
        $readmemh("fc_b.mem",    fc_b);
    end

    // Intermediate feature buffers
    reg [7:0] conv1_out [0:7][0:15][0:15];
    reg [7:0] pool1_out [0:7][0:7][0:7];
    reg [7:0] conv2_out [0:15][0:7][0:7];
    reg [7:0] pool2_out [0:255];
    reg signed [31:0] logits [0:C-1];

    // State definitions
    localparam S_IDLE   = 3'd0;
    localparam S_CONV1  = 3'd1;
    localparam S_POOL1  = 3'd2;
    localparam S_CONV2  = 3'd3;
    localparam S_POOL2  = 3'd4;
    localparam S_FC     = 3'd5;
    localparam S_ARGMAX = 3'd6;

    reg [2:0] state;
    reg [4:0] ch_cnt, r_cnt, c_cnt;
    reg [3:0] in_ch_cnt;
    reg [8:0] k_cnt;
    
    integer kr, kc;
    reg signed [31:0] accum;
    reg signed [31:0] sum_3x3, prod, accum_val, req_val;
    reg signed [31:0] max_score;
    reg [7:0] max_val;

    always @(posedge clk) begin
        class_valid <= 1'b0;

        if (rst) begin
            state <= S_IDLE;
            predicted_class <= 3'd0;
            ch_cnt <= 0; r_cnt <= 0; c_cnt <= 0;
            in_ch_cnt <= 0; k_cnt <= 0; accum <= 0;
            max_score <= 32'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (image_valid) begin
                        ch_cnt <= 0; r_cnt <= 0; c_cnt <= 0;
                        in_ch_cnt <= 0; k_cnt <= 0;
                        state <= S_CONV1;
                    end
                end

                // CONV1: 1 pixel calculated per clock cycle
                S_CONV1: begin
                    accum_val = conv1_b[ch_cnt];
                    for (kr = -1; kr <= 1; kr = kr + 1) begin
                        for (kc = -1; kc <= 1; kc = kc + 1) begin
                            if (($signed({1'b0, r_cnt}) + kr >= 0) && ($signed({1'b0, r_cnt}) + kr < 16) &&
                                ($signed({1'b0, c_cnt}) + kc >= 0) && ($signed({1'b0, c_cnt}) + kc < 16)) begin
                                if (image_in[(r_cnt + kr)*16 + (c_cnt + kc)]) begin
                                    accum_val = accum_val + conv1_w[ch_cnt*9 + (kr+1)*3 + (kc+1)];
                                end
                            end
                        end
                    end
                    conv1_out[ch_cnt][r_cnt][c_cnt] <= (accum_val < 0) ? 8'd0 : ((accum_val > 255) ? 8'd255 : accum_val[7:0]);

                    if (c_cnt == 15) begin
                        c_cnt <= 0;
                        if (r_cnt == 15) begin
                            r_cnt <= 0;
                            if (ch_cnt == 7) begin
                                ch_cnt <= 0;
                                state <= S_POOL1;
                            end else ch_cnt <= ch_cnt + 1;
                        end else r_cnt <= r_cnt + 1;
                    end else c_cnt <= c_cnt + 1;
                end

                // POOL1: 1 pooled pixel per clock cycle
                S_POOL1: begin
                    max_val = conv1_out[ch_cnt][2*r_cnt][2*c_cnt];
                    if (conv1_out[ch_cnt][2*r_cnt+1][2*c_cnt] > max_val)   max_val = conv1_out[ch_cnt][2*r_cnt+1][2*c_cnt];
                    if (conv1_out[ch_cnt][2*r_cnt][2*c_cnt+1] > max_val)   max_val = conv1_out[ch_cnt][2*r_cnt][2*c_cnt+1];
                    if (conv1_out[ch_cnt][2*r_cnt+1][2*c_cnt+1] > max_val) max_val = conv1_out[ch_cnt][2*r_cnt+1][2*c_cnt+1];
                    pool1_out[ch_cnt][r_cnt][c_cnt] <= max_val;

                    if (c_cnt == 7) begin
                        c_cnt <= 0;
                        if (r_cnt == 7) begin
                            r_cnt <= 0;
                            if (ch_cnt == 7) begin
                                ch_cnt <= 0;
                                in_ch_cnt <= 0;
                                state <= S_CONV2;
                            end else ch_cnt <= ch_cnt + 1;
                        end else r_cnt <= r_cnt + 1;
                    end else c_cnt <= c_cnt + 1;
                end

                // CONV2: 1 input channel per clock cycle (8 cycles per pixel)
                S_CONV2: begin
                    sum_3x3 = 0;
                    for (kr = -1; kr <= 1; kr = kr + 1) begin
                        for (kc = -1; kc <= 1; kc = kc + 1) begin
                            if (($signed({1'b0, r_cnt}) + kr >= 0) && ($signed({1'b0, r_cnt}) + kr < 8) &&
                                ($signed({1'b0, c_cnt}) + kc >= 0) && ($signed({1'b0, c_cnt}) + kc < 8)) begin
                                sum_3x3 = sum_3x3 + $signed({1'b0, pool1_out[in_ch_cnt][r_cnt+kr][c_cnt+kc]}) *
                                          conv2_w[ch_cnt*72 + in_ch_cnt*9 + (kr+1)*3 + (kc+1)];
                            end
                        end
                    end

                    accum_val = (in_ch_cnt == 0) ? (conv2_b[ch_cnt] + sum_3x3) : (accum + sum_3x3);
                    accum <= accum_val;

                    if (in_ch_cnt == 7) begin
                        in_ch_cnt <= 0;
                        req_val = (accum_val * REQ_MULT1) >>> REQ_SHIFT1;
                        conv2_out[ch_cnt][r_cnt][c_cnt] <= (req_val < 0) ? 8'd0 : ((req_val > 255) ? 8'd255 : req_val[7:0]);

                        if (c_cnt == 7) begin
                            c_cnt <= 0;
                            if (r_cnt == 7) begin
                                r_cnt <= 0;
                                if (ch_cnt == 15) begin
                                    ch_cnt <= 0;
                                    state <= S_POOL2;
                                end else ch_cnt <= ch_cnt + 1;
                            end else r_cnt <= r_cnt + 1;
                        end else c_cnt <= c_cnt + 1;
                    end else begin
                        in_ch_cnt <= in_ch_cnt + 1;
                    end
                end

                // POOL2: Flattening and Pooling
                S_POOL2: begin
                    max_val = conv2_out[ch_cnt][2*r_cnt][2*c_cnt];
                    if (conv2_out[ch_cnt][2*r_cnt+1][2*c_cnt] > max_val)   max_val = conv2_out[ch_cnt][2*r_cnt+1][2*c_cnt];
                    if (conv2_out[ch_cnt][2*r_cnt][2*c_cnt+1] > max_val)   max_val = conv2_out[ch_cnt][2*r_cnt][2*c_cnt+1];
                    if (conv2_out[ch_cnt][2*r_cnt+1][2*c_cnt+1] > max_val) max_val = conv2_out[ch_cnt][2*r_cnt+1][2*c_cnt+1];
                    pool2_out[ch_cnt*16 + r_cnt*4 + c_cnt] <= max_val;

                    if (c_cnt == 3) begin
                        c_cnt <= 0;
                        if (r_cnt == 3) begin
                            r_cnt <= 0;
                            if (ch_cnt == 15) begin
                                ch_cnt <= 0;
                                k_cnt <= 0;
                                state <= S_FC;
                            end else ch_cnt <= ch_cnt + 1;
                        end else r_cnt <= r_cnt + 1;
                    end else c_cnt <= c_cnt + 1;
                end

                // FC: 1 feature multiply-accumulate per clock cycle (256 cycles per class)
                S_FC: begin
                    prod = $signed({1'b0, pool2_out[k_cnt]}) * fc_w[ch_cnt*256 + k_cnt];
                    accum_val = (k_cnt == 0) ? (fc_b[ch_cnt] + prod) : (accum + prod);
                    accum <= accum_val;

                    if (k_cnt == 255) begin
                        k_cnt <= 0;
                        logits[ch_cnt] <= accum_val;
                        if (ch_cnt == C - 1) begin
                            ch_cnt <= 0;
                            k_cnt <= 1;
                            max_score <= logits[0];
                            predicted_class <= 3'd0;
                            state <= S_ARGMAX;
                        end else begin
                            ch_cnt <= ch_cnt + 1;
                        end
                    end else begin
                        k_cnt <= k_cnt + 1;
                    end
                end

                // ARGMAX: Sequential single-cycle comparative search per class
                S_ARGMAX: begin
                    if (k_cnt < C) begin
                        if (logits[k_cnt] > max_score) begin
                            max_score <= logits[k_cnt];
                            predicted_class <= k_cnt[2:0];
                        end
                        k_cnt <= k_cnt + 1;
                    end else begin
                        class_valid <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule