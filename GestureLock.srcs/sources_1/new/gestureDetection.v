// gestureDetection: top level for ZedBoard.
// Pmod JSTK2 (JA1..JA4) -> SPI -> stroke detector -> rasteriser (16x16 image) -> single-layer classifier -> LEDs.
//
// LEDs:  LD0       on while a stroke is being drawn
//        LD1       toggles each time a stroke has been classified
//        LD2       toggles each time a stroke was rejected (too short / too small / too long)
//        LD3       heartbeat, toggles about once a second while the joystick is being read
//        LD7..LD4  class of the last stroke, as a binary number (LD7 = most significant bit):
//                  0 circle, 1 down, 2 hline, 3 left, 4 right, 5 up, 6 vline   (order of linear_params.txt)
// OLED:  the 16x16 image the classifier saw (enlarged 2x, left) and the class name (right); shows DRAW at start-up.
module gestureDetection #(
    parameter CLK_HZ    = 100_000_000,
    parameter SAMPLE_HZ = 100,
    parameter OLED_SIM_FAST = 0        // 1 only in simulation: shortens the OLED power-up delays
)(
    input  wire       clk100,      // 100 MHz board oscillator (Y9)
    input  wire       btnc,        // centre button = reset (P16)
    output wire       ja_cs_n,     // JA1
    output wire       ja_mosi,     // JA2
    input  wire       ja_miso,     // JA3
    output wire       ja_sck,      // JA4
    output wire [7:0] led,
    // on-board OLED (SSD1306)
    output wire       oled_sclk,
    output wire       oled_sdin,
    output wire       oled_dc,
    output wire       oled_res,
    output wire       oled_vbat,
    output wire       oled_vdd
);
    // ---- joystick ----
    wire [9:0] x, y;
    wire [2:0] btn;
    wire       sample_valid;

    jstk2_spi #(.CLK_HZ(CLK_HZ), .SCK_HZ(500_000), .SAMPLE_HZ(SAMPLE_HZ)) u_spi (
        .clk(clk100), .rst(btnc),
        .cs_n(ja_cs_n), .sck(ja_sck), .mosi(ja_mosi), .miso(ja_miso),
        .x(x), .y(y), .btn(btn), .valid(sample_valid));

    // ---- stroke detection ----
    wire        active, stroke_done, stroke_reject;
    wire [10:0] stroke_len;
    wire [9:0]  rd_addr;
    wire [19:0] rd_data;

    stroke_detect #(.CX(528), .CY(518), .DWELL(40)) u_det (
        .clk(clk100), .rst(btnc),
        .sample_valid(sample_valid), .x(x), .y(y),
        .active(active), .stroke_done(stroke_done), .stroke_reject(stroke_reject),
        .stroke_len(stroke_len),
        .rd_addr(rd_addr), .rd_data(rd_data));

    // ---- stroke -> 16x16 image ----
    wire         img_valid;
    wire [255:0] img;

    stroke_raster #(.CX(528), .CY(518)) u_ras (
        .clk(clk100), .rst(btnc),
        .start(stroke_done), .len(stroke_len),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .busy(), .img_valid(img_valid), .img(img));

    // ---- image -> class ----
    wire       cls_done;
    wire [3:0] class_idx;

    linear_classifier #(.NUM_CLASSES(7)) u_cls (
        .clk(clk100), .rst(btnc),
        .start(img_valid), .img(img),
        .busy(), .done(cls_done), .class_idx(class_idx), .scores_flat());

    // ---- OLED: picture and class name, updated every time a stroke has been classified ----
    oled_ctrl #(.CLK_HZ(CLK_HZ), .SIM_FAST(OLED_SIM_FAST)) u_oled (
        .clk(clk100), .upd(cls_done), .img(img), .cls(class_idx),
        .oled_sclk(oled_sclk), .oled_sdin(oled_sdin), .oled_dc(oled_dc),
        .oled_res(oled_res), .oled_vbat(oled_vbat), .oled_vdd(oled_vdd));

    // ---- debug LEDs ----
    reg       done_t, rej_t, beat;
    reg [6:0] beat_cnt;
    always @(posedge clk100) begin
        if (btnc) begin done_t <= 0; rej_t <= 0; beat <= 0; beat_cnt <= 0; end
        else begin
            if (cls_done)      done_t <= ~done_t;
            if (stroke_reject) rej_t  <= ~rej_t;
            if (sample_valid) begin
                if (beat_cnt == 49) begin beat_cnt <= 0; beat <= ~beat; end   // about 1 Hz at 100 samples/s
                else beat_cnt <= beat_cnt + 1;
            end
        end
    end
    assign led = {class_idx, beat, rej_t, done_t, active};
endmodule