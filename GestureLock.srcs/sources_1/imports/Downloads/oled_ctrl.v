// On-board 128x32 OLED (SSD1306) driver for the ZedBoard.
// Shows the 16x16 stroke image (enlarged 2x, inside a 32x32 box on left) and the class name (right).
// Software 180-degree rotation handles display flipping without breaking hardware multiplexing.
module oled_ctrl #(
    parameter CLK_HZ   = 100_000_000,
    parameter SCK_HZ   = 5_000_000,
    parameter SIM_FAST = 0,                 // 1 = shorten the power-up delays 1000x (simulation only)
    parameter [0:0] VDD_ON  = 1'b0,
    parameter [0:0] VBAT_ON = 1'b0,
    parameter [7:0] SEG_CMD = 8'hA1,        // Restored to native hardware remap
    parameter [7:0] COM_CMD = 8'hC8,        // Restored to native COM scan mode
    parameter [7:0] COMPINS = 8'h20
)(
    input  wire         clk,
    input  wire         upd,                // pulse: new result, latch img and cls
    input  wire [255:0] img,                // bit index = row*16 + column, row 0 = top
    input  wire [3:0]   cls,                // class number 0..6
    output reg          oled_sclk,
    output reg          oled_sdin,
    output reg          oled_dc,            // 0 = command, 1 = data
    output reg          oled_res,
    output reg          oled_vbat,
    output reg          oled_vdd
);
    localparam HALF = CLK_HZ / (2 * SCK_HZ);
    localparam US   = CLK_HZ / 1_000_000;
    localparam MS   = SIM_FAST ? US : CLK_HZ / 1000;
    localparam T_VDD  = 20  * MS;           // VDD on -> reset
    localparam T_RES  = 1   * MS;           // reset low time, and wait after reset
    localparam T_VBAT = 100 * MS;           // VBAT on -> display on

    // ---------------- font and text tables (generated) ----------------
    function [7:0] glyph_row;
        input [4:0] ch;
        input [2:0] row;
        begin
            case ({ch, row})
            {5'd0, 3'd0}: glyph_row = 8'h00;   // ' ' row 0
            {5'd0, 3'd1}: glyph_row = 8'h00;   // ' ' row 1
            {5'd0, 3'd2}: glyph_row = 8'h00;   // ' ' row 2
            {5'd0, 3'd3}: glyph_row = 8'h00;   // ' ' row 3
            {5'd0, 3'd4}: glyph_row = 8'h00;   // ' ' row 4
            {5'd0, 3'd5}: glyph_row = 8'h00;   // ' ' row 5
            {5'd0, 3'd6}: glyph_row = 8'h00;   // ' ' row 6
            {5'd0, 3'd7}: glyph_row = 8'h00;   // ' ' row 7
            {5'd1, 3'd0}: glyph_row = 8'h3C;   // 'C' row 0
            {5'd1, 3'd1}: glyph_row = 8'h66;   // 'C' row 1
            {5'd1, 3'd2}: glyph_row = 8'hC0;   // 'C' row 2
            {5'd1, 3'd3}: glyph_row = 8'hC0;   // 'C' row 3
            {5'd1, 3'd4}: glyph_row = 8'hC0;   // 'C' row 4
            {5'd1, 3'd5}: glyph_row = 8'h66;   // 'C' row 5
            {5'd1, 3'd6}: glyph_row = 8'h3C;   // 'C' row 6
            {5'd1, 3'd7}: glyph_row = 8'h00;   // 'C' row 7
            {5'd2, 3'd0}: glyph_row = 8'h3C;   // 'I' row 0
            {5'd2, 3'd1}: glyph_row = 8'h18;   // 'I' row 1
            {5'd2, 3'd2}: glyph_row = 8'h18;   // 'I' row 2
            {5'd2, 3'd3}: glyph_row = 8'h18;   // 'I' row 3
            {5'd2, 3'd4}: glyph_row = 8'h18;   // 'I' row 4
            {5'd2, 3'd5}: glyph_row = 8'h18;   // 'I' row 5
            {5'd2, 3'd6}: glyph_row = 8'h3C;   // 'I' row 6
            {5'd2, 3'd7}: glyph_row = 8'h00;   // 'I' row 7
            {5'd3, 3'd0}: glyph_row = 8'hFC;   // 'R' row 0
            {5'd3, 3'd1}: glyph_row = 8'h66;   // 'R' row 1
            {5'd3, 3'd2}: glyph_row = 8'h66;   // 'R' row 2
            {5'd3, 3'd3}: glyph_row = 8'h7C;   // 'R' row 3
            {5'd3, 3'd4}: glyph_row = 8'h6C;   // 'R' row 4
            {5'd3, 3'd5}: glyph_row = 8'h66;   // 'R' row 5
            {5'd3, 3'd6}: glyph_row = 8'hE6;   // 'R' row 6
            {5'd3, 3'd7}: glyph_row = 8'h00;   // 'R' row 7
            {5'd4, 3'd0}: glyph_row = 8'hF0;   // 'L' row 0
            {5'd4, 3'd1}: glyph_row = 8'h60;   // 'L' row 1
            {5'd4, 3'd2}: glyph_row = 8'h60;   // 'L' row 2
            {5'd4, 3'd3}: glyph_row = 8'h60;   // 'L' row 3
            {5'd4, 3'd4}: glyph_row = 8'h62;   // 'L' row 4
            {5'd4, 3'd5}: glyph_row = 8'h66;   // 'L' row 5
            {5'd4, 3'd6}: glyph_row = 8'hFE;   // 'L' row 6
            {5'd4, 3'd7}: glyph_row = 8'h00;   // 'L' row 7
            {5'd5, 3'd0}: glyph_row = 8'hFE;   // 'E' row 0
            {5'd5, 3'd1}: glyph_row = 8'h62;   // 'E' row 1
            {5'd5, 3'd2}: glyph_row = 8'h68;   // 'E' row 2
            {5'd5, 3'd3}: glyph_row = 8'h78;   // 'E' row 3
            {5'd5, 3'd4}: glyph_row = 8'h68;   // 'E' row 4
            {5'd5, 3'd5}: glyph_row = 8'h62;   // 'E' row 5
            {5'd5, 3'd6}: glyph_row = 8'hFE;   // 'E' row 6
            {5'd5, 3'd7}: glyph_row = 8'h00;   // 'E' row 7
            {5'd6, 3'd0}: glyph_row = 8'hF8;   // 'D' row 0
            {5'd6, 3'd1}: glyph_row = 8'h6C;   // 'D' row 1
            {5'd6, 3'd2}: glyph_row = 8'h66;   // 'D' row 2
            {5'd6, 3'd3}: glyph_row = 8'h66;   // 'D' row 3
            {5'd6, 3'd4}: glyph_row = 8'h66;   // 'D' row 4
            {5'd6, 3'd5}: glyph_row = 8'h6C;   // 'D' row 5
            {5'd6, 3'd6}: glyph_row = 8'hF8;   // 'D' row 6
            {5'd6, 3'd7}: glyph_row = 8'h00;   // 'D' row 7
            {5'd7, 3'd0}: glyph_row = 8'h38;   // 'O' row 0
            {5'd7, 3'd1}: glyph_row = 8'h6C;   // 'O' row 1
            {5'd7, 3'd2}: glyph_row = 8'hC6;   // 'O' row 2
            {5'd7, 3'd3}: glyph_row = 8'hC6;   // 'O' row 3
            {5'd7, 3'd4}: glyph_row = 8'hC6;   // 'O' row 4
            {5'd7, 3'd5}: glyph_row = 8'h6C;   // 'O' row 5
            {5'd7, 3'd6}: glyph_row = 8'h38;   // 'O' row 6
            {5'd7, 3'd7}: glyph_row = 8'h00;   // 'O' row 7
            {5'd8, 3'd0}: glyph_row = 8'hC6;   // 'W' row 0
            {5'd8, 3'd1}: glyph_row = 8'hC6;   // 'W' row 1
            {5'd8, 3'd2}: glyph_row = 8'hC6;   // 'W' row 2
            {5'd8, 3'd3}: glyph_row = 8'hD6;   // 'W' row 3
            {5'd8, 3'd4}: glyph_row = 8'hFE;   // 'W' row 4
            {5'd8, 3'd5}: glyph_row = 8'hEE;   // 'W' row 5
            {5'd8, 3'd6}: glyph_row = 8'hC6;   // 'W' row 6
            {5'd8, 3'd7}: glyph_row = 8'h00;   // 'W' row 7
            {5'd9, 3'd0}: glyph_row = 8'hC6;   // 'N' row 0
            {5'd9, 3'd1}: glyph_row = 8'hE6;   // 'N' row 1
            {5'd9, 3'd2}: glyph_row = 8'hF6;   // 'N' row 2
            {5'd9, 3'd3}: glyph_row = 8'hDE;   // 'N' row 3
            {5'd9, 3'd4}: glyph_row = 8'hCE;   // 'N' row 4
            {5'd9, 3'd5}: glyph_row = 8'hC6;   // 'N' row 5
            {5'd9, 3'd6}: glyph_row = 8'hC6;   // 'N' row 6
            {5'd9, 3'd7}: glyph_row = 8'h00;   // 'N' row 7
            {5'd10, 3'd0}: glyph_row = 8'hC6;   // 'H' row 0
            {5'd10, 3'd1}: glyph_row = 8'hC6;   // 'H' row 1
            {5'd10, 3'd2}: glyph_row = 8'hC6;   // 'H' row 2
            {5'd10, 3'd3}: glyph_row = 8'hFE;   // 'H' row 3
            {5'd10, 3'd4}: glyph_row = 8'hC6;   // 'H' row 4
            {5'd10, 3'd5}: glyph_row = 8'hC6;   // 'H' row 5
            {5'd10, 3'd6}: glyph_row = 8'hC6;   // 'H' row 6
            {5'd10, 3'd7}: glyph_row = 8'h00;   // 'H' row 7
            {5'd11, 3'd0}: glyph_row = 8'hFE;   // 'F' row 0
            {5'd11, 3'd1}: glyph_row = 8'h62;   // 'F' row 1
            {5'd11, 3'd2}: glyph_row = 8'h68;   // 'F' row 2
            {5'd11, 3'd3}: glyph_row = 8'h78;   // 'F' row 3
            {5'd11, 3'd4}: glyph_row = 8'h68;   // 'F' row 4
            {5'd11, 3'd5}: glyph_row = 8'h60;   // 'F' row 5
            {5'd11, 3'd6}: glyph_row = 8'hF0;   // 'F' row 6
            {5'd11, 3'd7}: glyph_row = 8'h00;   // 'F' row 7
            {5'd12, 3'd0}: glyph_row = 8'h7E;   // 'T' row 0
            {5'd12, 3'd1}: glyph_row = 8'h18;   // 'T' row 1
            {5'd12, 3'd2}: glyph_row = 8'h18;   // 'T' row 2
            {5'd12, 3'd3}: glyph_row = 8'h18;   // 'T' row 3
            {5'd12, 3'd4}: glyph_row = 8'h18;   // 'T' row 4
            {5'd12, 3'd5}: glyph_row = 8'h18;   // 'T' row 5
            {5'd12, 3'd6}: glyph_row = 8'h18;   // 'T' row 6
            {5'd12, 3'd7}: glyph_row = 8'h00;   // 'T' row 7
            {5'd13, 3'd0}: glyph_row = 8'h3C;   // 'G' row 0
            {5'd13, 3'd1}: glyph_row = 8'h66;   // 'G' row 1
            {5'd13, 3'd2}: glyph_row = 8'hC0;   // 'G' row 2
            {5'd13, 3'd3}: glyph_row = 8'hCE;   // 'G' row 3
            {5'd13, 3'd4}: glyph_row = 8'hC6;   // 'G' row 4
            {5'd13, 3'd5}: glyph_row = 8'h66;   // 'G' row 5
            {5'd13, 3'd6}: glyph_row = 8'h3E;   // 'G' row 6
            {5'd13, 3'd7}: glyph_row = 8'h00;   // 'G' row 7
            {5'd14, 3'd0}: glyph_row = 8'hC6;   // 'U' row 0
            {5'd14, 3'd1}: glyph_row = 8'hC6;   // 'U' row 1
            {5'd14, 3'd2}: glyph_row = 8'hC6;   // 'U' row 2
            {5'd14, 3'd3}: glyph_row = 8'hC6;   // 'U' row 3
            {5'd14, 3'd4}: glyph_row = 8'hC6;   // 'U' row 4
            {5'd14, 3'd5}: glyph_row = 8'hC6;   // 'U' row 5
            {5'd14, 3'd6}: glyph_row = 8'h7C;   // 'U' row 6
            {5'd14, 3'd7}: glyph_row = 8'h00;   // 'U' row 7
            {5'd15, 3'd0}: glyph_row = 8'hFC;   // 'P' row 0
            {5'd15, 3'd1}: glyph_row = 8'h66;   // 'P' row 1
            {5'd15, 3'd2}: glyph_row = 8'h66;   // 'P' row 2
            {5'd15, 3'd3}: glyph_row = 8'h7C;   // 'P' row 3
            {5'd15, 3'd4}: glyph_row = 8'h60;   // 'P' row 4
            {5'd15, 3'd5}: glyph_row = 8'h60;   // 'P' row 5
            {5'd15, 3'd6}: glyph_row = 8'hF0;   // 'P' row 6
            {5'd15, 3'd7}: glyph_row = 8'h00;   // 'P' row 7
            {5'd16, 3'd0}: glyph_row = 8'hC6;   // 'V' row 0
            {5'd16, 3'd1}: glyph_row = 8'hC6;   // 'V' row 1
            {5'd16, 3'd2}: glyph_row = 8'hC6;   // 'V' row 2
            {5'd16, 3'd3}: glyph_row = 8'hC6;   // 'V' row 3
            {5'd16, 3'd4}: glyph_row = 8'hC6;   // 'V' row 4
            {5'd16, 3'd5}: glyph_row = 8'h6C;   // 'V' row 5
            {5'd16, 3'd6}: glyph_row = 8'h38;   // 'V' row 6
            {5'd16, 3'd7}: glyph_row = 8'h00;   // 'V' row 7
            {5'd17, 3'd0}: glyph_row = 8'h38;   // 'A' row 0
            {5'd17, 3'd1}: glyph_row = 8'h6C;   // 'A' row 1
            {5'd17, 3'd2}: glyph_row = 8'hC6;   // 'A' row 2
            {5'd17, 3'd3}: glyph_row = 8'hC6;   // 'A' row 3
            {5'd17, 3'd4}: glyph_row = 8'hFE;   // 'A' row 4
            {5'd17, 3'd5}: glyph_row = 8'hC6;   // 'A' row 5
            {5'd17, 3'd6}: glyph_row = 8'hC6;   // 'A' row 6
            {5'd17, 3'd7}: glyph_row = 8'h00;   // 'A' row 7
                default: glyph_row = 8'h00;
            endcase
        end
    endfunction

    function [4:0] name_char;
        input [3:0] cl;
        input [2:0] li;
        begin
            case ({cl, li})
            {4'd0, 3'd0}: name_char = 5'd1;   // 'C'
            {4'd0, 3'd1}: name_char = 5'd2;   // 'I'
            {4'd0, 3'd2}: name_char = 5'd3;   // 'R'
            {4'd0, 3'd3}: name_char = 5'd1;   // 'C'
            {4'd0, 3'd4}: name_char = 5'd4;   // 'L'
            {4'd0, 3'd5}: name_char = 5'd5;   // 'E'
            {4'd1, 3'd0}: name_char = 5'd6;   // 'D'
            {4'd1, 3'd1}: name_char = 5'd7;   // 'O'
            {4'd1, 3'd2}: name_char = 5'd8;   // 'W'
            {4'd1, 3'd3}: name_char = 5'd9;   // 'N'
            {4'd2, 3'd0}: name_char = 5'd10;  // 'H'
            {4'd2, 3'd1}: name_char = 5'd4;   // 'L'
            {4'd2, 3'd2}: name_char = 5'd2;   // 'I'
            {4'd2, 3'd3}: name_char = 5'd9;   // 'N'
            {4'd2, 3'd4}: name_char = 5'd5;   // 'E'
            {4'd3, 3'd0}: name_char = 5'd4;   // 'L'
            {4'd3, 3'd1}: name_char = 5'd5;   // 'E'
            {4'd3, 3'd2}: name_char = 5'd11;  // 'F'
            {4'd3, 3'd3}: name_char = 5'd12;  // 'T'
            {4'd4, 3'd0}: name_char = 5'd3;   // 'R'
            {4'd4, 3'd1}: name_char = 5'd2;   // 'I'
            {4'd4, 3'd2}: name_char = 5'd13;  // 'G'
            {4'd4, 3'd3}: name_char = 5'd10;  // 'H'
            {4'd4, 3'd4}: name_char = 5'd12;  // 'T'
            {4'd5, 3'd0}: name_char = 5'd14;  // 'U'
            {4'd5, 3'd1}: name_char = 5'd15;  // 'P'
            {4'd6, 3'd0}: name_char = 5'd16;  // 'V'
            {4'd6, 3'd1}: name_char = 5'd4;   // 'L'
            {4'd6, 3'd2}: name_char = 5'd2;   // 'I'
            {4'd6, 3'd3}: name_char = 5'd9;   // 'N'
            {4'd6, 3'd4}: name_char = 5'd5;   // 'E'
            {4'd7, 3'd0}: name_char = 5'd6;   // 'D'
            {4'd7, 3'd1}: name_char = 5'd3;   // 'R'
            {4'd7, 3'd2}: name_char = 5'd17;  // 'A'
            {4'd7, 3'd3}: name_char = 5'd8;   // 'W'
                default: name_char = 5'd0;
            endcase
        end
    endfunction

    // Generates 8 vertical pixels per byte; applies 180-degree software rotation and box enclosing.
    function [7:0] gen_byte;
        input [1:0]   page;
        input [6:0]   col;
        input [255:0] im;
        input [3:0]   cl;
        integer b;
        reg [7:0] v;
        reg [6:0] vcol, x;
        reg [2:0] li, gx;
        reg [5:0] row, vrow;
        reg [3:0] fr;
        reg [7:0] gl;
        begin
            v = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                row = {page, 3'b000} + b;

                // Software 180-degree rotation mapping
                vrow = 6'd31 - row;
                vcol = 7'd127 - col;

                if (vcol < 32) begin
                    // Border box around the 32x32 shape area on the visual left side
                    if (vcol == 0 || vcol == 31 || vrow == 0 || vrow == 31) begin
                        v[b] = 1'b1;
                    end else begin
                        v[b] = im[{vrow[4:1], vcol[4:1]}];       // Scaled shape pixel
                    end
                end else begin
                    x  = vcol - 7'd32;                          // 0..95 inside text area
                    li = x[6:4];                               // letter index 0..5
                    gx = x[3:1];                               // glyph column 0..7
                    if (vrow >= 8 && vrow < 24) begin          // text rows 8..23
                        fr = (vrow - 6'd8) >> 1;
                        gl = glyph_row(name_char(cl, li), fr[2:0]);
                        v[b] = gl[7 - gx];
                    end
                end
            end
            gen_byte = v;
        end
    endfunction

    function [7:0] init_byte;
        input [3:0] i;
        begin
            case (i)
                4'd0: init_byte = 8'hAE;   // display off
                4'd1: init_byte = 8'h8D;   // charge pump ...
                4'd2: init_byte = 8'h14;   // ... enabled
                4'd3: init_byte = 8'hD9;   // pre-charge period ...
                4'd4: init_byte = 8'hF1;   // ... 15 / 1
                4'd5: init_byte = 8'h20;   // memory addressing mode ...
                4'd6: init_byte = 8'h00;   // ... horizontal
                4'd7: init_byte = SEG_CMD;
                4'd8: init_byte = COM_CMD;
                4'd9: init_byte = 8'hDA;   // COM pins configuration ...
                default: init_byte = COMPINS;
            endcase
        end
    endfunction

    function [7:0] frame_cmd;
        input [2:0] i;
        begin
            case (i)
                3'd0: frame_cmd = 8'h21; 3'd1: frame_cmd = 8'h00; 3'd2: frame_cmd = 8'h7F;   // columns 0..127
                3'd3: frame_cmd = 8'h22; 3'd4: frame_cmd = 8'h00; default: frame_cmd = 8'h03; // pages 0..3
            endcase
        end
    endfunction

    // ---------------- byte serialiser (SPI mode 0, MSB first) ----------------
    reg [7:0] tx_byte, sh;
    reg       tx_go, tx_busy;
    reg [3:0] bitn;
    reg [7:0] ck;
    always @(posedge clk) begin
        if (tx_go) begin
            sh <= tx_byte; oled_sdin <= tx_byte[7]; oled_sclk <= 1'b0; bitn <= 0; ck <= 0; tx_busy <= 1'b1;
        end else if (tx_busy) begin
            if (ck == HALF - 1) begin
                ck <= 0;
                if (!oled_sclk) oled_sclk <= 1'b1;                       // rising edge: panel samples the bit
                else begin
                    oled_sclk <= 1'b0;
                    if (bitn == 4'd7) tx_busy <= 1'b0;
                    else begin bitn <= bitn + 1'b1; sh <= {sh[6:0], 1'b0}; oled_sdin <= sh[6]; end
                end
            end else ck <= ck + 1'b1;
        end
    end

    // ---------------- sequencer ----------------
    localparam S_VDD  = 4'd0,
               S_RESL = 4'd1,
               S_RESH = 4'd2,
               S_PREP = 4'd3,
               S_LOAD = 4'd4,
               S_W1   = 4'd5,
               S_W2   = 4'd6,
               S_DONE = 4'd7,
               S_VBAT = 4'd8,
               S_IDLE = 4'd9;

    reg [3:0]   state;
    reg [1:0]   ph;                         // 0 = init commands, 1 = one frame, 2 = display on
    reg [9:0]   idx;
    reg [31:0]  tmr;
    reg [7:0]   data_r;
    reg         powered, pending;
    reg [255:0] img_r, img_n;
    reg [3:0]   cls_r, cls_n;
    wire [9:0]  n_data = idx - 10'd6;
    wire [9:0]  last = (ph == 2'd0) ? 10'd10 : (ph == 2'd1) ? 10'd517 : 10'd0;

    initial begin
        oled_sclk = 0; oled_sdin = 0; oled_dc = 0; oled_res = 0;             // everything quiet while unpowered
        oled_vdd = ~VDD_ON; oled_vbat = ~VBAT_ON;                         // both supplies off
        tx_go = 0; tx_busy = 0; state = S_VDD; ph = 0; idx = 0; tmr = 0; data_r = 0;
        powered = 0; pending = 0; img_r = 256'd0; img_n = 256'd0; cls_r = 4'd7; cls_n = 4'd7;
    end

    always @(posedge clk) begin
        case (state)
        S_VDD: begin
            oled_vdd <= VDD_ON;
            if (tmr == T_VDD - 1) begin tmr <= 0; state <= S_RESL; end else tmr <= tmr + 1;
        end
        S_RESL: begin
            if (tmr == T_RES - 1) begin tmr <= 0; oled_res <= 1'b1; state <= S_RESH; end else tmr <= tmr + 1;
        end
        S_RESH: begin
            if (tmr == T_RES - 1) begin tmr <= 0; ph <= 0; idx <= 0; state <= S_PREP; end else tmr <= tmr + 1;
        end
        S_PREP: begin
            if (ph == 2'd1 && idx >= 10'd6) data_r <= gen_byte(n_data[8:7], n_data[6:0], img_r, cls_r);
            state <= S_LOAD;
        end
        S_LOAD: begin
            case (ph)
                2'd0:    begin oled_dc <= 1'b0; tx_byte <= init_byte(idx[3:0]); end
                2'd1:    begin
                    if (idx < 10'd6) begin oled_dc <= 1'b0; tx_byte <= frame_cmd(idx[2:0]); end
                    else             begin oled_dc <= 1'b1; tx_byte <= data_r; end
                end
                default: begin oled_dc <= 1'b0; tx_byte <= 8'hAF; end       // display on
            endcase
            tx_go <= 1'b1; state <= S_W1;
        end
        S_W1: begin tx_go <= 1'b0; state <= S_W2; end
        S_W2: if (!tx_busy) begin
            if (idx == last) state <= S_DONE;
            else begin idx <= idx + 1'b1; state <= S_PREP; end
        end
        S_DONE: begin
            if (ph == 2'd0) begin ph <= 2'd1; idx <= 0; state <= S_PREP; end                // first picture
            else if (ph == 2'd1) begin
                if (!powered) begin oled_vbat <= VBAT_ON; tmr <= 0; state <= S_VBAT; end
                else state <= S_IDLE;
            end else begin powered <= 1'b1; state <= S_IDLE; end
        end
        S_VBAT: begin
            if (tmr == T_VBAT - 1) begin tmr <= 0; ph <= 2'd2; idx <= 0; state <= S_PREP; end else tmr <= tmr + 1;
        end
        S_IDLE: if (pending) begin
            pending <= 1'b0; img_r <= img_n; cls_r <= cls_n; ph <= 2'd1; idx <= 0; state <= S_PREP;
        end
        default: state <= S_VDD;
        endcase
        if (upd) begin img_n <= img; cls_n <= cls; pending <= 1'b1; end
    end
endmodule