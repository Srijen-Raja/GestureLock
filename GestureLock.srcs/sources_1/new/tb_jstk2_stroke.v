`timescale 1ns/1ps
// Self-checking testbench: behavioural JSTK2 slave + spi master + stroke detector.
module tb_jstk2_stroke;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;                         // 100 MHz

    wire cs_n, sck, mosi; reg miso_r = 0;
    wire [9:0] x, y; wire [2:0] btn; wire sv;

    jstk2_spi #(.SAMPLE_HZ(2000)) spi (.clk(clk), .rst(rst), .cs_n(cs_n), .sck(sck), .mosi(mosi),
        .miso(miso_r), .x(x), .y(y), .btn(btn), .valid(sv));

    wire active, done, reject; wire [10:0] len; reg [9:0] ra = 0; wire [19:0] rd;
    stroke_detect #(.DWELL(40)) det (.clk(clk), .rst(rst), .sample_valid(sv), .x(x), .y(y),
        .active(active), .stroke_done(done), .stroke_reject(reject), .stroke_len(len),
        .rd_addr(ra), .rd_data(rd));

    // ---- JSTK2 slave model: mode 0, MSB first, 5 byte reply X_lo X_hi Y_lo Y_hi BTN ----
    reg [9:0] jx = 528, jy = 518;  reg [2:0] jb = 0;
    reg [7:0] reply [0:4];
    integer bytei, biti;
    always @(negedge cs_n) begin
        reply[0] = jx[7:0]; reply[1] = {6'b0, jx[9:8]};
        reply[2] = jy[7:0]; reply[3] = {6'b0, jy[9:8]}; reply[4] = {5'b0, jb};
        bytei = 0; biti = 7; miso_r = reply[0][7];
    end
    always @(negedge sck) if (!cs_n) begin
        if (biti == 0) begin biti = 7; bytei = bytei + 1; end else biti = biti - 1;
        if (bytei < 5) miso_r = reply[bytei][biti];
    end

    // ---- stimulus: position as a function of frame number ----
    integer frame = 0, n_done = 0, n_rej = 0, k, errors = 0;
    real ang;
    always @(negedge cs_n) begin
        frame = frame + 1;
        // 1..20 rest | 21..140 circle (120 samples) | 141..200 rest | 201..210 tap | 211..260 rest
        if (frame >= 21 && frame <= 140) begin
            ang = 6.2831853 * (frame - 21) / 120.0;
            jx = 528 + $rtoi(350.0 * $cos(ang)); jy = 518 + $rtoi(350.0 * $sin(ang));
        end else if (frame >= 201 && frame <= 210) begin
            jx = 528 + 100; jy = 518;                  // small push: too short and too small
        end else begin
            jx = 528 + (frame % 3) - 1; jy = 518 + (frame % 2);   // rest with 1-count noise
        end
    end

    always @(posedge clk) begin
        if (done)   begin n_done = n_done + 1; $display("t=%0t stroke_done len=%0d", $time, len); end
        if (reject) begin n_rej  = n_rej  + 1; $display("t=%0t stroke_reject", $time); end
    end

    // read the accepted stroke back as soon as it is announced (before the next stroke can overwrite it)
    initial begin
        @(posedge done);
        ra = 0;  #30; $display("buffer[0]   x=%0d y=%0d (expect 878,518: start of the circle)", rd[19:10], rd[9:0]);
        if (rd[19:10] !== 878 || rd[9:0] !== 518) begin errors = errors + 1; $display("FAIL: buffer[0]"); end
        ra = 60; #30; $display("buffer[60]  x=%0d y=%0d (expect 178,518: opposite side)", rd[19:10], rd[9:0]);
        if (rd[19:10] !== 178 || rd[9:0] !== 518) begin errors = errors + 1; $display("FAIL: buffer[60]"); end
    end

    initial begin
        #100 rst = 0;
        wait (frame >= 270); #1_000_000;
        if (n_done !== 1) begin errors = errors + 1; $display("FAIL: expected 1 accepted stroke, got %0d", n_done); end
        if (n_rej  !== 1) begin errors = errors + 1; $display("FAIL: expected 1 rejected stroke, got %0d", n_rej); end
        if (len < 118 || len > 122) begin errors = errors + 1; $display("FAIL: stroke length %0d, expected about 120", len); end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
    initial begin #2_000_000_000; $display("TIMEOUT"); $finish; end
endmodule
