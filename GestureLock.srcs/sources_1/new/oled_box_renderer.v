`timescale 1ns / 1ps

// oled_box_renderer.v: Displays 4 shape boxes or 3x-scaled status banners ("LOCKED", "UNLOCKED", "WRONG!")
module oled_box_renderer #(
    parameter CLK_HZ   = 100_000_000,
    parameter SCK_HZ   = 5_000_000,
    parameter SIM_FAST = 0
)(
    input  wire         clk,
    input  wire         rst,
    input  wire  [1:0]  display_mode, // 0: 4 BOXES, 1: LOCKED, 2: UNLOCKED, 3: WRONG!
    input  wire         filled0, filled1, filled2, filled3,
    input  wire  [255:0] img0, img1, img2, img3,
    input  wire  [3:0]  cls0, cls1, cls2, cls3,
    input  wire         upd,          // Redraw trigger pulse
    output reg          oled_sclk,
    output reg          oled_sdin,
    output reg          oled_dc,
    output reg          oled_res,
    output reg          oled_vbat,
    output reg          oled_vdd
);
    localparam HALF = CLK_HZ / (2 * SCK_HZ);
    localparam US   = CLK_HZ / 1_000_000;
    localparam MS   = SIM_FAST ? US : CLK_HZ / 1000;

    localparam T_VDD  = 20  * MS;
    localparam T_RES  = 1   * MS;
    localparam T_VBAT = 100 * MS;

    // ------------------------------------------------------------------------
    // 5x7 Font Generator (Same glyph definitions as oled_display_wrapper)
    // ------------------------------------------------------------------------
    function [7:0] get_font_char;
        input [7:0] ascii_char;
        input [2:0] c_idx;
        begin
            if (c_idx > 3'd4) begin
                get_font_char = 8'h00;
            end else begin
                case (ascii_char)
                    "L": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h40; 3'd2: get_font_char = 8'h40; 3'd3: get_font_char = 8'h40; default: get_font_char = 8'h40; endcase
                    "O": case(c_idx) 3'd0: get_font_char = 8'h3E; 3'd1: get_font_char = 8'h41; 3'd2: get_font_char = 8'h41; 3'd3: get_font_char = 8'h41; default: get_font_char = 8'h3E; endcase
                    "C": case(c_idx) 3'd0: get_font_char = 8'h3E; 3'd1: get_font_char = 8'h41; 3'd2: get_font_char = 8'h41; 3'd3: get_font_char = 8'h41; default: get_font_char = 8'h22; endcase
                    "K": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h08; 3'd2: get_font_char = 8'h14; 3'd3: get_font_char = 8'h22; default: get_font_char = 8'h41; endcase
                    "E": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h49; 3'd2: get_font_char = 8'h49; 3'd3: get_font_char = 8'h49; default: get_font_char = 8'h41; endcase
                    "D": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h41; 3'd2: get_font_char = 8'h41; 3'd3: get_font_char = 8'h22; default: get_font_char = 8'h1C; endcase
                    "U": case(c_idx) 3'd0: get_font_char = 8'h3F; 3'd1: get_font_char = 8'h40; 3'd2: get_font_char = 8'h40; 3'd3: get_font_char = 8'h40; default: get_font_char = 8'h3F; endcase
                    "N": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h04; 3'd2: get_font_char = 8'h08; 3'd3: get_font_char = 8'h10; default: get_font_char = 8'h7F; endcase
                    "W": case(c_idx) 3'd0: get_font_char = 8'h3F; 3'd1: get_font_char = 8'h40; 3'd2: get_font_char = 8'h38; 3'd3: get_font_char = 8'h40; default: get_font_char = 8'h3F; endcase
                    "R": case(c_idx) 3'd0: get_font_char = 8'h7F; 3'd1: get_font_char = 8'h09; 3'd2: get_font_char = 8'h19; 3'd3: get_font_char = 8'h29; default: get_font_char = 8'h46; endcase
                    "G": case(c_idx) 3'd0: get_font_char = 8'h3E; 3'd1: get_font_char = 8'h41; 3'd2: get_font_char = 8'h49; 3'd3: get_font_char = 8'h49; default: get_font_char = 8'h7A; endcase
                    "!": case(c_idx) 3'd0: get_font_char = 8'h00; 3'd1: get_font_char = 8'h00; 3'd2: get_font_char = 8'h5F; 3'd3: get_font_char = 8'h00; default: get_font_char = 8'h00; endcase
                    default: get_font_char = 8'h00;
                endcase
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // 3x Scaled Banner Pixel Generator (15x21 px per char, 16 px pitch)
    // ------------------------------------------------------------------------
    function get_banner_pixel;
        input [1:0] mode;
        input [5:0] row;
        input [6:0] col;
        reg [6:0] col_off;
        reg [2:0] char_idx;
        reg [3:0] sub_col;
        reg [2:0] c_idx;
        reg [2:0] r_bit;
        reg [7:0] font_col;
        begin
            get_banner_pixel = 1'b0;
            // Vertically centered: rows 5..25 (21 pixels tall = 7 rows x 3)
            if (row >= 5 && row <= 25) begin
                case (row)
                    6'd5,  6'd6,  6'd7:  r_bit = 3'd0;
                    6'd8,  6'd9,  6'd10: r_bit = 3'd1;
                    6'd11, 6'd12, 6'd13: r_bit = 3'd2;
                    6'd14, 6'd15, 6'd16: r_bit = 3'd3;
                    6'd17, 6'd18, 6'd19: r_bit = 3'd4;
                    6'd20, 6'd21, 6'd22: r_bit = 3'd5;
                    default:             r_bit = 3'd6;
                endcase

                font_col = 8'h00;
                col_off  = 7'd0;
                char_idx = 3'd0;
                sub_col  = 4'd15;
                c_idx    = 3'd5;

                if (mode == 2'd1) begin // "LOCKED" (6 chars x 16 px = 96 px, cols 16..111)
                    if (col >= 16 && col < 112) begin
                        col_off  = col - 7'd16;
                        char_idx = col_off[6:4];
                        sub_col  = col_off[3:0];
                        case (sub_col)
                            4'd0,  4'd1,  4'd2:  c_idx = 3'd0;
                            4'd3,  4'd4,  4'd5:  c_idx = 3'd1;
                            4'd6,  4'd7,  4'd8:  c_idx = 3'd2;
                            4'd9,  4'd10, 4'd11: c_idx = 3'd3;
                            4'd12, 4'd13, 4'd14: c_idx = 3'd4;
                            default:             c_idx = 3'd5;
                        endcase
                        case (char_idx)
                            3'd0: font_col = get_font_char("L", c_idx);
                            3'd1: font_col = get_font_char("O", c_idx);
                            3'd2: font_col = get_font_char("C", c_idx);
                            3'd3: font_col = get_font_char("K", c_idx);
                            3'd4: font_col = get_font_char("E", c_idx);
                            3'd5: font_col = get_font_char("D", c_idx);
                            default: font_col = 8'h00;
                        endcase
                    end
                end else if (mode == 2'd2) begin // "UNLOCKED" (8 chars x 16 px = 128 px, cols 0..127)
                    col_off  = col;
                    char_idx = col_off[6:4];
                    sub_col  = col_off[3:0];
                    case (sub_col)
                        4'd0,  4'd1,  4'd2:  c_idx = 3'd0;
                        4'd3,  4'd4,  4'd5:  c_idx = 3'd1;
                        4'd6,  4'd7,  4'd8:  c_idx = 3'd2;
                        4'd9,  4'd10, 4'd11: c_idx = 3'd3;
                        4'd12, 4'd13, 4'd14: c_idx = 3'd4;
                        default:             c_idx = 3'd5;
                    endcase
                    case (char_idx)
                        3'd0: font_col = get_font_char("U", c_idx);
                        3'd1: font_col = get_font_char("N", c_idx);
                        3'd2: font_col = get_font_char("L", c_idx);
                        3'd3: font_col = get_font_char("O", c_idx);
                        3'd4: font_col = get_font_char("C", c_idx);
                        3'd5: font_col = get_font_char("K", c_idx);
                        3'd6: font_col = get_font_char("E", c_idx);
                        3'd7: font_col = get_font_char("D", c_idx);
                        default: font_col = 8'h00;
                    endcase
                end else if (mode == 2'd3) begin // "WRONG!" (6 chars x 16 px = 96 px, cols 16..111)
                    if (col >= 16 && col < 112) begin
                        col_off  = col - 7'd16;
                        char_idx = col_off[6:4];
                        sub_col  = col_off[3:0];
                        case (sub_col)
                            4'd0,  4'd1,  4'd2:  c_idx = 3'd0;
                            4'd3,  4'd4,  4'd5:  c_idx = 3'd1;
                            4'd6,  4'd7,  4'd8:  c_idx = 3'd2;
                            4'd9,  4'd10, 4'd11: c_idx = 3'd3;
                            4'd12, 4'd13, 4'd14: c_idx = 3'd4;
                            default:             c_idx = 3'd5;
                        endcase
                        case (char_idx)
                            3'd0: font_col = get_font_char("W", c_idx);
                            3'd1: font_col = get_font_char("R", c_idx);
                            3'd2: font_col = get_font_char("O", c_idx);
                            3'd3: font_col = get_font_char("N", c_idx);
                            3'd4: font_col = get_font_char("G", c_idx);
                            3'd5: font_col = get_font_char("!", c_idx);
                            default: font_col = 8'h00;
                        endcase
                    end
                end
                get_banner_pixel = font_col[r_bit];
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Frame Byte Generator (4 Symmetrical Boxes + Software 180° Rotation)
    // ------------------------------------------------------------------------
    function [7:0] gen_byte;
        input [1:0]   page;
        input [6:0]   col;
        input [1:0]   mode;
        input [0:0]   f0, f1, f2, f3;
        input [255:0] i0, i1, i2, i3;
        input [3:0]   c0, c1, c2, c3;
        integer b;
        reg [7:0] v;
        reg [5:0] row, vrow;
        reg [6:0] vcol;
        reg       is_box, is_border, is_img_area, is_filled;
        reg [3:0] img_r, img_c;
        reg [7:0] bit_idx;
        reg [255:0] cur_img;
        begin
            v = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                row  = {page, 3'b000} + b;
                vrow = 6'd31 - row;  // 180 degree software rotation
                vcol = 7'd127 - col; // 180 degree software rotation

                if (mode != 2'd0) begin
                    v[b] = get_banner_pixel(mode, vrow, vcol);
                end else begin
                    is_box = 1'b0; is_border = 1'b0; is_img_area = 1'b0; is_filled = 1'b0;
                    cur_img = 256'd0; img_r = 0; img_c = 0;

                    // Box 0: cols 4..27 | Box 1: cols 36..59 | Box 2: cols 68..91 | Box 3: cols 100..123
                    if (vrow >= 4 && vrow <= 27) begin
                        if (vcol >= 4 && vcol <= 27) begin
                            is_box = 1'b1;
                            is_border = (vrow == 4 || vrow == 27 || vcol == 4 || vcol == 27);
                            is_img_area = (vrow >= 8 && vrow <= 23 && vcol >= 8 && vcol <= 23);
                            is_filled = f0; cur_img = i0;
                            img_r = vrow[3:0] - 4'd8; img_c = vcol[3:0] - 4'd8;
                        end else if (vcol >= 36 && vcol <= 59) begin
                            is_box = 1'b1;
                            is_border = (vrow == 4 || vrow == 27 || vcol == 36 || vcol == 59);
                            is_img_area = (vrow >= 8 && vrow <= 23 && vcol >= 40 && vcol <= 55);
                            is_filled = f1; cur_img = i1;
                            img_r = vrow[3:0] - 4'd8; img_c = vcol[5:0] - 6'd40;
                        end else if (vcol >= 68 && vcol <= 91) begin
                            is_box = 1'b1;
                            is_border = (vrow == 4 || vrow == 27 || vcol == 68 || vcol == 91);
                            is_img_area = (vrow >= 8 && vrow <= 23 && vcol >= 72 && vcol <= 87);
                            is_filled = f2; cur_img = i2;
                            img_r = vrow[3:0] - 4'd8; img_c = vcol[6:0] - 7'd72;
                        end else if (vcol >= 100 && vcol <= 123) begin
                            is_box = 1'b1;
                            is_border = (vrow == 4 || vrow == 27 || vcol == 100 || vcol == 123);
                            is_img_area = (vrow >= 8 && vrow <= 23 && vcol >= 104 && vcol <= 119);
                            is_filled = f3; cur_img = i3;
                            img_r = vrow[3:0] - 4'd8; img_c = vcol[6:0] - 7'd104;
                        end
                    end

                    if (is_box) begin
                        if (is_border) begin
                            v[b] = 1'b1;
                        end else if (is_filled && is_img_area) begin
                            bit_idx = {img_r, img_c};
                            v[b] = cur_img[bit_idx];
                        end
                    end
                end
            end
            gen_byte = v;
        end
    endfunction

    // ------------------------------------------------------------------------
    // SSD1306 SPI Hardware Driver Engine
    // ------------------------------------------------------------------------
    function [7:0] init_byte;
        input [3:0] i;
        begin
            case (i)
                4'd0: init_byte = 8'hAE;
                4'd1: init_byte = 8'h8D;
                4'd2: init_byte = 8'h14;
                4'd3: init_byte = 8'hD9;
                4'd4: init_byte = 8'hF1;
                4'd5: init_byte = 8'h20;
                4'd6: init_byte = 8'h00;
                4'd7: init_byte = 8'hA1;
                4'd8: init_byte = 8'hC8;
                4'd9: init_byte = 8'hDA;
                default: init_byte = 8'h20;
            endcase
        end
    endfunction

    function [7:0] frame_cmd;
        input [2:0] i;
        begin
            case (i)
                3'd0: frame_cmd = 8'h21; 3'd1: frame_cmd = 8'h00; 3'd2: frame_cmd = 8'h7F;
                3'd3: frame_cmd = 8'h22; 3'd4: frame_cmd = 8'h00; default: frame_cmd = 8'h03;
            endcase
        end
    endfunction

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
                if (!oled_sclk) oled_sclk <= 1'b1;
                else begin
                    oled_sclk <= 1'b0;
                    if (bitn == 4'd7) tx_busy <= 1'b0;
                    else begin bitn <= bitn + 1'b1; sh <= {sh[6:0], 1'b0}; oled_sdin <= sh[6]; end
                end
            end else ck <= ck + 1'b1;
        end
    end

    localparam S_VDD = 4'd0, S_RESL = 4'd1, S_RESH = 4'd2, S_PREP = 4'd3, S_LOAD = 4'd4,
               S_W1  = 4'd5, S_W2   = 4'd6, S_DONE = 4'd7, S_VBAT = 4'd8, S_IDLE = 4'd9;

    reg [3:0]   state;
    reg [1:0]   ph;
    reg [9:0]   idx;
    reg [31:0]  tmr;
    reg [7:0]   data_r;
    reg         powered, pending;
    wire [9:0]  n_data = idx - 10'd6;
    wire [9:0]  last = (ph == 2'd0) ? 10'd10 : (ph == 2'd1) ? 10'd517 : 10'd0;

    // Redraw detector registers
    reg [1:0] prev_display_mode;
    reg       prev_filled0, prev_filled1, prev_filled2, prev_filled3;

    initial begin
        oled_sclk = 0; oled_sdin = 0; oled_dc = 0; oled_res = 0;
        oled_vdd = 1'b1; oled_vbat = 1'b1;
        tx_go = 0; tx_busy = 0; state = S_VDD; ph = 0; idx = 0; tmr = 0; data_r = 0;
        powered = 0; pending = 0;
        prev_display_mode = 2'd1;
        prev_filled0 = 0; prev_filled1 = 0; prev_filled2 = 0; prev_filled3 = 0;
    end

    always @(posedge clk) begin
        case (state)
            S_VDD: begin
                oled_vdd <= 1'b0;
                if (tmr == T_VDD - 1) begin tmr <= 0; state <= S_RESL; end else tmr <= tmr + 1;
            end
            S_RESL: begin
                if (tmr == T_RES - 1) begin tmr <= 0; oled_res <= 1'b1; state <= S_RESH; end else tmr <= tmr + 1;
            end
            S_RESH: begin
                if (tmr == T_RES - 1) begin tmr <= 0; ph <= 0; idx <= 0; state <= S_PREP; end else tmr <= tmr + 1;
            end
            S_PREP: begin
                if (ph == 2'd1 && idx >= 10'd6)
                    data_r <= gen_byte(n_data[8:7], n_data[6:0], display_mode, filled0, filled1, filled2, filled3,
                                       img0, img1, img2, img3, cls0, cls1, cls2, cls3);
                state <= S_LOAD;
            end
            S_LOAD: begin
                case (ph)
                    2'd0:    begin oled_dc <= 1'b0; tx_byte <= init_byte(idx[3:0]); end
                    2'd1:    begin
                        if (idx < 10'd6) begin oled_dc <= 1'b0; tx_byte <= frame_cmd(idx[2:0]); end
                        else             begin oled_dc <= 1'b1; tx_byte <= data_r; end
                    end
                    default: begin oled_dc <= 1'b0; tx_byte <= 8'hAF; end
                endcase
                tx_go <= 1'b1; state <= S_W1;
            end
            S_W1: begin tx_go <= 1'b0; state <= S_W2; end
            S_W2: if (!tx_busy) begin
                if (idx == last) state <= S_DONE;
                else begin idx <= idx + 1'b1; state <= S_PREP; end
            end
            S_DONE: begin
                if (ph == 2'd0) begin ph <= 2'd1; idx <= 0; state <= S_PREP; end
                else if (ph == 2'd1) begin
                    if (!powered) begin oled_vbat <= 1'b0; tmr <= 0; state <= S_VBAT; end
                    else state <= S_IDLE;
                end else begin powered <= 1'b1; state <= S_IDLE; end
            end
            S_VBAT: begin
                if (tmr == T_VBAT - 1) begin tmr <= 0; ph <= 2'd2; idx <= 0; state <= S_PREP; end else tmr <= tmr + 1;
            end
            S_IDLE: if (pending) begin
                pending <= 1'b0; ph <= 2'd1; idx <= 0; state <= S_PREP;
            end
            default: state <= S_VDD;
        endcase

        // Trigger screen redraw on upd pulse, reset, mode changes, or new box additions
        if (upd || rst || 
            (display_mode != prev_display_mode) || 
            (filled0 != prev_filled0) || 
            (filled1 != prev_filled1) || 
            (filled2 != prev_filled2) || 
            (filled3 != prev_filled3)) begin
            pending <= 1'b1;
        end

        prev_display_mode <= display_mode;
        prev_filled0 <= filled0;
        prev_filled1 <= filled1;
        prev_filled2 <= filled2;
        prev_filled3 <= filled3;
    end
endmodule