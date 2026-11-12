`timescale 1ns / 1ps

module gestureDetection #(
    parameter CLK_HZ        = 100_000_000,
    parameter SAMPLE_HZ     = 100,
    parameter OLED_SIM_FAST = 0
)(
    input  wire       clk100,     // 100 MHz board oscillator (Y9)
    input  wire       btnc,       // Centre button reset (P16)
    output wire       ja_cs_n,    // Pmod JA SPI CS (Y11)
    output wire       ja_mosi,    // Pmod JA SPI MOSI (AA11)
    input  wire       ja_miso,    // Pmod JA SPI MISO (Y10)
    output wire       ja_sck,     // Pmod JA SPI SCK (AA9)
    output wire [7:0] led,        // Board status LEDs
    // On-board SSD1306 OLED
    output wire       oled_sclk,
    output wire       oled_sdin,
    output wire       oled_dc,
    output wire       oled_res,
    output wire       oled_vbat,
    output wire       oled_vdd
);
    // ------------------------------------------------------------------------
    // 1. Pmod JSTK2 Joystick SPI Interface
    // ------------------------------------------------------------------------
    wire [9:0] x, y;
    wire [2:0] btn;
    wire       sample_valid;

    jstk2_spi #(
        .CLK_HZ(CLK_HZ),
        .SCK_HZ(500_000),
        .SAMPLE_HZ(SAMPLE_HZ)
    ) u_spi (
        .clk(clk100),
        .rst(btnc),
        .cs_n(ja_cs_n),
        .sck(ja_sck),
        .mosi(ja_mosi),
        .miso(ja_miso),
        .x(x),
        .y(y),
        .btn(btn),
        .valid(sample_valid)
    );

    // ------------------------------------------------------------------------
    // 2. Stroke Detector & Sample Buffer
    // ------------------------------------------------------------------------
    wire        active, stroke_done, stroke_reject;
    wire [10:0] stroke_len;
    wire [9:0]  rd_addr;
    wire [19:0] rd_data;

    stroke_detect #(
        .CX(528),
        .CY(518),
        .DWELL(40)
    ) u_det (
        .clk(clk100),
        .rst(btnc),
        .sample_valid(sample_valid),
        .x(x),
        .y(y),
        .active(active),
        .stroke_done(stroke_done),
        .stroke_reject(stroke_reject),
        .stroke_len(stroke_len),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    // ------------------------------------------------------------------------
    // 3. Grid Rasterizer (Stroke -> 16x16 Binary Image)
    // ------------------------------------------------------------------------
    wire         img_valid;
    wire [255:0] img;

    stroke_raster #(
        .CX(528),
        .CY(518)
    ) u_ras (
        .clk(clk100),
        .rst(btnc),
        .start(stroke_done),
        .len(stroke_len),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .busy(),
        .img_valid(img_valid),
        .img(img)
    );

    // ------------------------------------------------------------------------
    // 4. Gesture Classifier Engine
    // ------------------------------------------------------------------------
    wire       cls_done;
    wire [3:0] class_idx;

    linear_classifier #(
        .NUM_CLASSES(7)
    ) u_cls (
        .clk(clk100),
        .rst(btnc),
        .start(img_valid),
        .img(img),
        .busy(),
        .done(cls_done),
        .class_idx(class_idx),
        .scores_flat()
    );

    // ------------------------------------------------------------------------
    // 5. Master Gesture Lock FSM
    // ------------------------------------------------------------------------
    wire [1:0]   display_mode;
    wire         filled0, filled1, filled2, filled3;
    wire [255:0] img0, img1, img2, img3;
    wire [3:0]   cls0, cls1, cls2, cls3;
    wire         unlocked;

    gesture_lock_fsm #(
        .CLK_HZ(CLK_HZ)
    ) u_lock_fsm (
        .clk(clk100),
        .rst(btnc),
        .cls_done(cls_done),
        .class_idx(class_idx),
        .img_in(img),
        .btn(btn),
        .display_mode(display_mode),
        .filled0(filled0), .filled1(filled1), .filled2(filled2), .filled3(filled3),
        .img0(img0), .img1(img1), .img2(img2), .img3(img3),
        .cls0(cls0), .cls1(cls1), .cls2(cls2), .cls3(cls3),
        .unlocked(unlocked)
    );

    // ------------------------------------------------------------------------
    // 6. OLED 4-Box & Status Display Driver
    // ------------------------------------------------------------------------
    oled_box_renderer #(
        .CLK_HZ(CLK_HZ),
        .SIM_FAST(OLED_SIM_FAST)
    ) u_oled (
        .clk(clk100),
        .rst(btnc),
        .display_mode(display_mode),
        .filled0(filled0), .filled1(filled1), .filled2(filled2), .filled3(filled3),
        .img0(img0), .img1(img1), .img2(img2), .img3(img3),
        .cls0(cls0), .cls1(cls1), .cls2(cls2), .cls3(cls3),
        .upd(cls_done),
        .oled_sclk(oled_sclk),
        .oled_sdin(oled_sdin),
        .oled_dc(oled_dc),
        .oled_res(oled_res),
        .oled_vbat(oled_vbat),
        .oled_vdd(oled_vdd)
    );

    // ------------------------------------------------------------------------
    // 7. Status LEDs
    // ------------------------------------------------------------------------
    reg done_t, rej_t;
    always @(posedge clk100) begin
        if (btnc) begin
            done_t <= 0;
            rej_t  <= 0;
        end else begin
            if (cls_done)      done_t <= ~done_t;
            if (stroke_reject) rej_t  <= ~rej_t;
        end
    end

    assign led = {unlocked, display_mode, class_idx[2:0], rej_t, active};

endmodule