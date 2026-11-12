`timescale 1ns / 1ps

module gesture_lock_fsm #(
    parameter CLK_HZ = 100_000_000
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         cls_done,        // Confident classification pulse
    input  wire  [3:0]  class_idx,       // Detected class (0..6)
    input  wire  [255:0] img_in,          // 16x16 rasterized stroke bitmap
    input  wire         active,          // High while user is drawing a stroke
    input  wire         reject_pulse,    // Stroke rejected (size/length or low confidence)
    input  wire  [2:0]  btn,             // Pmod JSTK2 buttons
    input  wire         btn_set_pass,    // ZedBoard BTNU to enter password programming mode
    output reg   [2:0]  display_mode,    // 0: BOXES, 1: LOCKED, 2: UNLOCKED, 3: WRONG!, 4: SET PASS, 5: SET BOXES, 6: SAVED!
    output reg          filled0, filled1, filled2, filled3,
    output reg   [255:0] img0, img1, img2, img3,
    output wire  [1:0]  active_box,
    output wire         drawing_active,
    output wire         reject_flash,
    output reg          unlocked
);
    localparam ONE_SEC        = CLK_HZ;
    localparam HALF_SEC       = CLK_HZ / 2;
    localparam SET_BANNER_CLK = (CLK_HZ * 4) / 5;   // 800 ms
    localparam UNDO_MIN_CLK   = CLK_HZ / 200;       // 5 ms debounce
    localparam UNDO_MAX_CLK   = (CLK_HZ * 3) / 10;  // 300 ms max tap duration
    localparam REJECT_CLK     = (CLK_HZ * 3) / 10;  // 300 ms border flash

    // FSM States
    localparam S_START_LOCKED = 3'd0;
    localparam S_INPUT_BOXES  = 3'd1;
    localparam S_WAIT_EVAL    = 3'd2;
    localparam S_UNLOCKED     = 3'd3;
    localparam S_WRONG        = 3'd4;
    localparam S_SET_BANNER   = 3'd5;
    localparam S_SET_BOXES    = 3'd6;
    localparam S_SET_WAIT     = 3'd7;

    reg        in_saved_banner;
    reg [2:0]  state;
    reg [1:0]  filled_count;
    reg [31:0] timer;
    reg [31:0] reject_tmr;

    // Stored Password Registers (Default: Circle -> Left -> Right -> Vline)
    reg [3:0] pass0, pass1, pass2, pass3;
    reg [3:0] cls0, cls1, cls2, cls3;

    // Synchronize BTNU
    reg set_s1, set_s2, set_prev;
    wire set_rise = set_s2 && !set_prev;
    always @(posedge clk) begin
        set_s1   <= btn_set_pass;
        set_s2   <= set_s1;
        set_prev <= set_s2;
    end

    // Track Joystick Button Press / Tap-to-Undo / 1s Hold
    wire btn_pressed = |btn;
    reg  btn_prev;
    reg  [31:0] btn_hold_cnt;
    wire btn_released_tap = (!btn_pressed && btn_prev) &&
                            (btn_hold_cnt >= UNDO_MIN_CLK) &&
                            (btn_hold_cnt < UNDO_MAX_CLK) &&
                            !active;

    always @(posedge clk) begin
        if (rst) begin
            btn_prev     <= 1'b0;
            btn_hold_cnt <= 0;
        end else begin
            btn_prev <= btn_pressed;
            if (btn_pressed) begin
                if (btn_hold_cnt < ONE_SEC)
                    btn_hold_cnt <= btn_hold_cnt + 1;
            end else begin
                btn_hold_cnt <= 0;
            end
        end
    end

    // Rejection flash timer
    always @(posedge clk) begin
        if (rst) begin
            reject_tmr <= 0;
        end else begin
            if (reject_pulse && (state == S_INPUT_BOXES || state == S_SET_BOXES))
                reject_tmr <= REJECT_CLK;
            else if (reject_tmr > 0)
                reject_tmr <= reject_tmr - 1;
        end
    end

    assign active_box     = filled_count;
    assign drawing_active = active && (state == S_INPUT_BOXES || state == S_SET_BOXES);
    assign reject_flash   = (reject_tmr > 0) && (state == S_INPUT_BOXES || state == S_SET_BOXES);

    // Main Master FSM
    always @(posedge clk) begin
        if (rst) begin
            state           <= S_START_LOCKED;
            in_saved_banner <= 1'b0;
            display_mode    <= 3'd1; // LOCKED
            filled_count    <= 2'd0;
            filled0 <= 1'b0; filled1 <= 1'b0; filled2 <= 1'b0; filled3 <= 1'b0;
            img0 <= 256'd0; img1 <= 256'd0; img2 <= 256'd0; img3 <= 256'd0;
            cls0 <= 4'd0;   cls1 <= 4'd0;   cls2 <= 4'd0;   cls3 <= 4'd0;
            pass0 <= 4'd0;  pass1 <= 4'd3;  pass2 <= 4'd4;  pass3 <= 4'd6; // Circle, Left, Right, Vline
            unlocked        <= 1'b0;
            timer           <= 0;
        end else begin
            case (state)
                // 1. Show "LOCKED" banner for 1.0s
                S_START_LOCKED: begin
                    in_saved_banner <= 1'b0;
                    display_mode    <= 3'd1;
                    unlocked        <= 1'b0;
                    if (timer == ONE_SEC - 1) begin
                        timer        <= 0;
                        state        <= S_INPUT_BOXES;
                        display_mode <= 3'd0;
                        filled_count <= 2'd0;
                        filled0 <= 1'b0; filled1 <= 1'b0; filled2 <= 1'b0; filled3 <= 1'b0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // 2. Normal Unlock Entry (4 Boxes + Tap-to-Undo)
                S_INPUT_BOXES: begin
                    display_mode <= 3'd0;
                    unlocked     <= 1'b0;

                    if (cls_done) begin
                        case (filled_count)
                            2'd0: begin filled0 <= 1'b1; img0 <= img_in; cls0 <= class_idx; filled_count <= 2'd1; end
                            2'd1: begin filled1 <= 1'b1; img1 <= img_in; cls1 <= class_idx; filled_count <= 2'd2; end
                            2'd2: begin filled2 <= 1'b1; img2 <= img_in; cls2 <= class_idx; filled_count <= 2'd3; end
                            2'd3: begin
                                filled3 <= 1'b1; img3 <= img_in; cls3 <= class_idx;
                                filled_count <= 2'd0;
                                timer        <= 0;
                                state        <= S_WAIT_EVAL;
                            end
                            default: filled_count <= 2'd0;
                        endcase
                    end else if (btn_released_tap) begin
                        case (filled_count)
                            2'd1: begin filled0 <= 1'b0; img0 <= 256'd0; filled_count <= 2'd0; end
                            2'd2: begin filled1 <= 1'b0; img1 <= 256'd0; filled_count <= 2'd1; end
                            2'd3: begin filled2 <= 1'b0; img2 <= 256'd0; filled_count <= 2'd2; end
                            default: ;
                        endcase
                    end
                end

                // 3. Preview 4th shape for 500 ms before evaluating password
                S_WAIT_EVAL: begin
                    display_mode <= 3'd0;
                    unlocked     <= 1'b0;
                    if (timer == HALF_SEC - 1) begin
                        timer <= 0;
                        if (cls0 == pass0 && cls1 == pass1 && cls2 == pass2 && cls3 == pass3) begin
                            state        <= S_UNLOCKED;
                            display_mode <= 3'd2; // UNLOCKED
                            unlocked     <= 1'b1;
                        end else begin
                            state        <= S_WRONG;
                            display_mode <= 3'd3; // WRONG!
                            unlocked     <= 1'b0;
                        end
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // 4. Unlocked: Hold joystick button 1.0s to lock, or press BTNU to reprogram password
                S_UNLOCKED: begin
                    display_mode <= 3'd2;
                    unlocked     <= 1'b1;

                    if (set_rise) begin
                        timer        <= 0;
                        display_mode <= 3'd4; // SET PASS
                        state        <= S_SET_BANNER;
                    end else if (btn_pressed && btn_hold_cnt == ONE_SEC - 1) begin
                        timer        <= 0;
                        unlocked     <= 1'b0;
                        display_mode <= 3'd1;
                        state        <= S_START_LOCKED;
                    end
                end

                // 5. Wrong Sequence: Show "WRONG!" for 1.0s
                S_WRONG: begin
                    display_mode <= 3'd3;
                    unlocked     <= 1'b0;
                    if (timer == ONE_SEC - 1) begin
                        timer <= 0;
                        state <= S_START_LOCKED;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // 6. Show "SET PASS" banner for 800 ms
                S_SET_BANNER: begin
                    display_mode <= 3'd4;
                    unlocked     <= 1'b1;
                    if (timer == SET_BANNER_CLK - 1) begin
                        timer        <= 0;
                        filled_count <= 2'd0;
                        filled0 <= 1'b0; filled1 <= 1'b0; filled2 <= 1'b0; filled3 <= 1'b0;
                        display_mode <= 3'd5; // SET BOXES
                        state        <= S_SET_BOXES;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // 7. Record 4 New Password Shapes (supports Tap-to-Undo)
                S_SET_BOXES: begin
                    display_mode <= 3'd5;
                    unlocked     <= 1'b1;

                    if (cls_done) begin
                        case (filled_count)
                            2'd0: begin filled0 <= 1'b1; img0 <= img_in; cls0 <= class_idx; filled_count <= 2'd1; end
                            2'd1: begin filled1 <= 1'b1; img1 <= img_in; cls1 <= class_idx; filled_count <= 2'd2; end
                            2'd2: begin filled2 <= 1'b1; img2 <= img_in; cls2 <= class_idx; filled_count <= 2'd3; end
                            2'd3: begin
                                filled3 <= 1'b1; img3 <= img_in; cls3 <= class_idx;
                                filled_count    <= 2'd0;
                                timer           <= 0;
                                in_saved_banner <= 1'b0;
                                state           <= S_SET_WAIT;
                            end
                            default: filled_count <= 2'd0;
                        endcase
                    end else if (btn_released_tap) begin
                        case (filled_count)
                            2'd1: begin filled0 <= 1'b0; img0 <= 256'd0; filled_count <= 2'd0; end
                            2'd2: begin filled1 <= 1'b0; img1 <= 256'd0; filled_count <= 2'd1; end
                            2'd3: begin filled2 <= 1'b0; img2 <= 256'd0; filled_count <= 2'd2; end
                            default: ;
                        endcase
                    end
                end

                // 8. Preview 4th new password shape for 500 ms, then show "SAVED!" for 1.0s
                S_SET_WAIT: begin
                    if (!in_saved_banner) begin
                        display_mode <= 3'd5;
                        if (timer == HALF_SEC - 1) begin
                            pass0 <= cls0;
                            pass1 <= cls1;
                            pass2 <= cls2;
                            pass3 <= cls3;
                            timer           <= 0;
                            in_saved_banner <= 1'b1;
                            display_mode    <= 3'd6; // SAVED!
                        end else begin
                            timer <= timer + 1;
                        end
                    end else begin
                        display_mode <= 3'd6; // SAVED!
                        if (timer == ONE_SEC - 1) begin
                            timer           <= 0;
                            in_saved_banner <= 1'b0;
                            unlocked        <= 1'b0;
                            state           <= S_START_LOCKED;
                        end else begin
                            timer <= timer + 1;
                        end
                    end
                end

                default: state <= S_START_LOCKED;
            endcase
        end
    end
endmodule