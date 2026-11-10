`timescale 1ns / 1ps

// gesture_lock_fsm.v: Evaluates sequence, holds shape bitmaps, and handles state timing
module gesture_lock_fsm #(
    parameter CLK_HZ = 100_000_000
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         cls_done,        // Pulse on gesture classification completion
    input  wire  [3:0]  class_idx,       // Gesture class index (0..6)
    input  wire  [255:0] img_in,          // 16x16 rasterized shape matrix
    output reg   [1:0]  display_mode,    // 0: 4 BOXES, 1: LOCKED, 2: UNLOCKED, 3: WRONG!
    output reg          filled0, filled1, filled2, filled3,
    output reg   [255:0] img0, img1, img2, img3,
    output reg   [3:0]  cls0, cls1, cls2, cls3,
    output reg          unlocked
);

    // Target Sequence: Circle (0) -> Left (3) -> Right (4) -> Vline (6)
    localparam G_CIRCLE = 4'd0;
    localparam G_LEFT   = 4'd3;
    localparam G_RIGHT  = 4'd4;
    localparam G_VLINE  = 4'd6;

    // FSM States
    localparam S_START_LOCKED = 2'd0;
    localparam S_INPUT_BOXES  = 2'd1;
    localparam S_UNLOCKED     = 2'd2;
    localparam S_WRONG        = 2'd3;

    reg [1:0]  state;
    reg [1:0]  filled_count;
    reg [31:0] timer;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_START_LOCKED;
            display_mode <= 2'd1; // LOCKED screen at boot
            filled_count <= 2'd0;
            filled0 <= 1'b0; filled1 <= 1'b0; filled2 <= 1'b0; filled3 <= 1'b0;
            img0 <= 256'd0; img1 <= 256'd0; img2 <= 256'd0; img3 <= 256'd0;
            cls0 <= 4'd0;   cls1 <= 4'd0;   cls2 <= 4'd0;   cls3 <= 4'd0;
            unlocked     <= 1'b0;
            timer        <= 0;
        end else begin
            case (state)
                // 1. Startup / Reset State: Show "LOCKED" banner for 1.0 second
                S_START_LOCKED: begin
                    display_mode <= 2'd1; // LOCKED banner
                    unlocked     <= 1'b0;
                    if (timer == CLK_HZ - 1) begin
                        timer        <= 0;
                        state        <= S_INPUT_BOXES;
                        display_mode <= 2'd0; // Transition to 4 empty boxes
                        filled_count <= 2'd0;
                        filled0 <= 1'b0; filled1 <= 1'b0; filled2 <= 1'b0; filled3 <= 1'b0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // 2. Main Input State: Render 4 boxes and fill them sequentially as shapes are drawn
                S_INPUT_BOXES: begin
                    display_mode <= 2'd0; // BOXES screen
                    unlocked     <= 1'b0;

                    if (cls_done) begin
                        case (filled_count)
                            2'd0: begin
                                filled0 <= 1'b1; img0 <= img_in; cls0 <= class_idx;
                                filled_count <= 2'd1;
                            end
                            2'd1: begin
                                filled1 <= 1'b1; img1 <= img_in; cls1 <= class_idx;
                                filled_count <= 2'd2;
                            end
                            2'd2: begin
                                filled2 <= 1'b1; img2 <= img_in; cls2 <= class_idx;
                                filled_count <= 2'd3;
                            end
                            2'd3: begin
                                filled3 <= 1'b1; img3 <= img_in; cls3 <= class_idx;
                                filled_count <= 2'd0;

                                // Evaluate full 4-gesture sequence
                                if (cls0 == G_CIRCLE && cls1 == G_LEFT && cls2 == G_RIGHT && class_idx == G_VLINE) begin
                                    state        <= S_UNLOCKED;
                                    display_mode <= 2'd2; // UNLOCKED banner
                                    unlocked     <= 1'b1;
                                end else begin
                                    state        <= S_WRONG;
                                    display_mode <= 2'd3; // WRONG! banner
                                    timer        <= 0;
                                    unlocked     <= 1'b0;
                                end
                            end
                        endcase
                    end
                end

                // 3. Unlocked State
                S_UNLOCKED: begin
                    display_mode <= 2'd2; // UNLOCKED banner
                    unlocked     <= 1'b1;

                    // Re-lock system if a circle gesture is drawn while unlocked
                    if (cls_done && class_idx == G_CIRCLE) begin
                        state <= S_START_LOCKED;
                        timer <= 0;
                    end
                end

                // 4. Wrong Sequence State: Hold "WRONG!" banner for 1.0 second
                S_WRONG: begin
                    display_mode <= 2'd3; // WRONG! banner
                    unlocked     <= 1'b0;

                    if (timer == CLK_HZ - 1) begin
                        timer <= 0;
                        state <= S_START_LOCKED; // Show LOCKED for 1s, then reset to 4 empty boxes
                    end else begin
                        timer <= timer + 1;
                    end
                end

                default: state <= S_START_LOCKED;
            endcase
        end
    end
endmodule