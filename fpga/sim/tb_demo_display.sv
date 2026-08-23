`timescale 1ns/1ps
module tb_demo_display;
    reg clk=0, reset=1, batch_begin=0, board_complete=0, batch_end=0;
    reg [15:0] processed=1000, solved=862, expected=1000;
    reg [63:0] cycles=64'd81110615;
    reg signed [31:0] score=32'sd9038487;
    wire [511:0] segments;
    wire overflow;
    wire [63:0] leds;
    wire active, done;
    integer i;
    always #5 clk=~clk;

    minesweeper_display_formatter fmt(
        .clk(clk),.reset(reset),.boards_processed(processed),
        .boards_fully_solved(solved),.total_cycles(cycles),
        .total_score_scaled(score),.batch_active(active),.batch_done(done),
        .display_error(1'b0),.segments(segments),.overflow(overflow));
    minesweeper_demo_leds #(.CLOCK_HZ(100)) led(
        .clk(clk),.reset(reset),.heartbeat(1'b0),.batch_begin(batch_begin),
        .expected_boards(expected),.board_complete(board_complete),
        .batch_end(batch_end),.error_active(1'b0),.overflow_active(overflow),
        .led_bitmap(leds),.batch_active(active),.batch_done(done));

    task pulse_begin; begin @(negedge clk); batch_begin=1; @(negedge clk); batch_begin=0; end endtask
    task pulse_board; begin @(negedge clk); board_complete=1; @(negedge clk); board_complete=0; end endtask
    task pulse_end; begin @(negedge clk); batch_end=1; @(negedge clk); batch_end=0; end endtask
    task expect_glyph(input integer pos,input [7:0] value);
        begin if(segments[pos*8+:8]!==value) begin $display("FAIL pos=%0d got=%02x expected=%02x",pos,segments[pos*8+:8],value); $fatal; end end
    endtask

    initial begin
        repeat(3) @(negedge clk); reset=0;
        pulse_begin();
        repeat(400) @(negedge clk);
        // boArd 1000 run, FULL0862 PArt0138, cycles and score.
        expect_glyph(0,8'h3E); expect_glyph(6,8'h60); expect_glyph(7,8'hFC);
        expect_glyph(11,8'h0A); expect_glyph(12,8'h7C); expect_glyph(13,8'h2A);
        expect_glyph(20,8'hFC); expect_glyph(21,8'hFE); expect_glyph(22,8'hBE); expect_glyph(23,8'hDA);
        expect_glyph(28,8'hFC); expect_glyph(29,8'h60); expect_glyph(30,8'hF2); expect_glyph(31,8'hFE);
        expect_glyph(40,8'hFE); expect_glyph(47,8'hB6);
        expect_glyph(56,8'hFC); expect_glyph(57,8'hF6); expect_glyph(63,8'hE0);
        if(!segments[59*8]) $fatal(1,"score decimal point missing");
        // One-board mode must naturally fill all progress LEDs.
        expected=1; pulse_begin(); pulse_board(); repeat(70) @(negedge clk);
        if(leds!==64'hFFFFFFFFFFFFFFFF) $fatal(1,"one-board progress did not fill");
        pulse_end(); repeat(3) @(negedge clk);
        if(!done||active) $fatal(1,"batch completion state incorrect");
        repeat(400) @(negedge clk);
        expect_glyph(11,8'h7A); expect_glyph(12,8'h3A); expect_glyph(13,8'h2A); expect_glyph(14,8'h9E);
        $display("DEMO DISPLAY TEST PASSED");
        $finish;
    end
endmodule
