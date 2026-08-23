`timescale 1ns/1ps

// Production MU500-RX top. HEX_B=F runs the built-in ROM smoke pack; all
// other settings select the USB-Blaster/Virtual-JTAG transport.
module minesweeper_jtag_top #(
    parameter SIMULATION = 0,
    parameter DETERMINISTIC_SOLVER = 0,
    parameter FORCE_JTAG_MODE = 0,
    parameter FORCE_FULL_SPEED = 0,
    parameter MAX_PROBABILITY_GUESSES = 4,
    parameter ENABLE_ADAPTIVE_FEEDBACK = 0,
    parameter ENABLE_SATURATING_HALF_SAFE_FEEDBACK = 0,
    parameter BASE_PROBABILITY_GUESSES = 8,
    parameter ADAPTIVE_FEEDBACK_SAFE_THRESHOLD = 32,
    parameter ENABLE_LOW_SCORE_EDGE_RESCUE = 0,
    parameter LOW_SCORE_RESCUE_SAFE_THRESHOLD = 16
) (
    input  wire       CLK_20MHZ,
    input  wire       RESET_N,
    input  wire [3:0] HEX_A,
    input  wire [3:0] HEX_B,
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
    reg [1:0] reset_sync;
    wire reset = reset_sync[1];
    wire use_rom = !FORCE_JTAG_MODE && (HEX_B == 4'hF);
    wire [3:0] effective_speed = FORCE_FULL_SPEED ? 4'hF : HEX_A;

    wire rom_begin_valid, rom_begin_ready;
    wire [15:0] rom_board_id;
    wire [4:0] rom_width, rom_height;
    wire [8:0] rom_mines;
    wire rom_cell_valid, rom_cell_ready;
    wire [8:0] rom_cell_ordinal;
    wire [3:0] rom_cell_value;
    wire rom_commit_valid, rom_commit_ready;
    wire rom_result_ack, rom_finished;

    wire jtag_begin_valid, jtag_begin_ready;
    wire [15:0] jtag_board_id;
    wire [4:0] jtag_width, jtag_height;
    wire [8:0] jtag_mines;
    wire jtag_cell_valid, jtag_cell_ready;
    wire [8:0] jtag_cell_ordinal;
    wire [3:0] jtag_cell_value;
    wire jtag_commit_valid, jtag_commit_ready;
    wire jtag_result_ack;

    wire source_begin_valid = use_rom ? rom_begin_valid : jtag_begin_valid;
    wire source_begin_ready;
    wire [15:0] source_board_id = use_rom ? rom_board_id : jtag_board_id;
    wire [4:0] source_width = use_rom ? rom_width : jtag_width;
    wire [4:0] source_height = use_rom ? rom_height : jtag_height;
    wire [8:0] source_mines = use_rom ? rom_mines : jtag_mines;
    wire source_cell_valid = use_rom ? rom_cell_valid : jtag_cell_valid;
    wire source_cell_ready;
    wire [8:0] source_cell_ordinal = use_rom ? rom_cell_ordinal : jtag_cell_ordinal;
    wire [3:0] source_cell_value = use_rom ? rom_cell_value : jtag_cell_value;
    wire source_commit_valid = use_rom ? rom_commit_valid : jtag_commit_valid;
    wire source_commit_ready;

    wire cfg_valid, cfg_ready;
    wire [4:0] cfg_width, cfg_height;
    wire [8:0] cfg_mines;
    wire load_valid, load_ready;
    wire [8:0] load_index;
    wire [3:0] load_value;
    wire start_solver;
    wire board_done;
    wire [15:0] active_board_id;
    wire stream_error;

    wire solver_busy, solver_done, solver_stalled;
    wire core_result_valid, core_error;
    wire [15:0] boards_processed, boards_fully_solved;
    wire signed [31:0] current_score_scaled, total_score_scaled;
    wire [8:0] current_safe, current_mines;
    wire [8:0] current_selections;
    wire [31:0] current_cycles;
    wire [63:0] total_cycles;

    wire result_available;
    wire [15:0] result_board_id;
    wire [4:0] result_width, result_height;
    wire [8:0] result_total_mines;
    wire [8:0] result_selections;
    wire result_stalled;
    wire [8:0] result_opened_safe, result_opened_mines;
    wire [31:0] result_cycles;
    wire signed [31:0] result_score_scaled;
    wire result_protocol_error, result_overflow;
    wire result_ack = use_rom ? rom_result_ack : jtag_result_ack;

    wire mailbox_command_valid, mailbox_command_ready;
    wire [63:0] mailbox_command_word, mailbox_response_word;
    wire [63:0] unused_sim_response;
    wire jtag_transport_error;

    assign rom_begin_ready = use_rom && source_begin_ready;
    assign jtag_begin_ready = !use_rom && source_begin_ready;
    assign rom_cell_ready = use_rom && source_cell_ready;
    assign jtag_cell_ready = !use_rom && source_cell_ready;
    assign rom_commit_ready = use_rom && source_commit_ready;
    assign jtag_commit_ready = !use_rom && source_commit_ready;

    always @(posedge CLK_20MHZ or negedge RESET_N) begin
        if (!RESET_N)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end

    board_rom_loader u_rom (
        .clk(CLK_20MHZ), .reset(reset), .enable(use_rom),
        .begin_valid(rom_begin_valid), .begin_ready(rom_begin_ready),
        .begin_board_id(rom_board_id), .begin_width(rom_width),
        .begin_height(rom_height), .begin_mines(rom_mines),
        .cell_valid(rom_cell_valid), .cell_ready(rom_cell_ready),
        .cell_ordinal(rom_cell_ordinal), .cell_value(rom_cell_value),
        .commit_valid(rom_commit_valid), .commit_ready(rom_commit_ready),
        .result_available(result_available), .result_ack(rom_result_ack),
        .finished(rom_finished)
    );

    virtual_jtag_mailbox #(.SIMULATION(SIMULATION)) u_mailbox (
        .clk(CLK_20MHZ), .reset(reset),
        .command_valid(mailbox_command_valid),
        .command_ready(mailbox_command_ready),
        .command_word(mailbox_command_word),
        .response_word(mailbox_response_word),
        .sim_command_valid(1'b0), .sim_command_word(64'd0),
        .sim_response_word(unused_sim_response)
    );

    jtag_protocol_engine u_protocol (
        .clk(CLK_20MHZ), .reset(reset),
        .command_valid(mailbox_command_valid),
        .command_ready(mailbox_command_ready),
        .command_word(mailbox_command_word),
        .response_word(mailbox_response_word),
        .begin_valid(jtag_begin_valid), .begin_ready(jtag_begin_ready),
        .begin_board_id(jtag_board_id), .begin_width(jtag_width),
        .begin_height(jtag_height), .begin_mines(jtag_mines),
        .cell_valid(jtag_cell_valid), .cell_ready(jtag_cell_ready),
        .cell_ordinal(jtag_cell_ordinal), .cell_value(jtag_cell_value),
        .commit_valid(jtag_commit_valid), .commit_ready(jtag_commit_ready),
        .solver_busy(solver_busy), .result_available(result_available),
        .result_board_id(result_board_id), .result_width(result_width),
        .result_height(result_height), .result_total_mines(result_total_mines),
        .result_selections(result_selections),
        .result_stalled(result_stalled),
        .result_opened_safe(result_opened_safe),
        .result_opened_mines(result_opened_mines),
        .result_cycles(result_cycles), .result_score_scaled(result_score_scaled),
        .result_protocol_error(result_protocol_error),
        .result_ack(jtag_result_ack), .transport_error(jtag_transport_error)
    );

    board_stream_controller u_stream (
        .clk(CLK_20MHZ), .reset(reset),
        .begin_valid(source_begin_valid), .begin_ready(source_begin_ready),
        .begin_board_id(source_board_id), .begin_width(source_width),
        .begin_height(source_height), .begin_mines(source_mines),
        .cell_valid(source_cell_valid), .cell_ready(source_cell_ready),
        .cell_ordinal(source_cell_ordinal), .cell_value(source_cell_value),
        .commit_valid(source_commit_valid), .commit_ready(source_commit_ready),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_total_mines(cfg_mines),
        .load_valid(load_valid), .load_ready(load_ready),
        .load_index(load_index), .load_value(load_value),
        .start_solver(start_solver), .result_valid(core_result_valid),
        .board_done(board_done), .active_board_id(active_board_id),
        .protocol_error(stream_error)
    );

    minesweeper_mu500_system #(
        .DETERMINISTIC_SOLVER(DETERMINISTIC_SOLVER),
        .MAX_PROBABILITY_GUESSES(MAX_PROBABILITY_GUESSES),
        .ENABLE_ADAPTIVE_FEEDBACK(ENABLE_ADAPTIVE_FEEDBACK),
        .ENABLE_SATURATING_HALF_SAFE_FEEDBACK(
            ENABLE_SATURATING_HALF_SAFE_FEEDBACK),
        .BASE_PROBABILITY_GUESSES(BASE_PROBABILITY_GUESSES),
        .ADAPTIVE_FEEDBACK_SAFE_THRESHOLD(
            ADAPTIVE_FEEDBACK_SAFE_THRESHOLD),
        .ENABLE_LOW_SCORE_EDGE_RESCUE(ENABLE_LOW_SCORE_EDGE_RESCUE),
        .LOW_SCORE_RESCUE_SAFE_THRESHOLD(LOW_SCORE_RESCUE_SAFE_THRESHOLD)
    ) u_system (
        .clk(CLK_20MHZ), .reset(reset), .speed_setting(effective_speed),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_total_mines(cfg_mines),
        .load_valid(load_valid), .load_ready(load_ready),
        .load_index(load_index), .load_value(load_value),
        .start_solver(start_solver), .solver_busy(solver_busy),
        .solver_done(solver_done), .solver_stalled(solver_stalled),
        .result_valid(core_result_valid),
        .protocol_error(core_error), .boards_processed(boards_processed),
        .boards_fully_solved(boards_fully_solved),
        .current_score_scaled(current_score_scaled),
        .total_score_scaled(total_score_scaled),
        .current_safe(current_safe), .current_mines(current_mines),
        .current_selections(current_selections), .current_cycles(current_cycles),
        .total_cycles(total_cycles),
        .SEG_A(SEG_A),.SEG_B(SEG_B),.SEG_C(SEG_C),.SEG_D(SEG_D),
        .SEG_E(SEG_E),.SEG_F(SEG_F),.SEG_G(SEG_G),.SEG_H(SEG_H),
        .SEG_SEL(SEG_SEL)
    );

    result_snapshot u_result (
        .clk(CLK_20MHZ), .reset(reset), .capture(core_result_valid),
        .board_id(active_board_id), .width(cfg_width), .height(cfg_height),
        .total_mines(cfg_mines), .selections(current_selections),
        .stalled(solver_stalled),
        .opened_safe(current_safe), .opened_mines(current_mines),
        .cycles(current_cycles), .score_scaled(current_score_scaled),
        .protocol_error_in(core_error | stream_error), .acknowledge(result_ack),
        .available(result_available), .result_board_id(result_board_id),
        .result_width(result_width), .result_height(result_height),
        .result_total_mines(result_total_mines),
        .result_selections(result_selections),
        .result_stalled(result_stalled),
        .result_opened_safe(result_opened_safe),
        .result_opened_mines(result_opened_mines),
        .result_cycles(result_cycles), .result_score_scaled(result_score_scaled),
        .result_protocol_error(result_protocol_error),
        .overflow_error(result_overflow)
    );
endmodule
