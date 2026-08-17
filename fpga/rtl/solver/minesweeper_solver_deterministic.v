`timescale 1ns/1ps

// Deterministic solver over revealed knowledge only. It implements local
// R1-R3 deductions, global R4, and cached subset-difference R5 deductions.
module minesweeper_solver_deterministic #(
    parameter MAX_WIDTH = 19,
    parameter MAX_HEIGHT = 19,
    parameter MAX_CELLS = 361,
    parameter ENABLE_CORNER_ON_STALL = 1,
    parameter ENABLE_CONSTRAINT_COLLECTOR = 1,
    parameter MAX_COLLECTOR_CONSTRAINTS = 8,
    parameter ENABLE_PROBABILITY_FEEDBACK = 1,
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
    input  wire       start,
    input  wire [4:0] board_width,
    input  wire [4:0] board_height,
    input  wire [8:0] total_mines,
    output wire       select_valid,
    input  wire       select_ready,
    output wire [4:0] select_x,
    output wire [4:0] select_y,
    input  wire       select_rejected,
    input  wire       reveal_valid,
    input  wire [4:0] reveal_x,
    input  wire [4:0] reveal_y,
    input  wire       reveal_is_mine,
    input  wire [3:0] reveal_clue,
    input  wire       cascade_done,
    output reg        busy,
    output reg        done,
    output reg        stalled,
    output reg        protocol_error,
    output reg  [8:0] selections_issued,
    output reg  [8:0] observed_safe_count,
    output reg  [8:0] observed_mine_count,
    output reg  [8:0] known_mine_count,
    output reg [31:0] cycle_count
);
    localparam CELL_UNKNOWN     = 3'd0;
    localparam CELL_QUEUED_SAFE = 3'd1;
    localparam CELL_OPEN_SAFE   = 3'd2;
    localparam CELL_KNOWN_MINE  = 3'd3;
    localparam CELL_OPEN_MINE   = 3'd4;

    localparam S_IDLE           = 5'd0;
    localparam S_CLEAR          = 5'd1;
    localparam S_ISSUE          = 5'd2;
    localparam S_WAIT           = 5'd3;
    localparam S_R5_STORE_WAIT  = 5'd4;
    localparam S_SCAN_WAIT      = 5'd5;
    localparam S_POP_SAFE       = 5'd6;
    localparam S_FINISH         = 5'd7;
    localparam S_ERROR          = 5'd8;
    localparam S_WAIT_DRAIN     = 5'd9;
    localparam S_POP_READ_ADDR  = 5'd12;
    localparam S_POP_READ_WAIT  = 5'd13;
    localparam S_POP_CHECK      = 5'd14;
    localparam S_R4_CHECK       = 5'd15;
    localparam S_R4_SCAN_ADDR   = 5'd16;
    localparam S_R4_SCAN_WAIT   = 5'd17;
    localparam S_R4_SCAN_APPLY  = 5'd18;
    localparam S_CHANGE_POP     = 5'd19;
    localparam S_CHANGE_WALK    = 5'd20;
    localparam S_DIRTY_POP      = 5'd21;
    localparam S_DIRTY_READ_ADDR = 5'd22;
    localparam S_DIRTY_READ_WAIT = 5'd23;
    localparam S_DIRTY_CHECK    = 5'd24;
    localparam S_R5_INIT        = 5'd25;
    localparam S_R5_CANDIDATE   = 5'd26;
    localparam S_R5_COMPARE     = 5'd27;
    localparam S_R5_APPLY_ADDR  = 5'd28;
    localparam S_R5_APPLY_WAIT  = 5'd29;
    localparam S_R5_APPLY       = 6'd30;
    localparam S_COMP_CLEAR     = 6'd31;
    localparam S_COMP_LOAD_A    = 6'd32;
    localparam S_COMP_LOAD_B    = 6'd33;
    localparam S_COMP_SOLVE     = 6'd34;
    localparam S_COMP_WAIT      = 6'd35;
    localparam S_COMP_APPLY_ADDR = 6'd36;
    localparam S_COMP_APPLY_WAIT = 6'd37;
    localparam S_COMP_APPLY     = 6'd38;
    localparam S_OPEN_NEXT      = 6'd39;
    localparam S_OPEN_READ_ADDR = 6'd40;
    localparam S_OPEN_READ_WAIT = 6'd41;
    localparam S_OPEN_CHECK     = 6'd42;
    localparam S_COLLECT_INIT      = 6'd43;
    localparam S_COLLECT_SEED      = 6'd44;
    localparam S_COLLECT_READ_ADDR = 6'd45;
    localparam S_COLLECT_READ_WAIT = 6'd46;
    localparam S_COLLECT_LOAD      = 6'd47;
    localparam S_COLLECT_SCAN_NEXT = 6'd48;
    localparam S_COLLECT_SOLVE     = 6'd49;
    localparam S_PROB_READ_ADDR    = 6'd50;
    localparam S_PROB_READ_WAIT    = 6'd51;
    localparam S_PROB_CHECK        = 6'd52;
    localparam S_RESCUE_NEXT       = 6'd53;
    localparam S_RESCUE_READ_ADDR  = 6'd54;
    localparam S_RESCUE_READ_WAIT  = 6'd55;
    localparam S_RESCUE_CHECK      = 6'd56;

    localparam R4_ALL_SAFE = 1'b0;
    localparam R4_ALL_MINE = 1'b1;

    reg [5:0] state;
    reg [4:0] width;
    reg [4:0] height;
    reg [8:0] mines;
    reg [4:0] active_x;
    reg [4:0] active_y;
    reg [4:0] scan_x;
    reg [4:0] scan_y;
    reg [3:0] scan_clue;
    reg r4_mode;
    reg [4:0] changed_x;
    reg [4:0] changed_y;
    reg [3:0] changed_direction;
    reg ram_clear_start;
    reg fifo_clear;
    reg scan_start;
    reg reveal_pending;
    reg [8:0] pending_reveal_index;
    reg [4:0] pending_reveal_x;
    reg [4:0] pending_reveal_y;
    reg pending_reveal_is_mine;
    reg [3:0] pending_reveal_clue;
    reg [8:0] unknown_count;
    reg [8:0] remaining_mines;
    reg [8:0] queued_safe_count;
    reg [MAX_CELLS-1:0] constraint_valid;
    reg [4:0] r5_center_x;
    reg [4:0] r5_center_y;
    reg [4:0] r5_candidate_offset;
    reg [24:0] r5_apply_mask;
    reg r5_apply_is_mine;
    reg signed [6:0] r5_apply_base_x;
    reg signed [6:0] r5_apply_base_y;
    reg [31:0] r5_safe_count;
    reg [31:0] r5_mine_count;
    reg [31:0] constraint_rebuild_count;
    reg [31:0] constraint_compare_count;
    reg [31:0] derived_store_overflow_count;
    reg component_pair_tried;
    reg component_clear;
    reg [8:0] component_apply_index;
    reg component_apply_is_mine;
    reg component_constraint_sent;
    reg component_changed;
    reg [31:0] component_safe_count;
    reg [31:0] component_mine_count;
    reg component_collector_mode;
    reg [8:0] collector_seed_index;
    reg [8:0] collector_scan_index;
    reg [8:0] collector_read_index;
    reg collector_loading_seed;
    reg collector_pass_added;
    reg collector_closed_local;
    reg [2:0] collector_source_count;
    reg [8:0] collector_source_0;
    reg [8:0] collector_source_1;
    reg [8:0] collector_source_2;
    reg [8:0] collector_source_3;
    reg collector_signature_valid;
    reg [38:0] collector_signature_0;
    reg [31:0] component_candidate_count;
    reg [8:0] component_last_candidate_cell;
    reg [31:0] component_last_candidate_mines;
    reg [31:0] component_last_candidate_ways;
    reg best_candidate_valid;
    reg [8:0] best_candidate_cell;
    reg [12:0] best_candidate_mines;
    reg [12:0] best_candidate_ways;
    reg [3:0] probability_guess_count;
    reg [2:0] rescue_step;
`ifdef SIM_PROFILE
    reg [31:0] profile_reveal_cycles;
    reg [31:0] profile_r123_cycles;
    reg [31:0] profile_r4_cycles;
    reg [31:0] profile_r5_cycles;
    reg [31:0] profile_collector_cycles;
    reg [31:0] profile_builder_cycles;
    reg [31:0] profile_enumeration_cycles;
    reg [31:0] profile_candidate_cycles;
    reg [31:0] profile_corner_cycles;
    reg [31:0] profile_other_cycles;
    reg [31:0] profile_component_attempts;
    reg [31:0] profile_component_completions;
    reg [31:0] profile_component_forced;
    reg [31:0] profile_component_closed;
    reg [31:0] profile_component_incomplete;
    reg [31:0] profile_component_duplicate_skips;
    reg [63:0] profile_enumeration_nodes;
