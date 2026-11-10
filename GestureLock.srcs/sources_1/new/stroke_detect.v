// Stroke detector + stroke buffer. Same rules as segment_strokes.py / the live logger:
//   start : distance from rest centre > START_R
//   end   : DWELL samples in a row with distance < END_R (hysteresis: END_R < START_R)
//   the DWELL resting samples at the end are dropped from the stroke
//   accept: length >= MIN_SAMPLES and farthest point >= MIN_EXTENT from rest
// Samples of the accepted stroke are in the buffer at addresses 0 .. stroke_len-1,
// each word = {x[9:0], y[9:0]}.
module stroke_detect #(
    parameter CX          = 528,
    parameter CY          = 518,
    parameter START_R2    = 3600,     // 60^2
    parameter END_R2      = 1600,     // 40^2
    parameter DWELL       = 40,       // samples (400 ms at 100 Hz)
    parameter MIN_SAMPLES = 20,
    parameter MIN_EXTENT2 = 22500,    // 150^2
    parameter AW          = 10        // buffer holds 2^AW samples
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          sample_valid,   // pulse, one per joystick sample
    input  wire [9:0]    x,
    input  wire [9:0]    y,
    output reg           active,         // a stroke is in progress
    output reg           stroke_done,    // 1-clock pulse: accepted stroke is in the buffer
    output reg           stroke_reject,  // 1-clock pulse: stroke too short/small/long
    output reg  [AW:0]   stroke_len,     // valid when stroke_done
    input  wire [AW-1:0] rd_addr,
    output reg  [19:0]   rd_data         // {x,y}, valid one clock after rd_addr
);
    localparam MAXLEN = (1 << AW);

    // ---- 3-stage pipeline so the multipliers have plenty of time ----
    reg        v1, v2, v3;
    reg [9:0]  x1, y1, x2, y2, x3, y3;
    reg signed [11:0] dx, dy;
    reg [23:0] r2;
    always @(posedge clk) begin
        v1 <= sample_valid; v2 <= v1; v3 <= v2;
        if (sample_valid) begin x1 <= x; y1 <= y; end
        // stage 1 -> 2: offsets from the rest centre
        dx <= $signed({2'b00, x1}) - CX;
        dy <= $signed({2'b00, y1}) - CY;
        x2 <= x1; y2 <= y1;
        // stage 2 -> 3: squared distance
        r2 <= dx * dx + dy * dy;
        x3 <= x2; y3 <= y2;
    end

    // ---- buffer (inferred block RAM) ----
    reg [19:0]   mem [0:MAXLEN-1];
    reg          we;
    reg [AW-1:0] waddr;
    reg [19:0]   wdata;
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rd_data <= mem[rd_addr];
    end

    // ---- state machine, runs once per sample ----
    reg [AW:0]  cnt;          // samples stored so far in this stroke
    reg [15:0]  rest;         // consecutive resting samples
    reg [23:0]  maxr2;
    wire [AW+1:0] total     = cnt + 1;                 // samples so far incl. this one
    wire [AW+1:0] final_len = total - DWELL;           // drop the resting tail

    always @(posedge clk) begin
        we <= 1'b0; stroke_done <= 1'b0; stroke_reject <= 1'b0;
        if (rst) begin
            active <= 1'b0; cnt <= 0; rest <= 0; maxr2 <= 0; stroke_len <= 0;
        end else if (v3) begin
            if (!active) begin
                if (r2 > START_R2) begin
                    active <= 1'b1; cnt <= 1; rest <= 0; maxr2 <= r2;
                    we <= 1'b1; waddr <= 0; wdata <= {x3, y3};
                end
            end else begin
                if (cnt < MAXLEN) begin we <= 1'b1; waddr <= cnt[AW-1:0]; wdata <= {x3, y3}; end
                if (cnt != {(AW+1){1'b1}}) cnt <= cnt + 1;   // saturate on very long strokes
                if (r2 > maxr2) maxr2 <= r2;
                if (r2 < END_R2) begin
                    if (rest + 1 >= DWELL) begin                 // stroke ended
                        active <= 1'b0;
                        if (final_len <= MAXLEN && final_len >= MIN_SAMPLES && maxr2 >= MIN_EXTENT2) begin
                            stroke_len <= final_len[AW:0]; stroke_done <= 1'b1;
                        end else stroke_reject <= 1'b1;
                    end
                    rest <= rest + 1;
                end else rest <= 0;
            end
        end
    end
endmodule
