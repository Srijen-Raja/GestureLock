// Pmod JSTK2 SPI master (mode 0, MSB first).
// Every 1/SAMPLE_HZ seconds it reads one 5-byte frame:
//   byte0 X low, byte1 X high, byte2 Y low, byte3 Y high, byte4 buttons.
// Timing follows what worked in your Vitis test: 15-20 us CS setup, 25 us between bytes.
module jstk2_spi #(
    parameter CLK_HZ    = 100_000_000,
    parameter SCK_HZ    = 500_000,     // JSTK2 limit is about 1 MHz
    parameter SAMPLE_HZ = 100          // matches the 100 Hz used for the training data
)(
    input  wire        clk,
    input  wire        rst,            // synchronous, active high
    output reg         cs_n,
    output reg         sck,
    output wire        mosi,
    input  wire        miso,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output reg  [2:0]  btn,
    output reg         valid           // 1-clock pulse when x/y/btn are updated
);
    localparam HALF       = CLK_HZ / (2 * SCK_HZ);        // clocks per SCK half period
    localparam US         = CLK_HZ / 1_000_000;           // clocks per microsecond
    localparam T_SETUP    = 20 * US;                      // CS low -> first clock
    localparam T_GAP      = 25 * US;                      // after each byte
    localparam SAMPLE_CLK = CLK_HZ / SAMPLE_HZ;

    assign mosi = 1'b0;                                   // we send 0x00 in every byte

    // synchronise MISO (it comes from outside the FPGA)
    reg miso_m, miso_s;
    always @(posedge clk) begin miso_m <= miso; miso_s <= miso_m; end

    // sample timer
    reg [31:0] sample_cnt;
    wire       tick = (sample_cnt == SAMPLE_CLK - 1);
    always @(posedge clk) begin
        if (rst || tick) sample_cnt <= 0;
        else             sample_cnt <= sample_cnt + 1;
    end

    localparam S_IDLE = 3'd0, S_SETUP = 3'd1, S_LOW = 3'd2, S_HIGH = 3'd3, S_GAP = 3'd4;
    reg [2:0]  state;
    reg [31:0] tmr;
    reg [2:0]  bitcnt, bytecnt;
    reg [7:0]  shreg;
    reg [7:0]  rx0, rx1, rx2, rx3;
    wire [7:0] rx_now = {shreg[6:0], miso_s};              // byte being completed

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            state <= S_IDLE; cs_n <= 1'b1; sck <= 1'b0; tmr <= 0;
            bitcnt <= 0; bytecnt <= 0; shreg <= 0;
            x <= 0; y <= 0; btn <= 0;
        end else begin
            case (state)
            S_IDLE: begin
                cs_n <= 1'b1; sck <= 1'b0;
                if (tick) begin cs_n <= 1'b0; tmr <= 0; bytecnt <= 0; bitcnt <= 0; state <= S_SETUP; end
            end
            S_SETUP: begin
                if (tmr == T_SETUP - 1) begin tmr <= 0; state <= S_LOW; end
                else tmr <= tmr + 1;
            end
            S_LOW: begin                                    // SCK low half period
                if (tmr == HALF - 1) begin tmr <= 0; sck <= 1'b1; state <= S_HIGH; end
                else tmr <= tmr + 1;
            end
            S_HIGH: begin                                   // SCK high half period
                if (tmr == HALF - 1) begin
                    tmr <= 0; sck <= 1'b0;
                    shreg <= rx_now;                        // sample MISO at the end of the high phase
                    if (bitcnt == 3'd7) begin
                        case (bytecnt)
                            3'd0: rx0 <= rx_now;
                            3'd1: rx1 <= rx_now;
                            3'd2: rx2 <= rx_now;
                            3'd3: rx3 <= rx_now;
                            default: ;
                        endcase
                        state <= S_GAP;
                    end else begin
                        bitcnt <= bitcnt + 1; state <= S_LOW;
                    end
                end else tmr <= tmr + 1;
            end
            S_GAP: begin
                if (tmr == T_GAP - 1) begin
                    tmr <= 0; bitcnt <= 0;
                    if (bytecnt == 3'd4) begin               // frame finished
                        x     <= {rx1[1:0], rx0};
                        y     <= {rx3[1:0], rx2};
                        btn   <= shreg[2:0];                 // byte 4 = buttons
                        valid <= 1'b1;
                        cs_n  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        bytecnt <= bytecnt + 1; state <= S_LOW;
                    end
                end else tmr <= tmr + 1;
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