`endif
    reg [2:0] opening_step;
    reg [7:0] board_generation;
    reg [8:0] dirty_queue_max_depth;
    integer changed_nx;
    integer changed_ny;
    integer changed_index_calc;
    integer r5_candidate_x_calc;
    integer r5_candidate_y_calc;
    integer r5_candidate_index_calc;
    integer r5_apply_position;
    integer r5_apply_x_calc;
    integer r5_apply_y_calc;
    integer r5_apply_index_calc;
    integer r5_bit_search;
    integer r5_bit_found;
    integer collector_scan_lane;
    integer collector_scan_candidate;
    reg collector_scan_found;
    reg [8:0] collector_scan_selected;

    wire [9:0] reveal_index_wide = (reveal_y << 4) +
                                    (reveal_y << 1) + reveal_y + reveal_x;
    wire [8:0] reveal_index = reveal_index_wide[8:0];

    wire ram_clear_busy;
    wire ram_clear_done;
    wire [8:0] ram_read_index;
    wire [2:0] ram_read_state;
    wire [3:0] ram_read_clue;
    wire change_push_ready;
    wire change_push_duplicate;
    wire reveal_state_compatible = pending_reveal_is_mine ?
        ((ram_read_state == CELL_UNKNOWN) ||
         (ram_read_state == CELL_KNOWN_MINE)) :
        ((ram_read_state == CELL_UNKNOWN) ||
         (ram_read_state == CELL_QUEUED_SAFE));
    wire reveal_counter_valid =
        (ram_read_state == CELL_UNKNOWN) ?
        (unknown_count != 0 &&
         (pending_reveal_is_mine ? (remaining_mines != 0) :
          (remaining_mines < unknown_count))) :
        (ram_read_state == CELL_QUEUED_SAFE) ?
        (queued_safe_count != 0) :
        (ram_read_state == CELL_KNOWN_MINE) ?
        (known_mine_count != 0) : 1'b0;
    wire reveal_transition_valid =
        pending_reveal_x < width && pending_reveal_y < height &&
        pending_reveal_index < MAX_CELLS &&
        (!pending_reveal_is_mine ? (pending_reveal_clue <= 8) : 1'b1) &&
        reveal_state_compatible && reveal_counter_valid &&
        (change_push_ready || change_push_duplicate);
    wire ram_write_from_reveal = reveal_pending &&
        ((state == S_WAIT) || (state == S_WAIT_DRAIN)) && run_enable &&
        reveal_transition_valid;
    wire [8:0] scan_cell_index = (scan_y << 4) + (scan_y << 1) +
                                 scan_y + scan_x;
    wire [8:0] active_cell_index = (active_y << 4) + (active_y << 1) +
                                   active_y + active_x;
    wire scan_last_cell = (scan_x + 1'b1 == width) &&
                          (scan_y + 1'b1 == height);

    wire scan_result_valid;
    wire [8:0] scan_result_index;
    wire [4:0] scan_result_x;
    wire [4:0] scan_result_y;
    wire [2:0] scan_result_state;
    wire scan_result_is_safe = scan_result_state == CELL_QUEUED_SAFE;
    wire scan_result_ready;
    wire scan_busy;
    wire scan_done;
    wire scan_contradiction;
    wire [8:0] scan_read_index;
    wire [7:0] scan_constraint_mask;
    wire [3:0] scan_constraint_count;
    wire [3:0] scan_constraint_remaining;
    wire [7:0] cache_read_a_mask;
    wire [3:0] cache_read_a_remaining;
    wire [7:0] cache_read_b_mask;
    wire [3:0] cache_read_b_remaining;

    wire fifo_push_ready;
    wire fifo_push_duplicate;
    wire fifo_pop_valid;
    wire [8:0] fifo_pop_index;
    wire [4:0] fifo_pop_x;
    wire [4:0] fifo_pop_y;
    wire [8:0] fifo_count;
    wire fifo_overflow;
    wire change_pop_valid;
    wire [8:0] change_pop_index;
    wire [4:0] change_pop_x;
    wire [4:0] change_pop_y;
    wire [8:0] change_count;
    wire change_overflow;
    wire dirty_push_ready;
    wire dirty_push_duplicate;
    wire dirty_pop_valid;
    wire [8:0] dirty_pop_index;
    wire [4:0] dirty_pop_x;
    wire [4:0] dirty_pop_y;
    wire [8:0] dirty_count;
    wire dirty_overflow;
    wire [8:0] r5_center_index = (r5_center_y << 4) +
                                  (r5_center_y << 1) +
                                  r5_center_y + r5_center_x;
    wire r5_candidate_in_range = r5_candidate_x_calc >= 0 &&
                                 r5_candidate_y_calc >= 0 &&
                                 r5_candidate_x_calc < width &&
                                 r5_candidate_y_calc < height;
    wire [8:0] r5_candidate_index = r5_candidate_index_calc[8:0];
    wire [8:0] r5_candidate_cache_index = r5_candidate_in_range ?
                                               r5_candidate_index : 9'd0;
    wire r5_pair_available = r5_candidate_in_range &&
        r5_candidate_index > r5_center_index &&
        constraint_valid[r5_center_index] &&
        constraint_valid[r5_candidate_cache_index];
    wire r5_compare_applicable;
    wire r5_compare_contradiction;
    wire r5_compare_is_mine;
    wire [24:0] r5_compare_difference_mask;
    wire r5_compare_derived_valid;
    wire [4:0] r5_compare_difference_mines;
    wire [4:0] r5_compare_difference_count;
    wire signed [6:0] r5_compare_base_x;
    wire signed [6:0] r5_compare_base_y;
    wire derived_store_ready;
    wire derived_store_done;
    wire derived_store_inserted;
    wire derived_store_duplicate;
    wire derived_store_contradiction;
    wire derived_store_overflow;
    wire [8:0] derived_constraint_count;
    wire derived_store_clear = state == S_IDLE && start;
    wire derived_store_insert_valid = state == S_R5_COMPARE &&
                                      r5_compare_derived_valid;
    wire [8:0] r5_apply_index = r5_apply_index_calc[8:0];
    wire component_constraint_valid =
        (state == S_COMP_LOAD_A || state == S_COMP_LOAD_B ||
         state == S_COLLECT_LOAD) &&
        !component_constraint_sent;
    wire component_constraint_done;
    wire component_constraint_added_wire;
    wire component_constraint_incomplete_wire;
    wire component_constraint_ready;
    wire component_solve_ready;
    wire component_result_valid;
    wire component_result_ready;
    wire [8:0] component_result_cell;
    wire component_result_is_mine;
    wire component_done;
    wire component_error;
    wire component_overflow;
    wire [3:0] component_variable_count;
    wire [4:0] component_constraint_count;
    wire [31:0] component_enumeration_nodes;
    wire [31:0] component_total_ways;
    wire component_candidate_valid;
    wire [8:0] component_candidate_cell;
    wire [31:0] component_candidate_mines;
    wire [31:0] component_candidate_ways;
    wire component_candidate_closed;
    wire [3:0] component_profile_state;
    wire [25:0] candidate_compare_left =
        component_candidate_mines[12:0] * best_candidate_ways;
    wire [25:0] candidate_compare_right =
        best_candidate_mines * component_candidate_ways[12:0];
    wire component_candidate_better = !best_candidate_valid ||
        candidate_compare_left < candidate_compare_right ||
        (candidate_compare_left == candidate_compare_right &&
         component_candidate_cell < best_candidate_cell);
    // After the regular feedback budget, continue while fewer than half of all
    // safe cells have been opened. Doubling the opened-safe count avoids a
    // divider: 2 * opened_safe < board_cells - total_mines.
    wire [9:0] adaptive_board_cells = width * height;
    wire [22:0] adaptive_risk_left =
        best_candidate_mines * adaptive_board_cells;
    wire [21:0] adaptive_risk_right =
        mines * best_candidate_ways;
    wire adaptive_feedback_allowed = ENABLE_ADAPTIVE_FEEDBACK &&
        probability_guess_count >= BASE_PROBABILITY_GUESSES &&
        probability_guess_count < MAX_PROBABILITY_GUESSES &&
        observed_safe_count < ADAPTIVE_FEEDBACK_SAFE_THRESHOLD &&
        adaptive_risk_left < adaptive_risk_right;
    wire [9:0] half_safe_opened_twice = observed_safe_count << 1;
    wire [9:0] half_safe_total = adaptive_board_cells - mines;
    wire saturating_half_safe_feedback_allowed =
        ENABLE_SATURATING_HALF_SAFE_FEEDBACK &&
        probability_guess_count >= BASE_PROBABILITY_GUESSES &&
        half_safe_opened_twice < half_safe_total;
    wire probability_feedback_allowed =
        (probability_guess_count < MAX_PROBABILITY_GUESSES &&
         probability_guess_count < BASE_PROBABILITY_GUESSES) ||
        adaptive_feedback_allowed ||
        saturating_half_safe_feedback_allowed;
    wire collector_seed_duplicate = collector_signature_valid &&
        ((collector_signature_0[38:36] > 0 &&
          collector_seed_index == collector_signature_0[8:0]) ||
         (collector_signature_0[38:36] > 1 &&
          collector_seed_index == collector_signature_0[17:9]) ||
         (collector_signature_0[38:36] > 2 &&
          collector_seed_index == collector_signature_0[26:18]) ||
         (collector_signature_0[38:36] > 3 &&
          collector_seed_index == collector_signature_0[35:27]));
    wire collector_cache_read = state == S_COLLECT_READ_ADDR ||
                                state == S_COLLECT_READ_WAIT ||
                                state == S_COLLECT_LOAD;
    wire [8:0] cache_read_a_index = collector_cache_read ?
                                    collector_read_index :
                                    r5_center_index;
    wire [4:0] collector_center_x = collector_read_index % 19;
    wire [4:0] collector_center_y = collector_read_index / 19;
    wire [4:0] component_apply_x = component_apply_index % 19;
    wire [4:0] component_apply_y = component_apply_index / 19;

    // Check two sparse constraint slots per cycle. Components usually contain
    // only a small fraction of MAX_CELLS valid constraints, so a small local
    // priority encoder removes most empty-slot collector cycles without a
    // full-width 361-bit priority network.
    always @* begin
        collector_scan_found = 1'b0;
        collector_scan_selected = collector_scan_index;
        collector_scan_candidate = 0;
        for (collector_scan_lane = 0; collector_scan_lane < 2;
             collector_scan_lane = collector_scan_lane + 1) begin
            collector_scan_candidate = collector_scan_index +
                                       collector_scan_lane;
            if (!collector_scan_found &&
                collector_scan_candidate < MAX_CELLS &&
                collector_scan_candidate != collector_seed_index &&
                constraint_valid[collector_scan_candidate]) begin
                collector_scan_found = 1'b1;
                collector_scan_selected =
                    collector_scan_candidate[8:0];
            end
        end
    end
    wire r5_apply_in_range = r5_apply_x_calc >= 0 &&
                             r5_apply_y_calc >= 0 &&
                             r5_apply_x_calc < width &&
                             r5_apply_y_calc < height;
    wire [24:0] r5_apply_bit_mask = 25'b1 << r5_apply_position;
    wire r5_apply_last = (r5_apply_mask & ~r5_apply_bit_mask) == 0;
    wire scan_counter_valid = (unknown_count != 0) &&
        (scan_result_is_safe ? (remaining_mines < unknown_count) :
         (remaining_mines != 0));
    wire r4_apply_unknown = (state == S_R4_SCAN_APPLY) &&
                            (ram_read_state == CELL_UNKNOWN);
    wire r4_safe_push_request = r4_apply_unknown &&
                                (r4_mode == R4_ALL_SAFE);
    wire r4_safe_push_valid = r4_safe_push_request && fifo_push_ready;
    wire scan_safe_push_valid = (state == S_SCAN_WAIT) &&
                                scan_result_valid && scan_result_is_safe &&
                                scan_counter_valid;
    wire r5_apply_unknown = (state == S_R5_APPLY) &&
                            r5_apply_mask != 0 && r5_apply_in_range &&
                            ram_read_state == CELL_UNKNOWN;
    wire r5_safe_push_request = r5_apply_unknown && !r5_apply_is_mine;
    wire r5_safe_push_valid = r5_safe_push_request && fifo_push_ready;
    wire component_apply_unknown = state == S_COMP_APPLY &&
        ram_read_state == CELL_UNKNOWN;
    wire component_apply_compatible =
        (component_apply_is_mine &&
         ram_read_state == CELL_KNOWN_MINE) ||
        (!component_apply_is_mine &&
         ram_read_state == CELL_QUEUED_SAFE);
    wire component_safe_push_request = component_apply_unknown &&
        !component_apply_is_mine;
    wire component_safe_push_valid = component_safe_push_request &&
        fifo_push_ready;
    wire fifo_push_valid = scan_safe_push_valid || r4_safe_push_valid ||
                           r5_safe_push_valid || component_safe_push_valid;
    wire fifo_pop_ready = (state == S_POP_SAFE) && run_enable;

    assign scan_result_ready = !scan_counter_valid ||
        ((!scan_result_is_safe || fifo_push_ready || fifo_push_duplicate) &&
         (change_push_ready || change_push_duplicate));
    assign ram_read_index = ((state == S_WAIT) ||
                             (state == S_WAIT_DRAIN)) ?
                            (reveal_pending ? pending_reveal_index :
                             reveal_index) :
                            (state == S_SCAN_WAIT) ? scan_read_index :
                            ((state == S_POP_READ_ADDR) ||
                             (state == S_POP_READ_WAIT) ||
                             (state == S_POP_CHECK)) ? active_cell_index :
                            ((state == S_R5_APPLY_ADDR) ||
                             (state == S_R5_APPLY_WAIT) ||
                             (state == S_R5_APPLY)) ? r5_apply_index :
                            ((state == S_COMP_APPLY_ADDR) ||
                             (state == S_COMP_APPLY_WAIT) ||
                             (state == S_COMP_APPLY)) ?
                            component_apply_index :
                            ((state == S_OPEN_READ_ADDR) ||
                             (state == S_OPEN_READ_WAIT) ||
                             (state == S_OPEN_CHECK) ||
                             (state == S_PROB_READ_ADDR) ||
                             (state == S_PROB_READ_WAIT) ||
                             (state == S_PROB_CHECK) ||
                             (state == S_RESCUE_READ_ADDR) ||
                             (state == S_RESCUE_READ_WAIT) ||
                             (state == S_RESCUE_CHECK)) ?
                            active_cell_index :
                            scan_cell_index;
    wire ram_write_from_scan = (state == S_SCAN_WAIT) && scan_result_valid &&
                               scan_result_ready && scan_counter_valid;
    wire ram_write_from_r4 = r4_apply_unknown &&
        ((r4_mode == R4_ALL_MINE) || fifo_push_ready);
    wire r5_queues_ready =
        (r5_apply_is_mine || fifo_push_ready || fifo_push_duplicate) &&
        (change_push_ready || change_push_duplicate);
    wire ram_write_from_r5 = r5_apply_unknown && r5_queues_ready;
    wire component_queues_ready =
        (component_apply_is_mine || fifo_push_ready ||
         fifo_push_duplicate) &&
        (change_push_ready || change_push_duplicate);
    wire ram_write_from_component = component_apply_unknown &&
                                    component_queues_ready;
    wire ram_write_valid = ram_write_from_reveal || ram_write_from_scan ||
                           ram_write_from_r4 || ram_write_from_r5 ||
                           ram_write_from_component;
    wire [8:0] ram_write_index = ram_write_from_reveal ?
                                 pending_reveal_index :
                                 ram_write_from_scan ? scan_result_index :
                                 ram_write_from_r4 ? scan_cell_index :
                                 ram_write_from_r5 ? r5_apply_index :
                                 component_apply_index;
    wire [2:0] ram_write_state = ram_write_from_reveal ?
        (pending_reveal_is_mine ? CELL_OPEN_MINE : CELL_OPEN_SAFE) :
        ram_write_from_scan ? scan_result_state :
        ram_write_from_r4 ?
        (r4_mode == R4_ALL_SAFE ? CELL_QUEUED_SAFE : CELL_KNOWN_MINE) :
        ram_write_from_r5 ?
        (r5_apply_is_mine ? CELL_KNOWN_MINE : CELL_QUEUED_SAFE) :
        (component_apply_is_mine ? CELL_KNOWN_MINE : CELL_QUEUED_SAFE);
    wire [3:0] ram_write_clue = ram_write_from_reveal ?
                                pending_reveal_clue : 4'd0;

    wire change_push_valid = ram_write_from_reveal || ram_write_from_scan ||
                             ram_write_from_r5 || ram_write_from_component;
    wire change_push_from_reveal = reveal_pending &&
        ((state == S_WAIT) || (state == S_WAIT_DRAIN));
    wire change_push_from_r5 = state == S_R5_APPLY;
    wire change_push_from_component = state == S_COMP_APPLY;
    wire [8:0] change_push_index = change_push_from_reveal ?
                                   pending_reveal_index :
                                   change_push_from_r5 ? r5_apply_index :
                                   change_push_from_component ?
                                   component_apply_index : scan_result_index;
    wire [4:0] change_push_x = change_push_from_reveal ?
                               pending_reveal_x :
                               change_push_from_r5 ? r5_apply_x_calc[4:0] :
                               change_push_from_component ?
                               component_apply_x : scan_result_x;
    wire [4:0] change_push_y = change_push_from_reveal ?
                               pending_reveal_y :
                               change_push_from_r5 ? r5_apply_y_calc[4:0] :
                               change_push_from_component ?
                               component_apply_y : scan_result_y;
    wire change_pop_ready = state == S_CHANGE_POP && run_enable;

    always @* begin
        case (changed_direction)
            0: begin changed_nx = changed_x;     changed_ny = changed_y;     end
            1: begin changed_nx = changed_x - 1; changed_ny = changed_y - 1; end
            2: begin changed_nx = changed_x;     changed_ny = changed_y - 1; end
            3: begin changed_nx = changed_x + 1; changed_ny = changed_y - 1; end
            4: begin changed_nx = changed_x - 1; changed_ny = changed_y;     end
            5: begin changed_nx = changed_x + 1; changed_ny = changed_y;     end
            6: begin changed_nx = changed_x - 1; changed_ny = changed_y + 1; end
            7: begin changed_nx = changed_x;     changed_ny = changed_y + 1; end
            default: begin
                changed_nx = changed_x + 1;
                changed_ny = changed_y + 1;
            end
        endcase
        changed_index_calc = (changed_ny << 4) + (changed_ny << 1) +
                             changed_ny + changed_nx;
    end

    always @* begin
        r5_candidate_x_calc = r5_center_x +
                              (r5_candidate_offset % 5) - 2;
        r5_candidate_y_calc = r5_center_y +
                              (r5_candidate_offset / 5) - 2;
        r5_candidate_index_calc =
            (r5_candidate_y_calc << 4) +
            (r5_candidate_y_calc << 1) +
            r5_candidate_y_calc + r5_candidate_x_calc;

        r5_apply_position = 0;
        r5_bit_found = 0;
        for (r5_bit_search = 0; r5_bit_search < 25;
             r5_bit_search = r5_bit_search + 1) begin
            if (!r5_bit_found && r5_apply_mask[r5_bit_search]) begin
                r5_apply_position = r5_bit_search;
                r5_bit_found = 1;
            end
        end
        r5_apply_x_calc = r5_apply_base_x + (r5_apply_position % 5);
        r5_apply_y_calc = r5_apply_base_y + (r5_apply_position / 5);
        r5_apply_index_calc = (r5_apply_y_calc << 4) +
                              (r5_apply_y_calc << 1) +
                              r5_apply_y_calc + r5_apply_x_calc;
    end
    wire changed_candidate_in_range = changed_nx >= 0 && changed_ny >= 0 &&
                                      changed_nx < width &&
                                      changed_ny < height;
    wire dirty_push_request = state == S_CHANGE_WALK &&
                              changed_candidate_in_range;
    wire dirty_push_valid = dirty_push_request &&
                            (dirty_push_ready || dirty_push_duplicate);
    wire dirty_pop_ready = state == S_DIRTY_POP && run_enable;

    assign select_valid = (state == S_ISSUE);
    assign select_x = active_x;
    assign select_y = active_y;

    solver_state_ram #(.MAX_CELLS(MAX_CELLS)) u_state_ram (
        .clk(clk), .reset(reset), .clear_start(ram_clear_start),
        .clear_busy(ram_clear_busy), .clear_done(ram_clear_done),
        .write_valid(ram_write_valid), .write_index(ram_write_index),
        .write_state(ram_write_state), .write_clue(ram_write_clue),
        .read_index(ram_read_index), .read_state(ram_read_state),
        .read_clue(ram_read_clue)
    );

    solver_safe_fifo #(.MAX_CELLS(MAX_CELLS)) u_safe_fifo (
        .clk(clk), .reset(reset), .clear(fifo_clear),
        .push_valid(fifo_push_valid),
        .push_index(r4_safe_push_request ? scan_cell_index :
                    r5_safe_push_request ? r5_apply_index :
                    component_safe_push_request ? component_apply_index :
                                           scan_result_index),
        .push_x(r4_safe_push_request ? scan_x :
                r5_safe_push_request ? r5_apply_x_calc[4:0] :
                component_safe_push_request ? component_apply_x :
                scan_result_x),
        .push_y(r4_safe_push_request ? scan_y :
                r5_safe_push_request ? r5_apply_y_calc[4:0] :
                component_safe_push_request ? component_apply_y :
                scan_result_y),
        .push_ready(fifo_push_ready), .push_duplicate(fifo_push_duplicate),
        .pop_valid(fifo_pop_valid), .pop_index(fifo_pop_index),
        .pop_x(fifo_pop_x), .pop_y(fifo_pop_y),
        .pop_ready(fifo_pop_ready), .count(fifo_count),
        .overflow_error(fifo_overflow)
    );

    solver_dirty_fifo #(.MAX_CELLS(MAX_CELLS)) u_change_fifo (
        .clk(clk), .reset(reset), .clear(fifo_clear),
        .push_valid(change_push_valid), .push_index(change_push_index),
        .push_x(change_push_x), .push_y(change_push_y),
        .push_ready(change_push_ready),
        .push_duplicate(change_push_duplicate),
        .pop_valid(change_pop_valid), .pop_index(change_pop_index),
        .pop_x(change_pop_x), .pop_y(change_pop_y),
        .pop_ready(change_pop_ready), .count(change_count),
        .overflow_error(change_overflow)
    );

    solver_dirty_fifo #(.MAX_CELLS(MAX_CELLS)) u_dirty_fifo (
        .clk(clk), .reset(reset), .clear(fifo_clear),
        .push_valid(dirty_push_valid),
        .push_index(changed_index_calc[8:0]),
        .push_x(changed_nx[4:0]), .push_y(changed_ny[4:0]),
        .push_ready(dirty_push_ready),
        .push_duplicate(dirty_push_duplicate),
        .pop_valid(dirty_pop_valid), .pop_index(dirty_pop_index),
        .pop_x(dirty_pop_x), .pop_y(dirty_pop_y),
        .pop_ready(dirty_pop_ready), .count(dirty_count),
        .overflow_error(dirty_overflow)
    );

    solver_neighbor_scan u_neighbor_scan (
        .clk(clk), .reset(reset), .start(scan_start),
        .board_width(width), .board_height(height),
        .center_x(scan_x), .center_y(scan_y),
        .center_clue(scan_clue), .read_index(scan_read_index),
        .read_state(ram_read_state), .result_valid(scan_result_valid),
        .result_index(scan_result_index), .result_state(scan_result_state),
        .result_x(scan_result_x), .result_y(scan_result_y),
        .result_ready(scan_result_ready), .busy(scan_busy), .done(scan_done),
        .contradiction(scan_contradiction),
        .constraint_unknown_mask(scan_constraint_mask),
        .constraint_unknown_count(scan_constraint_count),
        .constraint_remaining_mines(scan_constraint_remaining)
    );

    solver_constraint_cache #(.MAX_CELLS(MAX_CELLS))
    u_constraint_cache (
        .clk(clk),
        .write_valid(state == S_SCAN_WAIT && scan_done &&
                     !scan_contradiction && scan_constraint_count != 0),
        .write_index(scan_cell_index),
        .write_mask(scan_constraint_mask),
        .write_remaining(scan_constraint_remaining),
        .read_a_index(cache_read_a_index),
        .read_a_mask(cache_read_a_mask),
        .read_a_remaining(cache_read_a_remaining),
        .read_b_index(r5_candidate_cache_index),
        .read_b_mask(cache_read_b_mask),
        .read_b_remaining(cache_read_b_remaining)
    );

    solver_r5_compare u_r5_compare (
        .center_a_x(r5_center_x),
        .center_a_y(r5_center_y),
        .local_mask_a(cache_read_a_mask),
        .remaining_a(cache_read_a_remaining),
        .center_b_x(r5_candidate_x_calc[4:0]),
        .center_b_y(r5_candidate_y_calc[4:0]),
        .local_mask_b(cache_read_b_mask),
        .remaining_b(cache_read_b_remaining),
        .applicable(r5_compare_applicable),
        .contradiction(r5_compare_contradiction),
        .result_is_mine(r5_compare_is_mine),
        .difference_mask(r5_compare_difference_mask),
        .derived_valid(r5_compare_derived_valid),
        .difference_mines(r5_compare_difference_mines),
        .difference_count(r5_compare_difference_count),
        .base_x(r5_compare_base_x), .base_y(r5_compare_base_y)
    );

    solver_derived_constraint_store u_derived_constraint_store (
        .clk(clk), .reset(reset), .clear(derived_store_clear),
        .insert_valid(derived_store_insert_valid),
        .insert_ready(derived_store_ready),
        .insert_base_x(r5_compare_base_x),
        .insert_base_y(r5_compare_base_y),
        .insert_mask(r5_compare_difference_mask),
        .insert_mines(r5_compare_difference_mines),
        .insert_generation(board_generation),
        .done(derived_store_done), .inserted(derived_store_inserted),
        .duplicate(derived_store_duplicate),
        .contradiction(derived_store_contradiction),
        .overflow(derived_store_overflow),
        .stored_count(derived_constraint_count),
        .scan_valid(1'b0), .scan_ready(), .scan_index(8'd0),
        .scan_response_valid(), .scan_slot_valid(), .scan_mask(),
        .scan_base_x(), .scan_base_y(), .scan_mines(),
        .scan_generation()
    );

    assign component_result_ready = state == S_COMP_APPLY &&
        (component_apply_unknown ? component_queues_ready :
                                   component_apply_compatible);

    solver_small_component_pipeline #(
        .SKIP_DISCONNECTED(1),
        .MAX_CONSTRAINTS(MAX_COLLECTOR_CONSTRAINTS)
    ) u_small_component_pipeline (
        .clk(clk), .reset(reset), .clear(component_clear),
        .constraint_valid(component_constraint_valid),
        .constraint_ready(component_constraint_ready),
        .constraint_is_derived(1'b0),
        .board_width(width), .board_height(height),
        .constraint_center_x(state == S_COLLECT_LOAD ?
                             collector_center_x :
                             (state == S_COMP_LOAD_A ?
                              r5_center_x : r5_candidate_x_calc[4:0])),
        .constraint_center_y(state == S_COLLECT_LOAD ?
                             collector_center_y :
                             (state == S_COMP_LOAD_A ?
                              r5_center_y : r5_candidate_y_calc[4:0])),
        .constraint_base_x(7'sd0), .constraint_base_y(7'sd0),
        .constraint_local_mask(state == S_COLLECT_LOAD ?
                               cache_read_a_mask :
                               (state == S_COMP_LOAD_A ?
                                cache_read_a_mask : cache_read_b_mask)),
        .constraint_derived_mask(25'd0),
        .constraint_mines(state == S_COLLECT_LOAD ?
                          {1'b0, cache_read_a_remaining} :
                          (state == S_COMP_LOAD_A ?
                           {1'b0, cache_read_a_remaining} :
                           {1'b0, cache_read_b_remaining})),
        .constraint_done(component_constraint_done),
        .constraint_added(component_constraint_added_wire),
        .constraint_incomplete(component_constraint_incomplete_wire),
        .solve_start((state == S_COMP_SOLVE ||
                      state == S_COLLECT_SOLVE) &&
                     component_solve_ready),
        .solve_ready(component_solve_ready),
        .maximum_mines(4'd12),
        .closed_local(component_collector_mode && collector_closed_local),
        .result_valid(component_result_valid),
        .result_ready(component_result_ready),
        .result_cell(component_result_cell),
        .result_is_mine(component_result_is_mine),
        .done(component_done), .error(component_error),
        .overflow(component_overflow),
        .variable_count(component_variable_count),
        .component_constraint_count(component_constraint_count),
        .enumeration_nodes(component_enumeration_nodes),
        .total_ways(component_total_ways),
        .candidate_valid(component_candidate_valid),
        .candidate_ready(1'b1),
        .candidate_cell(component_candidate_cell),
        .candidate_mine_ways(component_candidate_mines),
        .candidate_total_ways(component_candidate_ways),
        .candidate_closed_local(component_candidate_closed),
        .profile_state(component_profile_state)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            width <= 0;
            height <= 0;
            mines <= 0;
            active_x <= 0;
            active_y <= 0;
            scan_x <= 0;
            scan_y <= 0;
            scan_clue <= 0;
            r4_mode <= R4_ALL_SAFE;
            changed_x <= 0;
            changed_y <= 0;
            changed_direction <= 0;
            ram_clear_start <= 0;
            fifo_clear <= 0;
            scan_start <= 0;
            reveal_pending <= 0;
            pending_reveal_index <= 0;
            pending_reveal_x <= 0;
            pending_reveal_y <= 0;
            pending_reveal_is_mine <= 0;
            pending_reveal_clue <= 0;
            unknown_count <= 0;
            remaining_mines <= 0;
            queued_safe_count <= 0;
            constraint_valid <= {MAX_CELLS{1'b0}};
            r5_center_x <= 0;
            r5_center_y <= 0;
            r5_candidate_offset <= 0;
            r5_apply_mask <= 0;
            r5_apply_is_mine <= 0;
            r5_apply_base_x <= 0;
            r5_apply_base_y <= 0;
            r5_safe_count <= 0;
            r5_mine_count <= 0;
            constraint_rebuild_count <= 0;
            constraint_compare_count <= 0;
            derived_store_overflow_count <= 0;
            component_pair_tried <= 1'b0;
            component_clear <= 1'b0;
            component_apply_index <= 9'd0;
            component_apply_is_mine <= 1'b0;
            component_constraint_sent <= 1'b0;
            component_changed <= 1'b0;
            component_safe_count <= 32'd0;
            component_mine_count <= 32'd0;
            component_collector_mode <= 1'b0;
            collector_seed_index <= 9'd0;
            collector_scan_index <= 9'd0;
            collector_read_index <= 9'd0;
            collector_loading_seed <= 1'b0;
            collector_pass_added <= 1'b0;
            collector_closed_local <= 1'b0;
            collector_source_count <= 3'd0;
            collector_source_0 <= 9'd0;
            collector_source_1 <= 9'd0;
            collector_source_2 <= 9'd0;
            collector_source_3 <= 9'd0;
            collector_signature_valid <= 1'b0;
            collector_signature_0 <= 39'd0;
            component_candidate_count <= 32'd0;
            component_last_candidate_cell <= 9'd0;
            component_last_candidate_mines <= 32'd0;
            component_last_candidate_ways <= 32'd0;
            best_candidate_valid <= 1'b0;
            best_candidate_cell <= 9'd0;
            best_candidate_mines <= 13'd0;
            best_candidate_ways <= 13'd0;
            probability_guess_count <= 4'd0;
            rescue_step <= 3'd0;
`ifdef SIM_PROFILE
            profile_reveal_cycles <= 32'd0;
            profile_r123_cycles <= 32'd0;
            profile_r4_cycles <= 32'd0;
            profile_r5_cycles <= 32'd0;
            profile_collector_cycles <= 32'd0;
            profile_builder_cycles <= 32'd0;
            profile_enumeration_cycles <= 32'd0;
            profile_candidate_cycles <= 32'd0;
            profile_corner_cycles <= 32'd0;
            profile_other_cycles <= 32'd0;
            profile_component_attempts <= 32'd0;
            profile_component_completions <= 32'd0;
            profile_component_forced <= 32'd0;
            profile_component_closed <= 32'd0;
            profile_component_incomplete <= 32'd0;
            profile_component_duplicate_skips <= 32'd0;
            profile_enumeration_nodes <= 64'd0;
