`timescale 1ns / 1ps

// lockFSM.v: Evaluates detected gesture sequence to lock or unlock system
module lockFSM (
    input  wire       clk,
    input  wire       rst,
    input  wire       class_valid,       // 1-clock pulse from cnn_engine
    input  wire [2:0] predicted_class,   // detected class index (0..6)
    output reg        unlocked,          // 1 = system unlocked, 0 = locked
    output reg  [2:0] step_status        // current progress step (0..4)
);
    // Class mapping (Alphabetical Order):
    // 0: Circle, 1: Down, 2: Hline, 3: Left, 4: Right, 5: Up, 6: Vline
    localparam G_CIRCLE = 3'd0;
    localparam G_DOWN   = 3'd1;
    localparam G_UP     = 3'd5;

    // Secret Key Sequence: CIRCLE -> UP -> DOWN -> CIRCLE
    localparam S_LOCKED   = 3'd0;
    localparam S_STEP1    = 3'd1; // Got Circle
    localparam S_STEP2    = 3'd2; // Got Up
    localparam S_STEP3    = 3'd3; // Got Down
    localparam S_UNLOCKED = 3'd4;

    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_LOCKED;
            unlocked    <= 1'b0;
            step_status <= 3'd0;
        end else if (class_valid) begin
            case (state)
                S_LOCKED: begin
                    if (predicted_class == G_CIRCLE) begin
                        state       <= S_STEP1;
                        step_status <= 3'd1;
                    end else begin
                        state       <= S_LOCKED;
                        step_status <= 3'd0;
                    end
                end

                S_STEP1: begin
                    if (predicted_class == G_UP) begin
                        state       <= S_STEP2;
                        step_status <= 3'd2;
                    end else if (predicted_class == G_CIRCLE) begin
                        state       <= S_STEP1; // keep step 1
                        step_status <= 3'd1;
                    end else begin
                        state       <= S_LOCKED;
                        step_status <= 3'd0;
                    end
                end

                S_STEP2: begin
                    if (predicted_class == G_DOWN) begin
                        state       <= S_STEP3;
                        step_status <= 3'd3;
                    end else begin
                        state       <= S_LOCKED;
                        step_status <= 3'd0;
                    end
                end

                S_STEP3: begin
                    if (predicted_class == G_CIRCLE) begin
                        state       <= S_UNLOCKED;
                        unlocked    <= 1'b1;
                        step_status <= 3'd4;
                    end else begin
                        state       <= S_LOCKED;
                        step_status <= 3'd0;
                    end
                end

                S_UNLOCKED: begin
                    // Drawing a circle while unlocked locks the system again
                    if (predicted_class == G_CIRCLE) begin
                        state       <= S_LOCKED;
                        unlocked    <= 1'b0;
                        step_status <= 3'd0;
                    end
                end

                default: state <= S_LOCKED;
            endcase
        end
    end
endmodule