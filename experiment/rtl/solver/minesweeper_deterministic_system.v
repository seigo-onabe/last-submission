`timescale 1ns/1ps

// Experimental integration boundary. The production four-corner system stays
// unchanged until the 9-bit selection result format is propagated through JTAG.
module minesweeper_deterministic_system #(
    parameter MAX_PROBABILITY_GUESSES = 4,
    parameter ENABLE_ADAPTIVE_FEEDBACK = 0,
    parameter ENABLE_SATURATING_HALF_SAFE_FEEDBACK = 0,
    parameter BASE_PROBABILITY_GUESSES = 8,
    parameter ADAPTIVE_FEEDBACK_SAFE_THRESHOLD = 32,
    parameter ENABLE_LOW_SCORE_EDGE_RESCUE = 0,
    parameter LOW_SCORE_RESCUE_SAFE_THRESHOLD = 16
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       run_enable,
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
    output wire       protocol_error,
    output wire [8:0] selections_issued,
    output wire [8:0] opened_safe_count,
    output wire [8:0] opened_mine_count,
    output wire [8:0] observed_safe_count,
    output wire [8:0] observed_mine_count,
    output wire [8:0] known_mine_count,
    output wire [31:0] cycle_count
);
    wire select_valid, select_ready, select_rejected;
    wire [4:0] select_x, select_y;
    wire reveal_valid, reveal_is_mine, cascade_done;
    wire [4:0] reveal_x, reveal_y;
    wire [3:0] reveal_clue;
    wire game_error, solver_error;
    reg [4:0] active_width, active_height;
    reg [8:0] active_mines;

    assign protocol_error = game_error | solver_error;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_width <= 0;
            active_height <= 0;
            active_mines <= 0;
        end else if (cfg_valid && cfg_ready) begin
            active_width <= cfg_width;
            active_height <= cfg_height;
            active_mines <= cfg_total_mines;
        end
    end

    minesweeper_game_core u_game (
        .clk(clk),.reset(reset),.run_enable(run_enable),
        .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_width(cfg_width),.cfg_height(cfg_height),
        .cfg_total_mines(cfg_total_mines),
        .load_valid(load_valid),.load_ready(load_ready),
        .load_index(load_index),.load_value(load_value),
        .select_valid(select_valid),.select_ready(select_ready),
        .select_x(select_x),.select_y(select_y),
        .reveal_valid(reveal_valid),.reveal_x(reveal_x),.reveal_y(reveal_y),
        .reveal_is_mine(reveal_is_mine),.reveal_clue(reveal_clue),
        .cascade_done(cascade_done),.select_rejected(select_rejected),
        .opened_safe_count(opened_safe_count),
        .opened_mine_count(opened_mine_count),.protocol_error(game_error)
    );

    minesweeper_solver_deterministic #(
        .MAX_PROBABILITY_GUESSES(MAX_PROBABILITY_GUESSES),
        .ENABLE_ADAPTIVE_FEEDBACK(ENABLE_ADAPTIVE_FEEDBACK),
        .ENABLE_SATURATING_HALF_SAFE_FEEDBACK(
            ENABLE_SATURATING_HALF_SAFE_FEEDBACK),
        .BASE_PROBABILITY_GUESSES(BASE_PROBABILITY_GUESSES),
        .ADAPTIVE_FEEDBACK_SAFE_THRESHOLD(
            ADAPTIVE_FEEDBACK_SAFE_THRESHOLD),
        .ENABLE_LOW_SCORE_EDGE_RESCUE(ENABLE_LOW_SCORE_EDGE_RESCUE),
        .LOW_SCORE_RESCUE_SAFE_THRESHOLD(LOW_SCORE_RESCUE_SAFE_THRESHOLD)
    ) u_solver (
        .clk(clk),.reset(reset),.run_enable(run_enable),.start(start_solver),
        .board_width(active_width),.board_height(active_height),
        .total_mines(active_mines),.select_valid(select_valid),
        .select_ready(select_ready),.select_x(select_x),.select_y(select_y),
        .select_rejected(select_rejected),.reveal_valid(reveal_valid),
        .reveal_x(reveal_x),.reveal_y(reveal_y),
        .reveal_is_mine(reveal_is_mine),.reveal_clue(reveal_clue),
        .cascade_done(cascade_done),.busy(solver_busy),.done(solver_done),
        .stalled(solver_stalled),.protocol_error(solver_error),
        .selections_issued(selections_issued),
        .observed_safe_count(observed_safe_count),
        .observed_mine_count(observed_mine_count),
        .known_mine_count(known_mine_count),.cycle_count(cycle_count)
    );
endmodule
