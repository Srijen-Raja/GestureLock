`timescale 1ns / 1ps

module oled_display_wrapper (
    input  wire       clk,             // 100 MHz System Clock
    input  wire       rst,             // Active-high Reset (btnc)
    input  wire       update_valid,    // Pulse on successful classification (cls_done)
    input  wire       reject_valid,    // Pulse on rejected stroke (stroke_reject)
    input  wire       active_stroke,   // High while user is drawing (active)
    input  wire [3:0] class_idx,       // Predicted gesture class (0..6)
    output reg        oled_sclk,       // SPI Clock (AB12)
    output reg        oled_sdin,       // SPI MOSI Data (AA12)
    output reg        oled_dc,         // Data / Command Select (U10)
    output reg        oled_res,        // Display Reset (U9)
    output reg        oled_vbat,       // Display Power, Active Low (U11)
    output reg        oled_vdd         // Logic Power, Active Low (U12)
);

    // ------------------------------------------------------------------------
    // 1. ASCII String Decoder
    // ------------------------------------------------------------------------
    reg [127:0] line1_str; // 16 characters x 8 bits
    reg [127:0] line2_str;

    always @(*) begin
        if (active_stroke)
            line1_str = "STATUS: DRAWING ";
        else
            line1_str = "STATUS: READY   ";

        if (reject_valid)
            line2_str = "RESULT: REJECTED";
        else begin
            case (class_idx)
                4'd0: line2_str = "GESTURE: CIRCLE ";
                4'd1: line2_str = "GESTURE: DOWN   ";
                4'd2: line2_str = "GESTURE: HLINE  ";
                4'd3: line2_str = "GESTURE: LEFT   ";
                4'd4: line2_str = "GESTURE: RIGHT  ";
                4'd5: line2_str = "GESTURE: UP     ";
                4'd6: line2_str = "GESTURE: VLINE  ";
                default: line2_str = "GESTURE: UNKNOWN";
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 2. 8x8 ASCII Font ROM (Upper-case letters, space, colon)
    // ------------------------------------------------------------------------
    function [7:0] get_font_col;
        input [7:0] ascii_char;
        input [2:0] col_idx; // 0..4 font data, 5..7 spacing
        begin
            if (col_idx > 3'd4) begin
                get_font_col = 8'h00; // 3-pixel spacing between characters
            end else begin
                case (ascii_char)
                    "A": case(col_idx) 3'd0: get_font_col = 8'h7C; 3'd1: get_font_col = 8'h12; 3'd2: get_font_col = 8'h11; 3'd3: get_font_col = 8'h12; default: get_font_col = 8'h7C; endcase
                    "B": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h49; 3'd2: get_font_col = 8'h49; 3'd3: get_font_col = 8'h49; default: get_font_col = 8'h36; endcase
                    "C": case(col_idx) 3'd0: get_font_col = 8'h3E; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h41; 3'd3: get_font_col = 8'h41; default: get_font_col = 8'h22; endcase
                    "D": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h41; 3'd3: get_font_col = 8'h22; default: get_font_col = 8'h1C; endcase
                    "E": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h49; 3'd2: get_font_col = 8'h49; 3'd3: get_font_col = 8'h49; default: get_font_col = 8'h41; endcase
                    "F": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h09; 3'd2: get_font_col = 8'h09; 3'd3: get_font_col = 8'h09; default: get_font_col = 8'h01; endcase
                    "G": case(col_idx) 3'd0: get_font_col = 8'h3E; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h49; 3'd3: get_font_col = 8'h49; default: get_font_col = 8'h7A; endcase
                    "H": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h08; 3'd2: get_font_col = 8'h08; 3'd3: get_font_col = 8'h08; default: get_font_col = 8'h7F; endcase
                    "I": case(col_idx) 3'd0: get_font_col = 8'h00; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h7F; 3'd3: get_font_col = 8'h41; default: get_font_col = 8'h00; endcase
                    "J": case(col_idx) 3'd0: get_font_col = 8'h20; 3'd1: get_font_col = 8'h40; 3'd2: get_font_col = 8'h41; 3'd3: get_font_col = 8'h3F; default: get_font_col = 8'h01; endcase
                    "K": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h08; 3'd2: get_font_col = 8'h14; 3'd3: get_font_col = 8'h22; default: get_font_col = 8'h41; endcase
                    "L": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h40; 3'd2: get_font_col = 8'h40; 3'd3: get_font_col = 8'h40; default: get_font_col = 8'h40; endcase
                    "M": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h02; 3'd2: get_font_col = 8'h0C; 3'd3: get_font_col = 8'h02; default: get_font_col = 8'h7F; endcase
                    "N": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h04; 3'd2: get_font_col = 8'h08; 3'd3: get_font_col = 8'h10; default: get_font_col = 8'h7F; endcase
                    "O": case(col_idx) 3'd0: get_font_col = 8'h3E; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h41; 3'd3: get_font_col = 8'h41; default: get_font_col = 8'h3E; endcase
                    "P": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h09; 3'd2: get_font_col = 8'h09; 3'd3: get_font_col = 8'h09; default: get_font_col = 8'h06; endcase
                    "Q": case(col_idx) 3'd0: get_font_col = 8'h3E; 3'd1: get_font_col = 8'h41; 3'd2: get_font_col = 8'h51; 3'd3: get_font_col = 8'h21; default: get_font_col = 8'h5E; endcase
                    "R": case(col_idx) 3'd0: get_font_col = 8'h7F; 3'd1: get_font_col = 8'h09; 3'd2: get_font_col = 8'h19; 3'd3: get_font_col = 8'h29; default: get_font_col = 8'h46; endcase
                    "S": case(col_idx) 3'd0: get_font_col = 8'h26; 3'd1: get_font_col = 8'h49; 3'd2: get_font_col = 8'h49; 3'd3: get_font_col = 8'h49; default: get_font_col = 8'h32; endcase
                    "T": case(col_idx) 3'd0: get_font_col = 8'h01; 3'd1: get_font_col = 8'h01; 3'd2: get_font_col = 8'h7F; 3'd3: get_font_col = 8'h01; default: get_font_col = 8'h01; endcase
                    "U": case(col_idx) 3'd0: get_font_col = 8'h3F; 3'd1: get_font_col = 8'h40; 3'd2: get_font_col = 8'h40; 3'd3: get_font_col = 8'h40; default: get_font_col = 8'h3F; endcase
                    "V": case(col_idx) 3'd0: get_font_col = 8'h1F; 3'd1: get_font_col = 8'h20; 3'd2: get_font_col = 8'h40; 3'd3: get_font_col = 8'h20; default: get_font_col = 8'h1F; endcase
                    "W": case(col_idx) 3'd0: get_font_col = 8'h3F; 3'd1: get_font_col = 8'h40; 3'd2: get_font_col = 8'h38; 3'd3: get_font_col = 8'h40; default: get_font_col = 8'h3F; endcase
                    "X": case(col_idx) 3'd0: get_font_col = 8'h63; 3'd1: get_font_col = 8'h14; 3'd2: get_font_col = 8'h08; 3'd3: get_font_col = 8'h14; default: get_font_col = 8'h63; endcase
                    "Y": case(col_idx) 3'd0: get_font_col = 8'h07; 3'd1: get_font_col = 8'h08; 3'd2: get_font_col = 8'h70; 3'd3: get_font_col = 8'h08; default: get_font_col = 8'h07; endcase
                    "Z": case(col_idx) 3'd0: get_font_col = 8'h61; 3'd1: get_font_col = 8'h51; 3'd2: get_font_col = 8'h49; 3'd3: get_font_col = 8'h45; default: get_font_col = 8'h43; endcase
                    ":": case(col_idx) 3'd1: get_font_col = 8'h36; 3'd2: get_font_col = 8'h36; default: get_font_col = 8'h00; endcase
                    default: get_font_col = 8'h00;
                endcase
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // 3. SSD1306 Initialization Command List (22 Bytes)
    // ------------------------------------------------------------------------
    reg [7:0] init_cmds [0:21];
    initial begin
        init_cmds[0]  = 8'hAE; // Display OFF
        init_cmds[1]  = 8'hD5; // Display Clock Divide Ratio
        init_cmds[2]  = 8'h80; 
        init_cmds[3]  = 8'hA8; // Multiplex Ratio
        init_cmds[4]  = 8'h1F; // 128x32
        init_cmds[5]  = 8'hD3; // Display Offset
        init_cmds[6]  = 8'h00; 
        init_cmds[7]  = 8'h40; // Display Start Line (0)
        init_cmds[8]  = 8'h8D; // Charge Pump Control
        init_cmds[9]  = 8'h14; // Enable Charge Pump
        init_cmds[10] = 8'h20; // Memory Addressing Mode
        init_cmds[11] = 8'h00; // Horizontal Mode
        init_cmds[12] = 8'hA1; // Segment Re-map (COL 127 = SEG0)
        init_cmds[13] = 8'hC8; // COM Output Scan Direction
        init_cmds[14] = 8'hDA; // COM Hardware Configuration
        init_cmds[15] = 8'h02; 
        init_cmds[16] = 8'h81; // Set Contrast Control
        init_cmds[17] = 8'h8F; 
        init_cmds[18] = 8'hD9; // Set Pre-charge Period
        init_cmds[19] = 8'hF1; 
        init_cmds[20] = 8'hDB; // Set VCOMH Deselect Level
        init_cmds[21] = 8'h40; 
    end

    // ------------------------------------------------------------------------
    // 4. Low-Level SPI Serializer Engine (5 MHz)
    // ------------------------------------------------------------------------
    reg       spi_start = 1'b0;
    reg [7:0] spi_tx_byte = 8'h00;
    reg       spi_busy = 1'b0;

    reg [4:0] spi_clk_cnt = 0;
    reg [3:0] bit_idx = 0;
    reg [7:0] shift_reg = 8'h00;

    always @(posedge clk) begin
        if (rst) begin
            oled_sclk   <= 1'b1;
            oled_sdin   <= 1'b0;
            spi_busy    <= 1'b0;
            spi_clk_cnt <= 0;
            bit_idx     <= 0;
        end else begin
            if (spi_start && !spi_busy) begin
                spi_busy    <= 1'b1;
                shift_reg   <= spi_tx_byte;
                bit_idx     <= 4'd7;
                spi_clk_cnt <= 0;
                oled_sclk   <= 1'b1;
                oled_sdin   <= spi_tx_byte[7];
            end else if (spi_busy) begin
                if (spi_clk_cnt == 5'd9) begin
                    oled_sclk   <= 1'b0; // Falling edge
                    spi_clk_cnt <= spi_clk_cnt + 1;
                end else if (spi_clk_cnt == 5'd19) begin
                    oled_sclk   <= 1'b1; // Rising edge (SSD1306 latches data)
                    spi_clk_cnt <= 0;
                    if (bit_idx == 0) begin
                        spi_busy <= 1'b0;
                    end else begin
                        bit_idx   <= bit_idx - 1;
                        oled_sdin <= shift_reg[bit_idx - 1];
                    end
                end else begin
                    spi_clk_cnt <= spi_clk_cnt + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 5. Main Initialization & Screen Refresh State Machine
    // ------------------------------------------------------------------------
    localparam S_BOOT_DELAY= 0,
               S_PWR_VDD   = 1,
               S_RST_LOW   = 2,
               S_RST_HIGH  = 3,
               S_INIT_CMDS = 4,
               S_PWR_VBAT  = 5,
               S_DISP_ON   = 6,
               S_IDLE      = 7,
               S_PAGE_ADDR = 8,
               S_COL_LOW   = 9,
               S_COL_HIGH  = 10,
               S_SEND_DATA = 11;

    reg [3:0]  state = S_BOOT_DELAY;
    reg [31:0] delay_cnt = 0;
    reg [4:0]  cmd_idx = 0;

    reg [1:0]  page_cnt = 0;
    reg [6:0]  col_cnt = 0;
    reg        need_refresh = 1'b1;

    // Trigger auto-refresh on text change
    reg prev_active;
    always @(posedge clk) begin
        prev_active <= active_stroke;
        if (rst) begin
            need_refresh <= 1'b1;
        end else if (update_valid || reject_valid || (active_stroke != prev_active)) begin
            need_refresh <= 1'b1;
        end else if (state == S_PAGE_ADDR) begin
            need_refresh <= 1'b0;
        end
    end

    // Extract ASCII char for current page & column
    wire [7:0] cur_char;
    wire [3:0] char_pos = col_cnt[6:3]; // col_cnt / 8
    assign cur_char = (page_cnt == 2'd0) ? line1_str[(15 - char_pos)*8 +: 8] :
                      (page_cnt == 2'd2) ? line2_str[(15 - char_pos)*8 +: 8] : 8'h20;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_PWR_VDD;
            oled_vdd    <= 1'b1;
            oled_vbat   <= 1'b1;
            oled_res    <= 1'b1;
            oled_dc     <= 1'b0;
            delay_cnt   <= 0;
            cmd_idx     <= 0;
            page_cnt    <= 0;
            col_cnt     <= 0;
            spi_start   <= 1'b0;
        end else begin
            spi_start <= 1'b0;

            case (state)
                // Boot delay (20ms) to ensure power rail stability upon FPGA configuration
                S_BOOT_DELAY: begin
                    oled_vdd  <= 1'b1;
                    oled_vbat <= 1'b1;
                    oled_res  <= 1'b1;
                    oled_dc   <= 1'b0;
                    if (delay_cnt == 2_000_000) begin
                        delay_cnt <= 0;
                        state     <= S_PWR_VDD;
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 1. Enable VDD Power (Active LOW) & Wait 5ms
                S_PWR_VDD: begin
                    oled_vdd <= 1'b0;
                    if (delay_cnt == 500_000) begin
                        delay_cnt <= 0;
                        state     <= S_RST_LOW;
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 2. Pulse Reset LOW (1ms)
                S_RST_LOW: begin
                    oled_res <= 1'b0;
                    if (delay_cnt == 100_000) begin
                        delay_cnt <= 0;
                        state     <= S_RST_HIGH;
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 3. Set Reset HIGH & Wait 5ms
                S_RST_HIGH: begin
                    oled_res <= 1'b1;
                    if (delay_cnt == 500_000) begin
                        delay_cnt <= 0;
                        cmd_idx   <= 0;
                        state     <= S_INIT_CMDS;
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 4. Transmit 22 SSD1306 Initialization Commands over SPI
                S_INIT_CMDS: begin
                    oled_dc <= 1'b0; // Command Mode
                    if (!spi_busy && !spi_start) begin
                        if (cmd_idx <= 21) begin
                            spi_tx_byte <= init_cmds[cmd_idx];
                            spi_start   <= 1'b1;
                            cmd_idx     <= cmd_idx + 1;
                        end else begin
                            delay_cnt <= 0;
                            state     <= S_PWR_VBAT;
                        end
                    end
                end

                // 5. Enable VBAT Power (Active LOW) & Wait 100ms for Panel Power
                S_PWR_VBAT: begin
                    oled_vbat <= 1'b0;
                    if (delay_cnt == 10_000_000) begin
                        delay_cnt <= 0;
                        state     <= S_DISP_ON;
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 6. Turn Display ON (0xAF)
                S_DISP_ON: begin
                    oled_dc <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= 8'hAF; // Display ON Command
                        spi_start   <= 1'b1;
                        page_cnt    <= 0;
                        state       <= S_PAGE_ADDR;
                    end
                end

                // 7. Idle / Wait for state updates
                S_IDLE: begin
                    if (need_refresh) begin
                        page_cnt <= 0;
                        state    <= S_PAGE_ADDR;
                    end
                end

                // 8. Set Page Start Address (0xB0..0xB3)
                S_PAGE_ADDR: begin
                    oled_dc <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= 8'hB0 + page_cnt;
                        spi_start   <= 1'b1;
                        state       <= S_COL_LOW;
                    end
                end

                // 9. Set Lower Column Address (0x00)
                S_COL_LOW: begin
                    oled_dc <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= 8'h00;
                        spi_start   <= 1'b1;
                        state       <= S_COL_HIGH;
                    end
                end

                // 10. Set Higher Column Address (0x10)
                S_COL_HIGH: begin
                    oled_dc <= 1'b0;
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= 8'h10;
                        spi_start   <= 1'b1;
                        col_cnt     <= 0;
                        state       <= S_SEND_DATA;
                    end
                end

                // 11. Stream Font Data Bytes to Display RAM
                S_SEND_DATA: begin
                    oled_dc <= 1'b1; // Data Mode
                    if (!spi_busy && !spi_start) begin
                        spi_tx_byte <= get_font_col(cur_char, col_cnt[2:0]);
                        spi_start   <= 1'b1;

                        if (col_cnt == 127) begin
                            if (page_cnt == 3) begin
                                state <= S_IDLE;
                            end else begin
                                page_cnt <= page_cnt + 1;
                                state    <= S_PAGE_ADDR;
                            end
                        end else begin
                            col_cnt <= col_cnt + 1;
                        end
                    end
                end

                default: state <= S_BOOT_DELAY;
            endcase
        end
    end

endmodule