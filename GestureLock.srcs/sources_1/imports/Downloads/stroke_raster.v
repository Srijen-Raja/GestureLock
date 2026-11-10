// Draws a stored stroke into a 16x16 binary image.
// Reads the stroke buffer of stroke_detect (address -> {x[9:0], y[9:0]}), converts every point to
// pixel coordinates in a fixed frame (rest centre = middle of the image, SCALE counts = edge of the gate)
// and draws straight lines between consecutive points, 16 sub-steps per segment, all in fixed point.
//   pixel_q8 = 1920 + (u * K >> 12)   (u = clamp(x - CX, +-375), K = 18175, 1920 = 7.5 pixels in Q8)
//   rows are flipped so that pushing the stick up draws toward the top of the image.
// Image bit index = row*16 + column. Bit-exact with raster_hw() in hw_model_linear.py.
module stroke_raster #(
    parameter CX = 528,
    parameter CY = 518,
    parameter AW = 10
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          start,        // pulse: a stroke is ready in the buffer (stroke_done)
    input  wire [AW:0]   len,          // number of samples in the stroke
    output reg  [AW-1:0] rd_addr,
    input  wire [19:0]   rd_data,      // {x, y}, valid two clocks after rd_addr
    output reg           busy,
    output reg           img_valid,    // 1-clock pulse: img is complete
    output reg  [255:0]  img
);
    localparam signed [11:0] CXS = CX;
    localparam signed [11:0] CYS = CY;
    localparam signed [11:0] LIM = 12'sd375;
    localparam signed [15:0] KS  = 16'sd18175;

    localparam S_IDLE = 4'd0, S_ADDR = 4'd1, S_W1 = 4'd2, S_CAP = 4'd3, S_U = 4'd4, S_P = 4'd5,
               S_Q = 4'd6, S_FIRST = 4'd7, S_DELTA = 4'd8, S_SEG = 4'd9, S_NEXT = 4'd10;
    reg [3:0]  state;
    reg [AW:0] idx, n;
    reg [9:0]  x_r, y_r;
    reg signed [11:0] ux, uy;
    reg signed [27:0] prx, pry;
    reg signed [14:0] pxq, pyq, pax, pay, dx, dy;
    reg signed [18:0] accx, accy;
    reg [4:0]  k;

    // offsets from the rest centre, clamped to +-375
    wire signed [11:0] dxs = $signed({2'b00, x_r}) - CXS;
    wire signed [11:0] dys = $signed({2'b00, y_r}) - CYS;
    wire signed [11:0] uxc = (dxs > LIM) ? LIM : (dxs < -LIM) ? -LIM : dxs;
    wire signed [11:0] uyc = (dys > LIM) ? LIM : (dys < -LIM) ? -LIM : dys;

    // pixel of the first point
    wire signed [14:0] fx = (pxq + 15'sd128) >>> 8;
    wire signed [14:0] fy = (pyq + 15'sd128) >>> 8;
    // pixel of the current sub-step
    wire signed [18:0] ax_n = accx + dx;
    wire signed [18:0] ay_n = accy + dy;
    wire signed [14:0] sx = ax_n >>> 4;
    wire signed [14:0] sy = ay_n >>> 4;
    wire signed [14:0] cx_s = (sx + 15'sd128) >>> 8;
    wire signed [14:0] cy_s = (sy + 15'sd128) >>> 8;

    always @(posedge clk) begin
        img_valid <= 1'b0;
        if (rst) begin
            state <= S_IDLE; busy <= 1'b0; img <= 256'd0; rd_addr <= 0; idx <= 0; n <= 0;
        end else begin
            case (state)
            S_IDLE: if (start) begin
                img <= 256'd0; n <= len; idx <= 0; busy <= 1'b1; state <= S_ADDR;
            end
            S_ADDR: begin rd_addr <= idx[AW-1:0]; state <= S_W1; end
            S_W1:   state <= S_CAP;
            S_CAP:  begin x_r <= rd_data[19:10]; y_r <= rd_data[9:0]; state <= S_U; end
            S_U:    begin ux <= uxc; uy <= uyc; state <= S_P; end
            S_P:    begin prx <= ux * KS; pry <= uy * KS; state <= S_Q; end
            S_Q:    begin
                pxq <= 15'sd1920 + (prx >>> 12);
                pyq <= 15'sd1920 - (pry >>> 12);
                state <= (idx == 0) ? S_FIRST : S_DELTA;
            end
            S_FIRST: begin                                   // very first point of the stroke
                img[{fy[3:0], fx[3:0]}] <= 1'b1;
                pax <= pxq; pay <= pyq; state <= S_NEXT;
            end
            S_DELTA: begin                                   // set up the line from the previous point
                dx <= pxq - pax; dy <= pyq - pay;
                accx <= $signed({pax, 4'b0000}); accy <= $signed({pay, 4'b0000});
                k <= 5'd1; state <= S_SEG;
            end
            S_SEG: begin                                     // 16 sub-steps along the segment
                img[{cy_s[3:0], cx_s[3:0]}] <= 1'b1;
                accx <= ax_n; accy <= ay_n;
                if (k == 5'd16) begin pax <= pxq; pay <= pyq; state <= S_NEXT; end
                else k <= k + 1'b1;
            end
            S_NEXT: begin
                if (idx + 1 >= n) begin img_valid <= 1'b1; busy <= 1'b0; state <= S_IDLE; end
                else begin idx <= idx + 1'b1; state <= S_ADDR; end
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
