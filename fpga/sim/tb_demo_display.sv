`timescale 1ns/1ps
module tb_demo_display;
    reg clk=0, reset=1, heartbeat=0, batch_begin=0, board_complete=0, batch_end=0;
    reg error_active=0, overflow_active=0;
    reg [15:0] processed=1000, solved=862, expected=1000;
    reg [63:0] cycles=64'd81110615;
    reg signed [31:0] score=32'sd9038487;
    wire [511:0] segments; wire overflow;
    wire [63:0] leds; wire active, done;
    always #5 clk=~clk;

    minesweeper_display_formatter fmt(
        .clk(clk),.reset(reset),.boards_processed(processed),
        .boards_fully_solved(solved),.total_cycles(cycles),
        .total_score_scaled(score),.batch_active(active),.batch_done(done),
        .display_error(error_active),.segments(segments),.overflow(overflow));
    minesweeper_demo_leds #(.CLOCK_HZ(100)) led(
        .clk(clk),.reset(reset),.heartbeat(heartbeat),.batch_begin(batch_begin),
        .expected_boards(expected),.board_complete(board_complete),
        .batch_end(batch_end),.error_active(error_active),.overflow_active(overflow_active),
        .led_bitmap(leds),.batch_active(active),.batch_done(done),
        .debug_state(),.debug_completed_count(),.debug_expected_boards());

    task pulse_begin; begin @(negedge clk); batch_begin=1; @(negedge clk); batch_begin=0; end endtask
    task pulse_board; begin @(negedge clk); board_complete=1; @(negedge clk); board_complete=0; end endtask
    task expect_glyph(input integer pos,input [7:0] value);
        begin if(segments[pos*8+:8]!==value) begin $display("FAIL pos=%0d",pos); $fatal; end end
    endtask

    initial begin
        repeat(3) @(negedge clk); reset=0;
        // WAIT: heartbeat is the only active pattern.
        heartbeat=1; #1;
        if(leds!==64'h0000018001800000) $fatal(1,"WAIT heartbeat pattern incorrect");
        heartbeat=0;

        // RUN: two boards produce 32 and then 64 progress steps.
        expected=2; pulse_begin();
        if(!active||done) $fatal(1,"BATCH_BEGIN did not enter RUN");
        pulse_board(); repeat(40) @(negedge clk);
        if(led.lit_count!==32) $fatal(1,"half progress was not 32 LEDs");

        // ERROR interrupts RUN and remains latched after the input clears.
        error_active=1; repeat(2) @(negedge clk); error_active=0;
        if(active||done) $fatal(1,"ERROR state flags incorrect");
        if(leds!==64'hAAAA5555AAAA5555&&leds!==64'h5555AAAA5555AAAA)
            $fatal(1,"checkerboard error pattern incorrect");
        repeat(20) @(negedge clk);
        if(leds!==64'hAAAA5555AAAA5555&&leds!==64'h5555AAAA5555AAAA)
            $fatal(1,"ERROR was not latched");

        // A clean new batch recovers. Final result enters FINISH directly.
        expected=1; pulse_begin(); pulse_board(); repeat(2) @(negedge clk);
        if(!done||active) $fatal(1,"final board did not enter FINISH");
        repeat(230) @(negedge clk);
        if(led.state!==3) $fatal(1,"finish animation did not enter FINISHED hold");

        // Formatter commits the visible FIn label.
        repeat(400) @(negedge clk);
        expect_glyph(11,8'h8E); expect_glyph(12,8'h60); expect_glyph(13,8'h2A);
        $display("DEMO FSM TEST PASSED");
        $finish;
    end
endmodule
