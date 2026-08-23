`timescale 1ns/1ps

// Instrumented solver system with the complete MU500-7SEG output path.
// The cfg/load/start ports form a board-source-neutral stream: a simulation
// testbench, UART receiver, SD controller, or ROM loader can drive the same API.
module minesweeper_mu500_system #(
    parameter DETERMINISTIC_SOLVER = 0,
    parameter MAX_PROBABILITY_GUESSES = 4,
    parameter ENABLE_ADAPTIVE_FEEDBACK = 0,
    parameter ENABLE_SATURATING_HALF_SAFE_FEEDBACK = 0,
    parameter BASE_PROBABILITY_GUESSES = 8,
    parameter ADAPTIVE_FEEDBACK_SAFE_THRESHOLD = 32,
    parameter ENABLE_GLOBAL_CONDITIONING = 0,
    parameter ENABLE_LOW_SCORE_EDGE_RESCUE = 0,
    parameter LOW_SCORE_RESCUE_SAFE_THRESHOLD = 16
) (
    input  wire       clk,
    input  wire       reset,
    input  wire [3:0] speed_setting,

    input  wire       cfg_valid,
    output wire       cfg_ready,
    input  wire [4:0] cfg_width,
    input  wire [4:0] cfg_height,
    input  wire [8:0] cfg_total_mines,
    input  wire       load_valid,
    output wire       load_ready,
    input  wire [8:0] load_index,
    input  wire [3:0] load_value,
    input  wire       start_solver,

    output wire       solver_busy,
    output wire       solver_done,
    output wire       solver_stalled,
    output wire       result_valid,
    output wire       protocol_error,
    output wire [15:0] boards_processed,
    output wire [15:0] boards_fully_solved,
    output wire signed [31:0] current_score_scaled,
    output wire signed [31:0] total_score_scaled,
    output wire [8:0] current_safe,
    output wire [8:0] current_mines,
    output wire [8:0] current_selections,
    output wire [31:0] current_cycles,
    output wire [63:0] total_cycles,

    output wire [7:0] SEG_A,
    output wire [7:0] SEG_B,
    output wire [7:0] SEG_C,
    output wire [7:0] SEG_D,
    output wire [7:0] SEG_E,
    output wire [7:0] SEG_F,
    output wire [7:0] SEG_G,
    output wire [7:0] SEG_H,
    output wire [8:0] SEG_SEL
);
    wire run_enable;
    wire heartbeat;
    wire core_error;
    wire metrics_error;
    wire metrics_busy;
    wire [8:0] selections_issued;
    wire [8:0] opened_safe_count;
    wire [8:0] opened_mine_count;
    wire [8:0] observed_safe_count;
    wire [8:0] observed_mine_count;
    wire [31:0] cycle_count;
    wire [511:0] digit_segments;
    wire display_overflow;
    reg [4:0] active_width;
    reg [4:0] active_height;
    reg [8:0] active_mines;
    reg configured;
    reg loading_seen;
    reg result_seen;
    reg done_toggle;
    wire [3:0] status_code;
    wire [15:0] current_board_number;
    wire current_fully_solved;
    wire [63:0] led_bitmap;

    assign protocol_error = core_error | metrics_error;
    assign current_board_number = boards_processed +
                                  ((solver_busy || metrics_busy) ? 16'd1 : 16'd0);
    assign current_fully_solved =
        (current_safe == (active_width * active_height - active_mines));
    assign status_code = protocol_error ? 4'd9 :
                         solver_busy ? 4'd3 :
                         metrics_busy ? 4'd4 :
                         result_seen ? 4'd5 :
                         configured ? 4'd2 :
                         loading_seen ? 4'd1 : 4'd0;
    assign led_bitmap = {
        48'd0,
        done_toggle, display_overflow, (current_mines != 0), speed_setting,
        solver_stalled, current_fully_solved, run_enable, protocol_error, result_seen,
        solver_busy, loading_seen, configured, heartbeat
    };

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_width <= 5'd0;
            active_height <= 5'd0;
            active_mines <= 9'd0;
            configured <= 1'b0;
            loading_seen <= 1'b0;
            result_seen <= 1'b0;
            done_toggle <= 1'b0;
        end else begin
            if (cfg_valid && cfg_ready) begin
                active_width <= cfg_width;
                active_height <= cfg_height;
                active_mines <= cfg_total_mines;
                configured <= 1'b1;
                loading_seen <= 1'b0;
                result_seen <= 1'b0;
            end
            if (load_valid && load_ready)
                loading_seen <= 1'b1;
            if (start_solver)
                result_seen <= 1'b0;
            if (result_valid) begin
                result_seen <= 1'b1;
                done_toggle <= ~done_toggle;
            end
        end
    end

    solver_speed_control u_speed (
        .clk(clk), .reset(reset), .setting(speed_setting),
        .run_enable(run_enable), .heartbeat(heartbeat)
    );

    generate
        if (DETERMINISTIC_SOLVER) begin : g_deterministic
            wire [8:0] unused_known_mines;
            minesweeper_deterministic_system #(
                .MAX_PROBABILITY_GUESSES(MAX_PROBABILITY_GUESSES),
                .ENABLE_ADAPTIVE_FEEDBACK(ENABLE_ADAPTIVE_FEEDBACK),
                .ENABLE_SATURATING_HALF_SAFE_FEEDBACK(
                    ENABLE_SATURATING_HALF_SAFE_FEEDBACK),
                .BASE_PROBABILITY_GUESSES(BASE_PROBABILITY_GUESSES),
                .ADAPTIVE_FEEDBACK_SAFE_THRESHOLD(
                    ADAPTIVE_FEEDBACK_SAFE_THRESHOLD),
                .ENABLE_LOW_SCORE_EDGE_RESCUE(
                    ENABLE_LOW_SCORE_EDGE_RESCUE),
                .LOW_SCORE_RESCUE_SAFE_THRESHOLD(
                    LOW_SCORE_RESCUE_SAFE_THRESHOLD)
            ) u_core (
                .clk(clk), .reset(reset), .run_enable(run_enable),
                .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
                .cfg_width(cfg_width), .cfg_height(cfg_height),
                .cfg_total_mines(cfg_total_mines),
                .load_valid(load_valid), .load_ready(load_ready),
                .load_index(load_index), .load_value(load_value),
                .start_solver(start_solver),
                .solver_busy(solver_busy), .solver_done(solver_done),
                .solver_stalled(solver_stalled), .protocol_error(core_error),
                .selections_issued(selections_issued),
                .opened_safe_count(opened_safe_count),
                .opened_mine_count(opened_mine_count),
                .observed_safe_count(observed_safe_count),
                .observed_mine_count(observed_mine_count),
                .known_mine_count(unused_known_mines), .cycle_count(cycle_count)
            );
        end else begin : g_four_corners
            wire [2:0] legacy_selections;
            assign selections_issued = {6'd0, legacy_selections};
            assign solver_stalled = 1'b0;
            minesweeper_four_corners_system u_core (
                .clk(clk), .reset(reset), .run_enable(run_enable),
                .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
                .cfg_width(cfg_width), .cfg_height(cfg_height),
                .cfg_total_mines(cfg_total_mines),
                .load_valid(load_valid), .load_ready(load_ready),
                .load_index(load_index), .load_value(load_value),
                .start_solver(start_solver),
                .solver_busy(solver_busy), .solver_done(solver_done),
                .protocol_error(core_error),
                .selections_issued(legacy_selections),
                .opened_safe_count(opened_safe_count),
                .opened_mine_count(opened_mine_count),
                .observed_safe_count(observed_safe_count),
                .observed_mine_count(observed_mine_count),
                .cycle_count(cycle_count)
            );
        end
    endgenerate

    minesweeper_metrics u_metrics (
        .clk(clk), .reset(reset), .board_done(solver_done),
        .board_width(active_width), .board_height(active_height),
        .total_mines(active_mines),
        .opened_safe(opened_safe_count), .opened_mines(opened_mine_count),
        .selections(selections_issued), .board_cycles(cycle_count),
        .busy(metrics_busy), .result_valid(result_valid),
        .protocol_error(metrics_error),
        .boards_processed(boards_processed),
        .boards_fully_solved(boards_fully_solved),
        .current_safe(current_safe), .current_mines(current_mines),
        .current_selections(current_selections),
        .current_cycles(current_cycles), .total_cycles(total_cycles),
        .current_score_scaled(current_score_scaled),
        .total_score_scaled(total_score_scaled)
    );

    minesweeper_display_formatter u_formatter (
        .clk(clk), .reset(reset),
        .boards_processed(boards_processed),
        .boards_fully_solved(boards_fully_solved),
        .current_board_number(current_board_number),
        .selections(current_selections),
        .opened_safe(current_safe), .opened_mines(current_mines),
        .board_width(active_width), .board_height(active_height),
        .total_mines(active_mines), .status_code(status_code),
        .current_cycles(current_cycles), .total_cycles(total_cycles),
        .current_score_scaled(current_score_scaled),
        .total_score_scaled(total_score_scaled),
        .segments(digit_segments), .overflow(display_overflow)
    );

    mu500_7seg_latch_driver u_display (
        .clk(clk), .reset(reset), .digit_segments(digit_segments),
        .led_bitmap(led_bitmap),
        .SEG_A(SEG_A), .SEG_B(SEG_B), .SEG_C(SEG_C), .SEG_D(SEG_D),
        .SEG_E(SEG_E), .SEG_F(SEG_F), .SEG_G(SEG_G), .SEG_H(SEG_H),
        .SEG_SEL(SEG_SEL)
    );
endmodule
