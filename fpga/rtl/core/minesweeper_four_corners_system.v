`timescale 1ns/1ps

// Integration of the protected game manager and the four-corner solver.
module minesweeper_four_corners_system (
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
    output wire       protocol_error,
    output wire [2:0] selections_issued,
    output wire [8:0] opened_safe_count,
    output wire [8:0] opened_mine_count,
    output wire [8:0] observed_safe_count,
    output wire [8:0] observed_mine_count,
    output wire [31:0] cycle_count
);

    wire       select_valid;
    wire       select_ready;
    wire [4:0] select_x;
    wire [4:0] select_y;
    wire       select_rejected;
    wire       reveal_valid;
    wire [4:0] reveal_x;
    wire [4:0] reveal_y;
    wire       reveal_is_mine;
    wire [3:0] reveal_clue;
    wire       cascade_done;
    wire       game_error;
    wire       solver_error;
    reg [4:0] active_width;
    reg [4:0] active_height;
    reg [8:0] active_total_mines;

    assign protocol_error = game_error | solver_error;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_width <= 5'd0;
            active_height <= 5'd0;
            active_total_mines <= 9'd0;
        end else if (cfg_valid && cfg_ready) begin
            active_width <= cfg_width;
            active_height <= cfg_height;
            active_total_mines <= cfg_total_mines;
        end
    end

    minesweeper_game_core u_game (
        .clk(clk),
        .reset(reset),
        .run_enable(run_enable),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_total_mines(cfg_total_mines),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_index(load_index),
        .load_value(load_value),
        .select_valid(select_valid),
        .select_ready(select_ready),
        .select_x(select_x),
        .select_y(select_y),
        .reveal_valid(reveal_valid),
        .reveal_x(reveal_x),
        .reveal_y(reveal_y),
        .reveal_is_mine(reveal_is_mine),
        .reveal_clue(reveal_clue),
        .cascade_done(cascade_done),
        .select_rejected(select_rejected),
        .opened_safe_count(opened_safe_count),
        .opened_mine_count(opened_mine_count),
        .protocol_error(game_error)
    );

    minesweeper_solver_four_corners u_solver (
        .clk(clk),
        .reset(reset),
        .run_enable(run_enable),
        .start(start_solver),
        .board_width(active_width),
        .board_height(active_height),
        .total_mines(active_total_mines),
        .select_valid(select_valid),
        .select_ready(select_ready),
        .select_x(select_x),
        .select_y(select_y),
        .select_rejected(select_rejected),
        .reveal_valid(reveal_valid),
        .reveal_x(reveal_x),
        .reveal_y(reveal_y),
        .reveal_is_mine(reveal_is_mine),
        .reveal_clue(reveal_clue),
        .cascade_done(cascade_done),
        .busy(solver_busy),
        .done(solver_done),
        .protocol_error(solver_error),
        .selections_issued(selections_issued),
        .observed_safe_count(observed_safe_count),
        .observed_mine_count(observed_mine_count),
        .cycle_count(cycle_count)
    );

endmodule