`endif
            opening_step <= 3'd1;
            board_generation <= 0;
            dirty_queue_max_depth <= 0;
            busy <= 0;
            done <= 0;
            stalled <= 0;
            protocol_error <= 0;
            selections_issued <= 0;
            observed_safe_count <= 0;
            observed_mine_count <= 0;
            known_mine_count <= 0;
            cycle_count <= 0;
        end else begin
            done <= 1'b0;
            ram_clear_start <= 1'b0;
            fifo_clear <= 1'b0;
            scan_start <= 1'b0;
            component_clear <= 1'b0;
            if (busy && run_enable)
                cycle_count <= cycle_count + 1'b1;
`ifdef SIM_PROFILE
            if (busy && run_enable) begin
                case (state)
                    S_ISSUE, S_WAIT, S_WAIT_DRAIN:
                        profile_reveal_cycles <=
                            profile_reveal_cycles + 1'b1;
                    S_SCAN_WAIT, S_POP_SAFE, S_POP_READ_ADDR,
                    S_POP_READ_WAIT, S_POP_CHECK, S_CHANGE_POP,
                    S_CHANGE_WALK, S_DIRTY_POP, S_DIRTY_READ_ADDR,
                    S_DIRTY_READ_WAIT, S_DIRTY_CHECK,
                    S_COMP_APPLY_ADDR, S_COMP_APPLY_WAIT, S_COMP_APPLY:
                        profile_r123_cycles <=
                            profile_r123_cycles + 1'b1;
                    S_R4_CHECK, S_R4_SCAN_ADDR, S_R4_SCAN_WAIT,
                    S_R4_SCAN_APPLY:
                        profile_r4_cycles <= profile_r4_cycles + 1'b1;
                    S_R5_STORE_WAIT, S_R5_INIT, S_R5_CANDIDATE,
                    S_R5_COMPARE, S_R5_APPLY_ADDR, S_R5_APPLY_WAIT,
                    S_R5_APPLY:
                        profile_r5_cycles <= profile_r5_cycles + 1'b1;
                    S_COLLECT_INIT, S_COLLECT_SEED,
                    S_COLLECT_READ_ADDR, S_COLLECT_READ_WAIT,
                    S_COLLECT_SCAN_NEXT:
                        profile_collector_cycles <=
                            profile_collector_cycles + 1'b1;
                    S_COMP_CLEAR, S_COMP_LOAD_A, S_COMP_LOAD_B,
                    S_COMP_SOLVE, S_COLLECT_LOAD, S_COLLECT_SOLVE:
                        profile_builder_cycles <=
                            profile_builder_cycles + 1'b1;
                    S_OPEN_NEXT, S_OPEN_READ_ADDR, S_OPEN_READ_WAIT,
                    S_OPEN_CHECK, S_RESCUE_NEXT, S_RESCUE_READ_ADDR,
                    S_RESCUE_READ_WAIT, S_RESCUE_CHECK:
                        profile_corner_cycles <=
                            profile_corner_cycles + 1'b1;
                    S_PROB_READ_ADDR, S_PROB_READ_WAIT, S_PROB_CHECK:
                        profile_candidate_cycles <=
                            profile_candidate_cycles + 1'b1;
                    S_COMP_WAIT: begin
                        if (component_profile_state == 4'd3 ||
                            component_profile_state == 4'd4 ||
                            component_profile_state == 4'd5)
                            profile_enumeration_cycles <=
                                profile_enumeration_cycles + 1'b1;
                        else if (component_profile_state == 4'd10 ||
                                 component_profile_state == 4'd11 ||
                                 component_profile_state == 4'd12)
                            profile_candidate_cycles <=
                                profile_candidate_cycles + 1'b1;
                        else
                            profile_builder_cycles <=
                                profile_builder_cycles + 1'b1;
                    end
                    default:
                        profile_other_cycles <=
                            profile_other_cycles + 1'b1;
                endcase
            end
`endif
            if (dirty_count > dirty_queue_max_depth)
                dirty_queue_max_depth <= dirty_count;

            if ((state == S_IDLE) || run_enable) begin
                case (state)
                    S_IDLE: begin
                        busy <= 1'b0;
                        if (start) begin
                            width <= board_width;
                            height <= board_height;
                            mines <= total_mines;
                            selections_issued <= 0;
                            observed_safe_count <= 0;
                            observed_mine_count <= 0;
                            known_mine_count <= 0;
                            unknown_count <= board_width * board_height;
                            remaining_mines <= total_mines;
                            queued_safe_count <= 0;
                            constraint_valid <= {MAX_CELLS{1'b0}};
                            r5_apply_mask <= 0;
                            r5_safe_count <= 0;
                            r5_mine_count <= 0;
                            constraint_rebuild_count <= 0;
                            constraint_compare_count <= 0;
                            derived_store_overflow_count <= 0;
                            component_pair_tried <= 1'b0;
                            component_safe_count <= 32'd0;
                            component_mine_count <= 32'd0;
                            component_collector_mode <= 1'b0;
                            collector_seed_index <= 9'd0;
                            collector_scan_index <= 9'd0;
                            collector_read_index <= 9'd0;
                            collector_loading_seed <= 1'b0;
                            collector_pass_added <= 1'b0;
                            collector_closed_local <= 1'b0;
                            collector_source_count <= 3'd0;
                            collector_signature_valid <= 1'b0;
                            component_candidate_count <= 32'd0;
                            best_candidate_valid <= 1'b0;
                            probability_guess_count <= 4'd0;
                            rescue_step <= 3'd0;
`ifdef SIM_PROFILE
                            profile_reveal_cycles <= 32'd0;
                            profile_r123_cycles <= 32'd0;
                            profile_r4_cycles <= 32'd0;
                            profile_r5_cycles <= 32'd0;
                            profile_collector_cycles <= 32'd0;
                            profile_builder_cycles <= 32'd0;
                            profile_enumeration_cycles <= 32'd0;
                            profile_candidate_cycles <= 32'd0;
                            profile_corner_cycles <= 32'd0;
                            profile_other_cycles <= 32'd0;
                            profile_component_attempts <= 32'd0;
                            profile_component_completions <= 32'd0;
                            profile_component_forced <= 32'd0;
                            profile_component_closed <= 32'd0;
                            profile_component_incomplete <= 32'd0;
                            profile_component_duplicate_skips <= 32'd0;
                            profile_enumeration_nodes <= 64'd0;
`endif
                            opening_step <= 3'd1;
                            board_generation <= board_generation + 1'b1;
                            dirty_queue_max_depth <= 0;
                            cycle_count <= 0;
                            stalled <= 0;
                            protocol_error <= 0;
                            reveal_pending <= 0;
                            busy <= 1'b1;
                            ram_clear_start <= 1'b1;
                            fifo_clear <= 1'b1;
                            if (board_width < 1 || board_width > MAX_WIDTH ||
                                board_height < 1 || board_height > MAX_HEIGHT ||
                                total_mines < 1 ||
                                total_mines >= board_width * board_height) begin
                                protocol_error <= 1'b1;
                                state <= S_ERROR;
                            end else state <= S_CLEAR;
                        end
                    end
                    S_CLEAR: begin
                        if (ram_clear_done) begin
                            active_x <= 0;
                            active_y <= 0;
                            state <= S_ISSUE;
                        end
                    end
                    S_ISSUE: begin
                        if (select_valid && select_ready) begin
                            selections_issued <= selections_issued + 1'b1;
                            state <= S_WAIT;
                        end
                    end
                    S_WAIT: begin
                        if (reveal_pending)
                            reveal_pending <= 1'b0;
                        if (reveal_valid) begin
                            reveal_pending <= 1'b1;
                            pending_reveal_index <= reveal_index;
                            pending_reveal_x <= reveal_x;
                            pending_reveal_y <= reveal_y;
                            pending_reveal_is_mine <= reveal_is_mine;
                            pending_reveal_clue <= reveal_clue;
                        end
                        if (select_rejected) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (cascade_done) begin
                            state <= S_WAIT_DRAIN;
                        end
                    end
                    S_WAIT_DRAIN: begin
                        // Finish the one-entry reveal pipeline before scanning.
                        // This permits one reveal event per clock while using a
                        // synchronous RAM read port for consistency checks.
                        if (reveal_valid) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (reveal_pending) begin
                            reveal_pending <= 1'b0;
                        end else if (observed_safe_count ==
                                     width * height - mines) begin
                            // The score is already complete, but R4 must still
                            // account for every remaining UNKNOWN as a mine.
                            state <= S_R4_CHECK;
                        end else if (fifo_pop_valid) begin
                            state <= S_POP_SAFE;
                        end else if (change_pop_valid) begin
                            state <= S_CHANGE_POP;
                        end else if (dirty_pop_valid) begin
                            state <= S_DIRTY_POP;
                        end else begin
                            state <= S_R4_CHECK;
                        end
                    end
                    S_SCAN_WAIT: begin
                        if (scan_done) begin
                            if (scan_contradiction || fifo_overflow ||
                                change_overflow || dirty_overflow) begin
                                protocol_error <= 1'b1;
                                state <= S_ERROR;
                            end else if (fifo_pop_valid) begin
                                state <= S_POP_SAFE;
                            end else if (change_pop_valid) begin
                                state <= S_CHANGE_POP;
                            end else if (dirty_pop_valid) begin
                                state <= S_DIRTY_POP;
                            end else begin
                                state <= S_R4_CHECK;
                            end
                        end
                    end
                    S_POP_SAFE: begin
                        if (fifo_pop_valid) begin
                            active_y <= fifo_pop_y;
                            active_x <= fifo_pop_x;
                            state <= S_POP_READ_ADDR;
                        end else begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end
                    end
                    S_POP_READ_ADDR: begin
                        state <= S_POP_READ_WAIT;
                    end
                    S_POP_READ_WAIT: begin
                        state <= S_POP_CHECK;
                    end
                    S_POP_CHECK: begin
                        if (ram_read_state == CELL_QUEUED_SAFE) begin
                            state <= S_ISSUE;
                        end else if (ram_read_state == CELL_OPEN_SAFE) begin
                            if (fifo_pop_valid) begin
                                state <= S_POP_SAFE;
                            end else if (change_pop_valid) begin
                                state <= S_CHANGE_POP;
                            end else if (dirty_pop_valid) begin
                                state <= S_DIRTY_POP;
                            end else begin
                                state <= S_R4_CHECK;
                            end
                        end else begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end
                    end
                    S_R4_CHECK: begin
                        if (fifo_pop_valid) begin
                            state <= S_POP_SAFE;
                        end else if (remaining_mines > unknown_count) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (unknown_count == 0) begin
                            state <= S_FINISH;
                        end else if (remaining_mines == 0) begin
                            r4_mode <= R4_ALL_SAFE;
                            scan_x <= 0;
                            scan_y <= 0;
                            state <= S_R4_SCAN_ADDR;
                        end else if (remaining_mines == unknown_count) begin
                            r4_mode <= R4_ALL_MINE;
                            scan_x <= 0;
                            scan_y <= 0;
                            state <= S_R4_SCAN_ADDR;
                        end else begin
                            state <= S_R5_INIT;
                        end
                    end
                    S_R4_SCAN_ADDR: begin
                        state <= S_R4_SCAN_WAIT;
                    end
                    S_R4_SCAN_WAIT: begin
                        state <= S_R4_SCAN_APPLY;
                    end
                    S_R4_SCAN_APPLY: begin
                        if (!r4_apply_unknown ||
                            (r4_mode == R4_ALL_MINE) || fifo_push_ready) begin
                            if (scan_last_cell) begin
                                if (r4_mode == R4_ALL_SAFE)
                                    state <= S_POP_SAFE;
                                else
                                    state <= S_FINISH;
                            end else begin
                                if (scan_x + 1'b1 == width) begin
                                    scan_x <= 0;
                                    scan_y <= scan_y + 1'b1;
                                end else scan_x <= scan_x + 1'b1;
                                state <= S_R4_SCAN_ADDR;
                            end
                        end
                    end
                    S_CHANGE_POP: begin
                        if (change_pop_valid) begin
                            changed_x <= change_pop_x;
                            changed_y <= change_pop_y;
                            changed_direction <= 0;
                            state <= S_CHANGE_WALK;
                        end else if (dirty_pop_valid) begin
                            state <= S_DIRTY_POP;
                        end else begin
                            state <= S_R4_CHECK;
                        end
                    end
                    S_CHANGE_WALK: begin
                        if (!changed_candidate_in_range ||
                            dirty_push_ready || dirty_push_duplicate) begin
                            if (changed_direction == 8) begin
                                if (change_pop_valid)
                                    state <= S_CHANGE_POP;
                                else
                                    state <= S_DIRTY_POP;
                            end else begin
                                changed_direction <= changed_direction + 1'b1;
                            end
                        end
                    end
                    S_DIRTY_POP: begin
                        if (dirty_pop_valid) begin
                            scan_x <= dirty_pop_x;
                            scan_y <= dirty_pop_y;
                            state <= S_DIRTY_READ_ADDR;
                        end else if (change_pop_valid) begin
                            state <= S_CHANGE_POP;
                        end else begin
                            state <= S_R4_CHECK;
                        end
                    end
                    S_DIRTY_READ_ADDR: begin
                        state <= S_DIRTY_READ_WAIT;
                    end
                    S_DIRTY_READ_WAIT: begin
                        state <= S_DIRTY_CHECK;
                    end
                    S_DIRTY_CHECK: begin
                        if (ram_read_state == CELL_OPEN_SAFE) begin
                            scan_clue <= ram_read_clue;
                            scan_start <= 1'b1;
                            state <= S_SCAN_WAIT;
                        end else if (fifo_pop_valid) begin
                            state <= S_POP_SAFE;
                        end else if (change_pop_valid) begin
                            state <= S_CHANGE_POP;
                        end else if (dirty_pop_valid) begin
                            state <= S_DIRTY_POP;
                        end else begin
                            state <= S_R4_CHECK;
                        end
                    end
                    S_R5_INIT: begin
                        r5_center_x <= 0;
                        r5_center_y <= 0;
                        r5_candidate_offset <= 0;
                        state <= S_R5_CANDIDATE;
                    end
                    S_R5_CANDIDATE: begin
                        if (r5_pair_available) begin
                            component_pair_tried <= 1'b0;
                            state <= S_R5_COMPARE;
                        end else if (r5_candidate_offset == 24) begin
                            r5_candidate_offset <= 0;
                            if (r5_center_x + 1'b1 == width) begin
                                r5_center_x <= 0;
                                if (r5_center_y + 1'b1 == height) begin
                                    state <= S_OPEN_NEXT;
                                end else begin
                                    r5_center_y <= r5_center_y + 1'b1;
                                end
                            end else begin
                                r5_center_x <= r5_center_x + 1'b1;
                            end
                        end else begin
                            r5_candidate_offset <= r5_candidate_offset + 1'b1;
                        end
                    end
                    S_R5_COMPARE: begin
                        constraint_compare_count <=
                            constraint_compare_count + 1'b1;
                        if (r5_compare_contradiction) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (!component_pair_tried &&
                                     !r5_compare_applicable) begin
                            component_pair_tried <= 1'b1;
                            component_collector_mode <= 1'b0;
                            component_clear <= 1'b1;
                            state <= S_COMP_CLEAR;
                        end else if (r5_compare_applicable) begin
                            r5_apply_mask <= r5_compare_difference_mask;
                            r5_apply_is_mine <= r5_compare_is_mine;
                            r5_apply_base_x <= r5_compare_base_x;
                            r5_apply_base_y <= r5_compare_base_y;
                            state <= S_R5_APPLY_ADDR;
                        end else if (r5_compare_derived_valid) begin
                            if (derived_store_ready)
                                state <= S_R5_STORE_WAIT;
                        end else if (r5_candidate_offset == 24) begin
                            r5_candidate_offset <= 0;
                            if (r5_center_x + 1'b1 == width) begin
                                r5_center_x <= 0;
                                if (r5_center_y + 1'b1 == height) begin
                                    state <= S_OPEN_NEXT;
                                end else begin
                                    r5_center_y <= r5_center_y + 1'b1;
                                    state <= S_R5_CANDIDATE;
                                end
                            end else begin
                                r5_center_x <= r5_center_x + 1'b1;
                                state <= S_R5_CANDIDATE;
                            end
                        end else begin
                            r5_candidate_offset <= r5_candidate_offset + 1'b1;
                            state <= S_R5_CANDIDATE;
                        end
                    end
                    S_R5_STORE_WAIT: begin
                        if (derived_store_done) begin
                            if (derived_store_contradiction) begin
                                protocol_error <= 1'b1;
                                state <= S_ERROR;
                            end else begin
                                if (derived_store_overflow)
                                    derived_store_overflow_count <=
                                        derived_store_overflow_count + 1'b1;
                                if (r5_candidate_offset == 24) begin
                                    r5_candidate_offset <= 0;
                                    if (r5_center_x + 1'b1 == width) begin
                                        r5_center_x <= 0;
                                        if (r5_center_y + 1'b1 == height) begin
                                            state <= S_OPEN_NEXT;
                                        end else begin
                                            r5_center_y <= r5_center_y + 1'b1;
                                            state <= S_R5_CANDIDATE;
                                        end
                                    end else begin
                                        r5_center_x <= r5_center_x + 1'b1;
                                        state <= S_R5_CANDIDATE;
                                    end
                                end else begin
                                    r5_candidate_offset <=
                                        r5_candidate_offset + 1'b1;
                                    state <= S_R5_CANDIDATE;
                                end
                            end
                        end
                    end
                    S_R5_APPLY_ADDR: begin
                        if (r5_apply_mask == 0 || !r5_apply_in_range) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else begin
                            state <= S_R5_APPLY_WAIT;
                        end
                    end
                    S_R5_APPLY_WAIT: begin
                        state <= S_R5_APPLY;
                    end
                    S_R5_APPLY: begin
                        if (!r5_apply_in_range ||
                            ram_read_state != CELL_UNKNOWN) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (r5_queues_ready) begin
                            r5_apply_mask <= r5_apply_mask &
                                             ~r5_apply_bit_mask;
                            if (r5_apply_last) begin
                                state <= S_CHANGE_POP;
                            end else begin
                                state <= S_R5_APPLY_ADDR;
                            end
                        end
                    end
                    S_COMP_CLEAR: begin
                        component_constraint_sent <= 1'b0;
                        component_changed <= 1'b0;
                        state <= S_COMP_LOAD_A;
                    end
                    S_COMP_LOAD_A: begin
                        if (component_error || component_overflow)
                            state <= S_R5_COMPARE;
                        else if (component_constraint_valid &&
                                 component_constraint_ready)
                            component_constraint_sent <= 1'b1;
                        else if (component_constraint_done) begin
                            component_constraint_sent <= 1'b0;
                            state <= S_COMP_LOAD_B;
                        end
                    end
                    S_COMP_LOAD_B: begin
                        if (component_error || component_overflow)
                            state <= S_R5_COMPARE;
                        else if (component_constraint_valid &&
                                 component_constraint_ready)
                            component_constraint_sent <= 1'b1;
                        else if (component_constraint_done) begin
                            component_constraint_sent <= 1'b0;
                            state <= S_COMP_SOLVE;
                        end
                    end
                    S_COMP_SOLVE: begin
                        if (component_error || component_overflow)
                            state <= S_R5_COMPARE;
                        else if (component_solve_ready)
                            state <= S_COMP_WAIT;
                    end
                    S_COMP_WAIT: begin
                        if (component_error || component_overflow) begin
                            if (component_collector_mode) begin
                                collector_seed_index <=
                                    collector_seed_index + 1'b1;
                                state <= S_COLLECT_SEED;
                            end else begin
                                state <= S_R5_COMPARE;
                            end
                        end else if (component_result_valid) begin
                            component_apply_index <= component_result_cell;
                            component_apply_is_mine <=
                                component_result_is_mine;
                            state <= S_COMP_APPLY_ADDR;
                        end else if (component_candidate_valid) begin
                            component_candidate_count <=
                                component_candidate_count + 1'b1;
                            component_last_candidate_cell <=
                                component_candidate_cell;
                            component_last_candidate_mines <=
                                component_candidate_mines;
                            component_last_candidate_ways <=
                                component_candidate_ways;
                            if (component_candidate_closed &&
                                component_candidate_better) begin
                                best_candidate_valid <= 1'b1;
                                best_candidate_cell <=
                                    component_candidate_cell;
                                best_candidate_mines <=
                                    component_candidate_mines[12:0];
                                best_candidate_ways <=
                                    component_candidate_ways[12:0];
                            end
                        end else if (component_done) begin
`ifdef SIM_PROFILE
                            if (component_collector_mode) begin
                                profile_component_completions <=
                                    profile_component_completions + 1'b1;
                                profile_enumeration_nodes <=
                                    profile_enumeration_nodes +
                                    component_enumeration_nodes;
                                if (component_changed)
                                    profile_component_forced <=
                                        profile_component_forced + 1'b1;
                                else if (collector_closed_local)
                                    profile_component_closed <=
                                        profile_component_closed + 1'b1;
                            end
`endif
                            if (component_changed)
                                state <= S_CHANGE_POP;
                            else if (component_collector_mode) begin
                                if (collector_closed_local) begin
                                    collector_signature_0 <=
                                        {collector_source_count,
                                         collector_source_3,
                                         collector_source_2,
                                         collector_source_1,
                                         collector_source_0};
                                    collector_signature_valid <= 1'b1;
                                end
                                collector_seed_index <=
                                    collector_seed_index + 1'b1;
                                state <= S_COLLECT_SEED;
                            end else
                                state <= S_R5_COMPARE;
                        end
                    end
                    S_COMP_APPLY_ADDR: begin
                        state <= S_COMP_APPLY_WAIT;
                    end
                    S_COMP_APPLY_WAIT: begin
                        state <= S_COMP_APPLY;
                    end
                    S_COMP_APPLY: begin
                        if (!component_apply_unknown &&
                            !component_apply_compatible) begin
                            protocol_error <= 1'b1;
                            state <= S_ERROR;
                        end else if (component_result_ready) begin
                            state <= S_COMP_WAIT;
                        end
                    end
                    S_OPEN_NEXT: begin
                        if (!ENABLE_CORNER_ON_STALL || opening_step >= 4) begin
                            if (ENABLE_CONSTRAINT_COLLECTOR)
                                state <= S_COLLECT_INIT;
                            else begin
                                stalled <= 1'b1;
                                state <= S_FINISH;
                            end
                        end else begin
                            case (opening_step)
                                1: begin
                                    active_x <= width - 1'b1;
                                    active_y <= 0;
                                end
                                2: begin
                                    active_x <= 0;
                                    active_y <= height - 1'b1;
                                end
                                default: begin
                                    active_x <= width - 1'b1;
                                    active_y <= height - 1'b1;
                                end
                            endcase
                            opening_step <= opening_step + 1'b1;
                            state <= S_OPEN_READ_ADDR;
                        end
                    end
                    S_OPEN_READ_ADDR: begin
                        state <= S_OPEN_READ_WAIT;
                    end
                    S_OPEN_READ_WAIT: begin
                        state <= S_OPEN_CHECK;
                    end
                    S_OPEN_CHECK: begin
                        if (ram_read_state == CELL_UNKNOWN)
                            state <= S_ISSUE;
                        else
                            state <= S_OPEN_NEXT;
                    end
                    S_COLLECT_INIT: begin
                        component_collector_mode <= 1'b1;
                        collector_seed_index <= 9'd0;
                        collector_signature_valid <= 1'b0;
                        best_candidate_valid <= 1'b0;
                        state <= S_COLLECT_SEED;
                    end
                    S_COLLECT_SEED: begin
                        component_changed <= 1'b0;
                        component_constraint_sent <= 1'b0;
                        if (collector_seed_index >= MAX_CELLS) begin
                            if (ENABLE_PROBABILITY_FEEDBACK &&
                                probability_feedback_allowed) begin
                                if (best_candidate_valid) begin
                                    active_x <= best_candidate_cell % 19;
                                    active_y <= best_candidate_cell / 19;
                                    state <= S_PROB_READ_ADDR;
                                end else begin
                                    if (ENABLE_LOW_SCORE_EDGE_RESCUE &&
                                        observed_safe_count <
                                            LOW_SCORE_RESCUE_SAFE_THRESHOLD &&
                                        rescue_step < 4)
                                        state <= S_RESCUE_NEXT;
                                    else begin
                                        stalled <= 1'b1;
                                        state <= S_FINISH;
                                    end
                                end
                            end else begin
                                stalled <= 1'b1;
                                state <= S_FINISH;
                            end
                        end else if (!constraint_valid[collector_seed_index] ||
                                     collector_seed_duplicate) begin
`ifdef SIM_PROFILE
                            if (constraint_valid[collector_seed_index] &&
                                collector_seed_duplicate)
                                profile_component_duplicate_skips <=
                                    profile_component_duplicate_skips + 1'b1;
`endif
                            collector_seed_index <=
                                collector_seed_index + 1'b1;
                        end else begin
`ifdef SIM_PROFILE
                            profile_component_attempts <=
                                profile_component_attempts + 1'b1;
`endif
                            component_clear <= 1'b1;
                            collector_read_index <= collector_seed_index;
                            collector_loading_seed <= 1'b1;
                            collector_pass_added <= 1'b0;
                            collector_closed_local <= 1'b1;
                            collector_source_count <= 3'd0;
                            state <= S_COLLECT_READ_ADDR;
                        end
                    end
                    S_COLLECT_READ_ADDR: begin
                        state <= S_COLLECT_READ_WAIT;
                    end
                    S_COLLECT_READ_WAIT: begin
                        state <= S_COLLECT_LOAD;
                    end
                    S_COLLECT_LOAD: begin
                        if (component_error || component_overflow) begin
                            collector_seed_index <=
                                collector_seed_index + 1'b1;
                            state <= S_COLLECT_SEED;
                        end else if (component_constraint_valid &&
                                     component_constraint_ready) begin
                            component_constraint_sent <= 1'b1;
                        end else if (component_constraint_done) begin
`ifdef SIM_PROFILE
                            if (component_constraint_incomplete_wire)
                                profile_component_incomplete <=
                                    profile_component_incomplete + 1'b1;
`endif
                            component_constraint_sent <= 1'b0;
                            if (component_constraint_added_wire &&
                                collector_source_count < 4) begin
                                case (collector_source_count)
                                    0: collector_source_0 <=
                                           collector_read_index;
                                    1: collector_source_1 <=
                                           collector_read_index;
                                    2: collector_source_2 <=
                                           collector_read_index;
                                    default: collector_source_3 <=
                                           collector_read_index;
                                endcase
                                collector_source_count <=
                                    collector_source_count + 1'b1;
                            end
                            if (collector_loading_seed) begin
                                collector_loading_seed <= 1'b0;
                                collector_scan_index <= 9'd0;
                                collector_pass_added <= 1'b0;
                            end else begin
                                if (component_constraint_added_wire)
                                    collector_pass_added <= 1'b1;
                                if (component_constraint_incomplete_wire)
                                    collector_closed_local <= 1'b0;
                                collector_scan_index <=
                                    collector_scan_index + 1'b1;
                            end
                            state <= S_COLLECT_SCAN_NEXT;
                        end
                    end
                    S_COLLECT_SCAN_NEXT: begin
                        if (collector_scan_index >= MAX_CELLS) begin
                            if (collector_pass_added) begin
                                collector_scan_index <= 9'd0;
                                collector_pass_added <= 1'b0;
                            end else begin
                                state <= S_COLLECT_SOLVE;
                            end
                        end else if (!collector_scan_found) begin
                            collector_scan_index <=
                                collector_scan_index + 2'd2;
                        end else begin
                            collector_scan_index <= collector_scan_selected;
                            collector_read_index <= collector_scan_selected;
                            state <= S_COLLECT_READ_ADDR;
                        end
                    end
                    S_COLLECT_SOLVE: begin
                        if (component_error || component_overflow) begin
                            collector_seed_index <=
                                collector_seed_index + 1'b1;
                            state <= S_COLLECT_SEED;
                        end else if (component_solve_ready) begin
                            state <= S_COMP_WAIT;
                        end
                    end
                    S_PROB_READ_ADDR: begin
                        state <= S_PROB_READ_WAIT;
                    end
                    S_PROB_READ_WAIT: begin
                        state <= S_PROB_CHECK;
                    end
                    S_PROB_CHECK: begin
                        if (ram_read_state == CELL_UNKNOWN) begin
                            if (probability_guess_count != 4'hf)
                                probability_guess_count <=
                                    probability_guess_count + 1'b1;
                            state <= S_ISSUE;
                        end else begin
                            stalled <= 1'b1;
                            state <= S_FINISH;
                        end
                    end
                    S_RESCUE_NEXT: begin
                        case (rescue_step)
                            0: begin
                                active_x <= width >> 1;
                                active_y <= 0;
                            end
                            1: begin
                                active_x <= width >> 1;
                                active_y <= height - 1'b1;
                            end
                            2: begin
                                active_x <= 0;
                                active_y <= height >> 1;
                            end
                            default: begin
                                active_x <= width - 1'b1;
                                active_y <= height >> 1;
                            end
                        endcase
                        rescue_step <= rescue_step + 1'b1;
                        state <= S_RESCUE_READ_ADDR;
                    end
                    S_RESCUE_READ_ADDR: begin
                        state <= S_RESCUE_READ_WAIT;
                    end
                    S_RESCUE_READ_WAIT: begin
                        state <= S_RESCUE_CHECK;
                    end
                    S_RESCUE_CHECK: begin
                        if (ram_read_state == CELL_UNKNOWN) begin
                            state <= S_ISSUE;
                        end else if (rescue_step < 4) begin
                            state <= S_RESCUE_NEXT;
                        end else begin
                            stalled <= 1'b1;
                            state <= S_FINISH;
                        end
                    end
                    S_FINISH: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= S_IDLE;
                    end
                    S_ERROR: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= S_IDLE;
                    end
                    default: begin
                        protocol_error <= 1'b1;
                        state <= S_ERROR;
                    end
                endcase
            end

            if (ram_write_from_reveal) begin
                if (ram_read_state == CELL_UNKNOWN)
                    unknown_count <= unknown_count - 1'b1;
                else if (ram_read_state == CELL_QUEUED_SAFE)
                    queued_safe_count <= queued_safe_count - 1'b1;
                else if (ram_read_state == CELL_KNOWN_MINE)
                    known_mine_count <= known_mine_count - 1'b1;

                if (pending_reveal_is_mine) begin
                    observed_mine_count <= observed_mine_count + 1'b1;
                    if (ram_read_state == CELL_UNKNOWN)
                        remaining_mines <= remaining_mines - 1'b1;
                end else
                    observed_safe_count <= observed_safe_count + 1'b1;
            end else if (reveal_pending &&
                         ((state == S_WAIT) || (state == S_WAIT_DRAIN)) &&
                         run_enable && !reveal_transition_valid) begin
                protocol_error <= 1'b1;
                state <= S_ERROR;
            end

            if (ram_write_from_scan) begin
                unknown_count <= unknown_count - 1'b1;
                if (scan_result_state == CELL_QUEUED_SAFE)
                    queued_safe_count <= queued_safe_count + 1'b1;
                else begin
                    known_mine_count <= known_mine_count + 1'b1;
                    remaining_mines <= remaining_mines - 1'b1;
                end
            end else if ((state == S_SCAN_WAIT) && scan_result_valid &&
                         scan_result_ready && !scan_counter_valid) begin
                protocol_error <= 1'b1;
                state <= S_ERROR;
            end

            if (ram_write_from_r4) begin
                unknown_count <= unknown_count - 1'b1;
                if (r4_mode == R4_ALL_SAFE)
                    queued_safe_count <= queued_safe_count + 1'b1;
                else begin
                    known_mine_count <= known_mine_count + 1'b1;
                    remaining_mines <= remaining_mines - 1'b1;
                end
            end

            if (state == S_SCAN_WAIT && scan_done &&
                !scan_contradiction) begin
                constraint_valid[scan_cell_index] <=
                    scan_constraint_count != 0;
                constraint_rebuild_count <= constraint_rebuild_count + 1'b1;
            end else if (state == S_DIRTY_CHECK &&
                         ram_read_state != CELL_OPEN_SAFE) begin
                constraint_valid[scan_cell_index] <= 1'b0;
            end

            if (ram_write_from_r5) begin
                unknown_count <= unknown_count - 1'b1;
                if (r5_apply_is_mine) begin
                    known_mine_count <= known_mine_count + 1'b1;
                    remaining_mines <= remaining_mines - 1'b1;
                    r5_mine_count <= r5_mine_count + 1'b1;
                end else begin
                    queued_safe_count <= queued_safe_count + 1'b1;
                    r5_safe_count <= r5_safe_count + 1'b1;
                end
            end

            if (ram_write_from_component) begin
                component_changed <= 1'b1;
                unknown_count <= unknown_count - 1'b1;
                if (component_apply_is_mine) begin
                    known_mine_count <= known_mine_count + 1'b1;
                    remaining_mines <= remaining_mines - 1'b1;
                    component_mine_count <= component_mine_count + 1'b1;
                end else begin
                    queued_safe_count <= queued_safe_count + 1'b1;
                    component_safe_count <= component_safe_count + 1'b1;
                end
            end
        end
    end
endmodule
