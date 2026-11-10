`timescale 1ns / 1ps

// rasterizer.v: Reads BRAM stroke buffer -> normalizes to 16x16 grid -> outputs 256-bit image
module rasterizer #(
    parameter CX = 528,
    parameter CY = 518,
    parameter AW = 10
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          stroke_done,    // pulse from stroke_detect
    input  wire [AW:0]   stroke_len,     // number of samples in buffer
    output reg  [AW-1:0] rd_addr,
    input  wire [19:0]   rd_data,        // {x[9:0], y[9:0]}
    output reg  [255:0]  image_matrix,   // 16x16 flattened binary image (row 0..15, col 0..15)
    output reg          image_valid     // 1-clock pulse when image generation completes
);
    // Grid scaling constants:
    // col = clamp((x - CX + 375) / 50, 0, 15)
    // row = clamp((CY + 375 - y) / 50, 0, 15)
    
    localparam S_IDLE    = 3'd0;
    localparam S_READ_P0 = 3'd1;
    localparam S_READ_P1 = 3'd2;
    localparam S_PLOT    = 3'd3;
    localparam S_DONE    = 3'd4;

    reg [2:0]  state;
    reg [AW:0] sample_idx;
    
    // Normalized coordinates
    reg [9:0] x_curr, y_curr, x_prev, y_prev;
    reg [3:0] col0, row0, col1, row1;
    
    // Simple coordinate-to-grid function
    function [3:0] calc_col(input [9:0] raw_x);
        integer signed val;
        begin
            val = ($signed({2'b00, raw_x}) - CX + 375) / 50;
            if (val < 0) calc_col = 4'd0;
            else if (val > 15) calc_col = 4'd15;
            else calc_col = val[3:0];
        end
    endfunction

    function [3:0] calc_row(input [9:0] raw_y);
        integer signed val;
        begin
            val = (CY + 375 - $signed({2'b00, raw_y})) / 50;
            if (val < 0) calc_row = 4'd0;
            else if (val > 15) calc_row = 4'd15;
            else calc_row = val[3:0];
        end
    endfunction

    // Pixel plotting helper: set pixel at (row, col)
    integer r, c;
    always @(posedge clk) begin
        image_valid <= 1'b0;
        
        if (rst) begin
            state <= S_IDLE;
            image_matrix <= 256'd0;
            rd_addr <= 0;
            sample_idx <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (stroke_done && stroke_len > 1) begin
                        image_matrix <= 256'd0;
                        rd_addr <= 0;
                        sample_idx <= 0;
                        state <= S_READ_P0;
                    end
                end

                S_READ_P0: begin
                    // Wait for BRAM read latency for point 0
                    rd_addr <= 10'd1;
                    sample_idx <= 10'd1;
                    state <= S_READ_P1;
                end

                S_READ_P1: begin
                    // Store point 0 grid
                    col0 <= calc_col(rd_data[19:10]);
                    row0 <= calc_row(rd_data[9:0]);
                    
                    if (sample_idx < stroke_len) begin
                        rd_addr <= sample_idx + 1'b1;
                        state <= S_PLOT;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_PLOT: begin
                    col1 <= calc_col(rd_data[19:10]);
                    row1 <= calc_row(rd_data[9:0]);
                    
                    // Mark current point and midpoint between consecutive points
                    image_matrix[{row0, col0}] <= 1'b1;
                    image_matrix[{row1, col1}] <= 1'b1;
                    image_matrix[{((row0 + row1) >> 1), ((col0 + col1) >> 1)}] <= 1'b1;
                    
                    // Advance pipeline
                    row0 <= row1;
                    col0 <= col1;
                    
                    sample_idx <= sample_idx + 1'b1;
                    if (sample_idx + 1'b1 < stroke_len) begin
                        rd_addr <= sample_idx + 2'd2;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    image_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule