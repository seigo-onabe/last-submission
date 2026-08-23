`timescale 1ns/1ps

// Questa/Icarus-compatible file runner for the official contest text format.
// Usage: vvp ... +BOARD_FILE=pack.txt +RESULT_CSV=result.csv
//              +START_BOARD=0 +MAX_BOARDS=1000
module tb_official_board_file #(
    parameter DETERMINISTIC_SOLVER = 0,
    parameter MAX_PROBABILITY_GUESSES = 4,
    parameter ENABLE_ADAPTIVE_FEEDBACK = 0,
    parameter ENABLE_SATURATING_HALF_SAFE_FEEDBACK = 0,
    parameter BASE_PROBABILITY_GUESSES = 8,
    parameter ADAPTIVE_FEEDBACK_SAFE_THRESHOLD = 32,
    parameter ENABLE_GLOBAL_CONDITIONING = 0,
    parameter ENABLE_LOW_SCORE_EDGE_RESCUE = 0,
    parameter LOW_SCORE_RESCUE_SAFE_THRESHOLD = 16
);
    reg clk = 0;
    reg reset = 1;
    reg [3:0] speed_setting = 4'hF;
`ifdef SIM_PROFILE
    reg [4:0] previous_solver_state;
    always @(posedge clk)
        previous_solver_state <= dut.g_deterministic.u_core.u_solver.state;
`endif
    wire cfg_valid;
    wire cfg_ready;
    wire [4:0] cfg_width;
    wire [4:0] cfg_height;
    wire [8:0] cfg_total_mines;
    wire load_valid;
    wire load_ready;
    wire [8:0] load_index;
    wire [3:0] load_value;
    wire start_solver;
    reg begin_valid = 0;
    wire begin_ready;
    reg [15:0] begin_board_id = 0;
    reg [4:0] begin_width = 0;
    reg [4:0] begin_height = 0;
    reg [8:0] begin_mines = 0;
    reg cell_valid = 0;
    wire cell_ready;
    reg [8:0] cell_ordinal = 0;
    reg [3:0] cell_value = 0;
    reg commit_valid = 0;
    wire commit_ready;
    wire solver_busy, solver_done, result_valid, protocol_error;
    wire [15:0] boards_processed, boards_fully_solved;
    wire signed [31:0] current_score_scaled, total_score_scaled;
    wire [8:0] current_safe, current_mines;
    wire [8:0] current_selections;
    wire solver_stalled;
    wire [31:0] current_cycles;
    wire [63:0] total_cycles;
    wire stream_done, stream_error;
    wire [15:0] active_board_id;
    reg result_ack = 0;
    wire snapshot_available;
    wire [15:0] snapshot_board_id;
    wire [4:0] snapshot_width, snapshot_height;
    wire [8:0] snapshot_total_mines;
    wire [8:0] snapshot_selections;
    wire snapshot_stalled;
    wire [8:0] snapshot_safe, snapshot_mines;
    wire [31:0] snapshot_cycles;
    wire signed [31:0] snapshot_score_scaled;
    wire snapshot_protocol_error, snapshot_overflow;
    wire [7:0] SEG_A,SEG_B,SEG_C,SEG_D,SEG_E,SEG_F,SEG_G,SEG_H;
    wire [8:0] SEG_SEL;
    wire debug_game_error;
    wire debug_solver_error;

    generate
        if (DETERMINISTIC_SOLVER) begin : g_debug_deterministic
            assign debug_game_error = dut.g_deterministic.u_core.game_error;
            assign debug_solver_error = dut.g_deterministic.u_core.solver_error;
        end else begin : g_debug_four_corners
            assign debug_game_error = dut.g_four_corners.u_core.game_error;
            assign debug_solver_error = dut.g_four_corners.u_core.solver_error;
        end
    endgenerate

    reg [8*1024-1:0] board_file;
    reg [8*1024-1:0] result_file;
`ifdef SIM_PROFILE
    reg [8*1024-1:0] profile_event_file;
    integer profile_event_fd;
    reg [8*1024-1:0] frontier_event_file;
    integer frontier_event_fd;
`endif
    reg [8*256-1:0] board_name;
    integer input_fd, result_fd, scan_count;
    integer width_i, height_i, mines_i, cell_i;
    integer x, y, board_limit, board_start, board_number, processed_count;
    longint unsigned elapsed_cycles;
    longint unsigned board_begin_cycle, cfg_end_cycle, load_end_cycle;
    longint unsigned solver_begin_cycle, solver_end_cycle, result_end_cycle;
    longint signed score_numerator, score_denominator, score_scaled_at_output;
    real score_real;

`ifdef SIM_PROFILE
    generate
        if (DETERMINISTIC_SOLVER) begin : g_component_profile
            integer variable_index;
            integer mine_bucket;
            integer frontier_x;
            integer frontier_y;
            integer frontier_nx;
            integer frontier_ny;
            integer frontier_index;
            integer frontier_neighbor_index;
            integer frontier_count;
            integer nonfrontier_count;
            integer nonfrontier_cell;
            integer frontier_touch;
            integer component_expected_mine_ways;
            reg [8*1024-1:0] global_override_file;
            integer global_override_fd;
            integer global_override_scan;
            integer global_override_index;
            integer global_override_cell [0:360];
            integer global_override_original [0:360];
            integer profile_local_candidate;
            integer global_override_count;
            initial begin
                global_override_count = 0;
                for (global_override_index = 0;
                     global_override_index < 361;
                     global_override_index = global_override_index + 1)
                    global_override_original[global_override_index] = -1;
                if ($value$plusargs("GLOBAL_OVERRIDE_FILE=%s",
                                   global_override_file)) begin
                    global_override_fd = $fopen(global_override_file, "r");
                    if (global_override_fd == 0) begin
                        $display("ERROR: cannot open override file %0s",
                                 global_override_file);
                        $finish(2);
                    end
                    while (!$feof(global_override_fd) &&
                           global_override_count < 361) begin
                        global_override_scan = $fscanf(
                            global_override_fd, "%d\n",
                            global_override_cell[global_override_count]);
                        if (global_override_scan == 1)
                            global_override_count = global_override_count + 1;
                    end
                    $fclose(global_override_fd);
                end
            end
            // A single-board simulation may replay an oracle-selected prefix.
            // Deposit the candidate on the falling edge before the solver
            // consumes it; production RTL and non-profile simulations are
            // unaffected.
            always @(negedge clk) begin
                if (!reset &&
                    dut.g_deterministic.u_core.u_solver.state == 6'd44 &&
                    dut.g_deterministic.u_core.u_solver.collector_seed_index >=
                        9'd361 &&
                    dut.g_deterministic.u_core.u_solver.best_candidate_valid &&
                    dut.g_deterministic.u_core.u_solver.probability_guess_count <
                        global_override_count) begin
                    global_override_original[
                        dut.g_deterministic.u_core.u_solver.probability_guess_count] =
                        dut.g_deterministic.u_core.u_solver.best_candidate_cell;
                    dut.g_deterministic.u_core.u_solver.best_candidate_cell =
                        global_override_cell[
                            dut.g_deterministic.u_core.u_solver.probability_guess_count];
                end
            end
            always @(posedge clk) begin
                if (!reset && profile_event_fd != 0 &&
                    dut.g_deterministic.u_core.u_solver.component_done &&
                    dut.g_deterministic.u_core.u_solver.component_collector_mode) begin
                    component_expected_mine_ways = 0;
                    for (variable_index = 0;
                         variable_index <
                            dut.g_deterministic.u_core.u_solver.component_variable_count;
                         variable_index = variable_index + 1)
                        component_expected_mine_ways =
                            component_expected_mine_ways +
                            dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.u_enumerator.mine_total[variable_index];
                    $fwrite(profile_event_fd,
                        "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                        board_number + 1,
                        dut.g_deterministic.u_core.u_solver.probability_guess_count + 1,
                        dut.g_deterministic.u_core.u_solver.collector_seed_index,
                        dut.g_deterministic.u_core.u_solver.component_variable_count,
                        dut.g_deterministic.u_core.u_solver.component_constraint_count,
                        dut.g_deterministic.u_core.u_solver.component_total_ways,
                        dut.g_deterministic.u_core.u_solver.component_enumeration_nodes,
                        dut.g_deterministic.u_core.u_solver.collector_closed_local,
                        dut.g_deterministic.u_core.u_solver.component_changed,
                        dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.candidate_cell,
                        dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.candidate_mine_ways,
                        dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.candidate_total_ways,
                        component_expected_mine_ways);
                    for (variable_index = 0; variable_index < 12;
                         variable_index = variable_index + 1) begin
                        if (variable_index <
                            dut.g_deterministic.u_core.u_solver.component_variable_count)
                            $fwrite(profile_event_fd, ",%0d",
                                dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.u_builder.variable_cells[variable_index]);
                        else
                            $fwrite(profile_event_fd, ",-1");
                    end
                    for (variable_index = 0; variable_index < 13;
                         variable_index = variable_index + 1)
                        $fwrite(profile_event_fd, ",%0d",
                            dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.u_enumerator.ways_by_mines[variable_index]);
                    $fwrite(profile_event_fd, ",%0d,",
                        dut.g_deterministic.u_core.u_solver.board_generation);
                    for (variable_index = 0; variable_index < 12;
                         variable_index = variable_index + 1) begin
                        if (variable_index != 0)
                            $fwrite(profile_event_fd, ";");
                        for (mine_bucket = 0; mine_bucket < 13;
                             mine_bucket = mine_bucket + 1) begin
                            if (mine_bucket != 0)
                                $fwrite(profile_event_fd, "|");
                            $fwrite(profile_event_fd, "%0d",
                                dut.g_deterministic.u_core.u_solver.u_small_component_pipeline.u_enumerator.mine_ways[variable_index * 13 + mine_bucket]);
                        end
                    end
                    $fwrite(profile_event_fd, "\n");
                end
                if (!reset && frontier_event_fd != 0 &&
                    dut.g_deterministic.u_core.u_solver.state == 6'd50) begin
                    if (dut.g_deterministic.u_core.u_solver.probability_guess_count <
                        global_override_count)
                        profile_local_candidate = global_override_original[
                            dut.g_deterministic.u_core.u_solver.probability_guess_count];
                    else
                        profile_local_candidate =
                            dut.g_deterministic.u_core.u_solver.best_candidate_cell;
                    frontier_count = 0;
                    nonfrontier_count = 0;
                    nonfrontier_cell = -1;
                    for (frontier_y = 0;
                         frontier_y < dut.g_deterministic.u_core.u_solver.height;
                         frontier_y = frontier_y + 1) begin
                        for (frontier_x = 0;
                             frontier_x < dut.g_deterministic.u_core.u_solver.width;
                             frontier_x = frontier_x + 1) begin
                            frontier_index = frontier_y * 19 + frontier_x;
                            if (dut.g_deterministic.u_core.u_solver.u_state_ram.knowledge_mem[frontier_index][2:0] == 3'd0) begin
                                frontier_touch = 0;
                                for (frontier_ny = frontier_y - 1;
                                     frontier_ny <= frontier_y + 1;
                                     frontier_ny = frontier_ny + 1) begin
                                    for (frontier_nx = frontier_x - 1;
                                         frontier_nx <= frontier_x + 1;
                                         frontier_nx = frontier_nx + 1) begin
                                        if (frontier_nx >= 0 && frontier_ny >= 0 &&
                                            frontier_nx < dut.g_deterministic.u_core.u_solver.width &&
                                            frontier_ny < dut.g_deterministic.u_core.u_solver.height &&
                                            !(frontier_nx == frontier_x &&
                                              frontier_ny == frontier_y)) begin
                                            frontier_neighbor_index =
                                                frontier_ny * 19 + frontier_nx;
                                            if (dut.g_deterministic.u_core.u_solver.constraint_valid[frontier_neighbor_index])
                                                frontier_touch = 1;
                                        end
                                    end
                                end
                                if (frontier_touch != 0)
                                    frontier_count = frontier_count + 1;
                                else begin
                                    if (nonfrontier_count == 0)
                                        nonfrontier_cell = frontier_index;
                                    nonfrontier_count = nonfrontier_count + 1;
                                end
                            end
                        end
                    end
                    $fdisplay(frontier_event_fd,
                        "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                        board_number + 1,
                        dut.g_deterministic.u_core.u_solver.probability_guess_count + 1,
                        dut.g_deterministic.u_core.u_solver.unknown_count,
                        dut.g_deterministic.u_core.u_solver.remaining_mines,
                        frontier_count, nonfrontier_count,
                        profile_local_candidate,
                        dut.g_deterministic.u_core.u_solver.best_candidate_mines,
                        dut.g_deterministic.u_core.u_solver.best_candidate_ways,
                        dut.g_deterministic.u_core.u_solver.active_cell_index,
                        nonfrontier_cell,
                        dut.g_deterministic.u_core.u_solver.board_generation);
                end
            end
        end
    endgenerate
`endif

    always #25 clk = ~clk;
    always @(posedge clk) begin
        if (reset)
            elapsed_cycles <= 0;
        else
            elapsed_cycles <= elapsed_cycles + 1;
    end

    minesweeper_mu500_system #(
        .DETERMINISTIC_SOLVER(DETERMINISTIC_SOLVER),
        .MAX_PROBABILITY_GUESSES(MAX_PROBABILITY_GUESSES),
        .ENABLE_ADAPTIVE_FEEDBACK(ENABLE_ADAPTIVE_FEEDBACK),
        .ENABLE_SATURATING_HALF_SAFE_FEEDBACK(
            ENABLE_SATURATING_HALF_SAFE_FEEDBACK),
        .BASE_PROBABILITY_GUESSES(BASE_PROBABILITY_GUESSES),
        .ADAPTIVE_FEEDBACK_SAFE_THRESHOLD(
            ADAPTIVE_FEEDBACK_SAFE_THRESHOLD),
        .ENABLE_GLOBAL_CONDITIONING(ENABLE_GLOBAL_CONDITIONING),
        .ENABLE_LOW_SCORE_EDGE_RESCUE(ENABLE_LOW_SCORE_EDGE_RESCUE),
        .LOW_SCORE_RESCUE_SAFE_THRESHOLD(LOW_SCORE_RESCUE_SAFE_THRESHOLD)
    ) dut (
        .clk(clk), .reset(reset), .speed_setting(speed_setting),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_total_mines(cfg_total_mines),
        .load_valid(load_valid), .load_ready(load_ready),
        .load_index(load_index), .load_value(load_value),
        .start_solver(start_solver), .solver_busy(solver_busy),
        .solver_done(solver_done), .solver_stalled(solver_stalled),
        .result_valid(result_valid),
        .protocol_error(protocol_error),
        .boards_processed(boards_processed),
        .boards_fully_solved(boards_fully_solved),
        .current_score_scaled(current_score_scaled),
        .total_score_scaled(total_score_scaled),
        .current_safe(current_safe), .current_mines(current_mines),
        .current_selections(current_selections),
        .current_cycles(current_cycles), .total_cycles(total_cycles),
        .SEG_A(SEG_A),.SEG_B(SEG_B),.SEG_C(SEG_C),.SEG_D(SEG_D),
        .SEG_E(SEG_E),.SEG_F(SEG_F),.SEG_G(SEG_G),.SEG_H(SEG_H),
        .SEG_SEL(SEG_SEL)
    );

    board_stream_controller stream (
        .clk(clk), .reset(reset),
        .begin_valid(begin_valid), .begin_ready(begin_ready),
        .begin_board_id(begin_board_id), .begin_width(begin_width),
        .begin_height(begin_height), .begin_mines(begin_mines),
        .cell_valid(cell_valid), .cell_ready(cell_ready),
        .cell_ordinal(cell_ordinal), .cell_value(cell_value),
        .commit_valid(commit_valid), .commit_ready(commit_ready),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_total_mines(cfg_total_mines),
        .load_valid(load_valid), .load_ready(load_ready),
        .load_index(load_index), .load_value(load_value),
        .start_solver(start_solver), .result_valid(result_valid),
        .board_done(stream_done), .active_board_id(active_board_id),
        .protocol_error(stream_error)
    );

    result_snapshot snapshot (
        .clk(clk), .reset(reset), .capture(result_valid),
        .board_id(active_board_id), .width(cfg_width), .height(cfg_height),
        .total_mines(cfg_total_mines), .selections(current_selections),
        .stalled(solver_stalled),
        .opened_safe(current_safe), .opened_mines(current_mines),
        .cycles(current_cycles), .score_scaled(current_score_scaled),
        .protocol_error_in(protocol_error | stream_error),
        .acknowledge(result_ack), .available(snapshot_available),
        .result_board_id(snapshot_board_id), .result_width(snapshot_width),
        .result_height(snapshot_height),
        .result_total_mines(snapshot_total_mines),
        .result_selections(snapshot_selections),
        .result_stalled(snapshot_stalled),
        .result_opened_safe(snapshot_safe), .result_opened_mines(snapshot_mines),
        .result_cycles(snapshot_cycles),
        .result_score_scaled(snapshot_score_scaled),
        .result_protocol_error(snapshot_protocol_error),
        .overflow_error(snapshot_overflow)
    );

    initial begin
        if (!$value$plusargs("BOARD_FILE=%s", board_file)) begin
            $display("ERROR: +BOARD_FILE=<official-format.txt> is required");
            $finish(2);
        end
        if (!$value$plusargs("RESULT_CSV=%s", result_file))
            result_file = "minesweeper_results.csv";
        if (!$value$plusargs("MAX_BOARDS=%d", board_limit))
            board_limit = 2147483647;
        if (!$value$plusargs("START_BOARD=%d", board_start))
            board_start = 0;
        if (board_start < 0 || board_limit < 0) begin
            $display("ERROR: START_BOARD and MAX_BOARDS must be non-negative");
            $finish(2);
        end
`ifdef SIM_PROFILE
        profile_event_fd = 0;
        frontier_event_fd = 0;
        if ($value$plusargs("PROFILE_EVENT_CSV=%s", profile_event_file)) begin
            profile_event_fd = $fopen(profile_event_file, "w");
            if (profile_event_fd == 0) begin
                $display("ERROR: could not open profile event file");
                $finish(2);
            end
            $fdisplay(profile_event_fd,
                "board_index,guess_index,seed_index,variable_count,constraint_count,total_ways,enumeration_nodes,closed,forced,candidate_cell,candidate_mine_ways,candidate_total_ways,component_expected_mine_ways,var0,var1,var2,var3,var4,var5,var6,var7,var8,var9,var10,var11,ways_m0,ways_m1,ways_m2,ways_m3,ways_m4,ways_m5,ways_m6,ways_m7,ways_m8,ways_m9,ways_m10,ways_m11,ways_m12,generation,mine_ways_matrix");
        end
        if ($value$plusargs("FRONTIER_EVENT_CSV=%s", frontier_event_file)) begin
            frontier_event_fd = $fopen(frontier_event_file, "w");
            if (frontier_event_fd == 0) begin
                $display("ERROR: could not open frontier event file");
                $finish(2);
            end
            $fdisplay(frontier_event_fd,
                "board_index,guess_index,unknown_count,remaining_mines,frontier_count,nonfrontier_count,local_candidate_cell,local_mine_ways,local_total_ways,selected_cell,nonfrontier_cell,generation");
        end
`endif

        input_fd = $fopen(board_file, "r");
        result_fd = $fopen(result_file, "w");
        if (input_fd == 0 || result_fd == 0) begin
            $display("ERROR: could not open input or output file");
            $finish(2);
        end
        if (DETERMINISTIC_SOLVER)
`ifdef SIM_PROFILE
            $fdisplay(result_fd,
              "board_index,board_name,width,height,total_mines,selections,opened_safe,opened_mines,cycles,cfg_cycles,load_cycles,solver_cycles,score_cycles,total_board_cycles,score_numerator,score_denominator,score_scaled,score,solver_stalled,profile_reveal,profile_r123,profile_r4,profile_r5,profile_collector,profile_builder,profile_enumeration,profile_candidate,profile_corner,profile_other,component_attempts,component_completions,component_forced,component_closed,component_incomplete,component_duplicate_skips,enumeration_nodes");
`else
            $fdisplay(result_fd,
              "board_index,board_name,width,height,total_mines,selections,opened_safe,opened_mines,cycles,cfg_cycles,load_cycles,solver_cycles,score_cycles,total_board_cycles,score_numerator,score_denominator,score_scaled,score,solver_stalled");
`endif
        else
            $fdisplay(result_fd,
              "board_index,board_name,width,height,total_mines,selections,opened_safe,opened_mines,cycles,cfg_cycles,load_cycles,solver_cycles,score_cycles,total_board_cycles,score_numerator,score_denominator,score_scaled,score");

        repeat (4) @(negedge clk);
        reset = 0;
        board_number = 0;
        processed_count = 0;

        while (!$feof(input_fd) && processed_count < board_limit) begin
            board_name = 0;
            scan_count = $fscanf(input_fd, "%d %d %d %s",
                                  width_i, height_i, mines_i, board_name);
            if (scan_count == 4) begin
                board_begin_cycle = elapsed_cycles;
                if (width_i < 1 || width_i > 19 ||
                    height_i < 1 || height_i > 19 ||
                    mines_i < 1 || mines_i >= width_i*height_i) begin
                    $display("ERROR: invalid header at board %0d", board_number+1);
                    $finish(3);
                end

                if (board_number < board_start) begin
                    for (y=0; y<height_i; y=y+1) begin
                        for (x=0; x<width_i; x=x+1) begin
                            scan_count = $fscanf(input_fd, "%1d", cell_i);
                            if (scan_count != 1 || cell_i < 0 || cell_i > 9) begin
                                $display("ERROR: invalid skipped cell at board %0d (%0d,%0d)",
                                         board_number+1, x, y);
                                $finish(3);
                            end
                        end
                    end
                    board_number = board_number + 1;
                end else begin
                @(negedge clk);
                begin_board_id = board_number + 1;
                begin_width = width_i;
                begin_height = height_i;
                begin_mines = mines_i;
                begin_valid = 1;
                while (!begin_ready) @(negedge clk);
                @(negedge clk);
                begin_valid = 0;
                while (!cell_ready) @(negedge clk);
                cfg_end_cycle = elapsed_cycles;

                for (y=0; y<height_i; y=y+1) begin
                    for (x=0; x<width_i; x=x+1) begin
                        scan_count = $fscanf(input_fd, "%1d", cell_i);
                        if (scan_count != 1 || cell_i < 0 || cell_i > 9) begin
                            $display("ERROR: invalid cell at board %0d (%0d,%0d)",
                                     board_number+1, x, y);
                            $finish(3);
                        end
                        cell_ordinal = y*width_i+x;
                        cell_value = cell_i;
                        cell_valid = 1;
                        while (!cell_ready) @(negedge clk);
                        @(negedge clk);
                    end
                end
                cell_valid = 0;
                while (!commit_ready) @(negedge clk);
                load_end_cycle = elapsed_cycles;
                commit_valid = 1;
                @(negedge clk);
                commit_valid = 0;
                @(negedge clk);
                solver_begin_cycle = elapsed_cycles;

                while (!solver_done) begin
                    @(negedge clk);
                    if (protocol_error) begin
                        $display("ERROR: solver protocol failure at board %0d core=%0d metrics=%0d game=%0d solver=%0d",
                                 board_number+1, dut.core_error, dut.metrics_error,
                                 debug_game_error, debug_solver_error);
`ifdef SIM_PROFILE
                        if (DETERMINISTIC_SOLVER)
                            $display("PROFILE ERROR: previous_state=%0d state=%0d active=%0d,%0d unknown=%0d remaining=%0d reveal_pending=%0d reveal_valid=%0d scan_valid=%0d scan_ready=%0d",
                                previous_solver_state,
                                dut.g_deterministic.u_core.u_solver.state,
                                dut.g_deterministic.u_core.u_solver.active_x,
                                dut.g_deterministic.u_core.u_solver.active_y,
                                dut.g_deterministic.u_core.u_solver.unknown_count,
                                dut.g_deterministic.u_core.u_solver.remaining_mines,
                                dut.g_deterministic.u_core.u_solver.reveal_pending,
                                dut.g_deterministic.u_core.u_solver.reveal_valid,
                                dut.g_deterministic.u_core.u_solver.scan_result_valid,
                                dut.g_deterministic.u_core.u_solver.scan_result_ready);
`endif
                        $finish(4);
                    end
                end
                solver_end_cycle = elapsed_cycles;
                while (!result_valid) begin
                    @(negedge clk);
                    if (protocol_error) begin
                        $display("ERROR: metrics protocol failure at board %0d", board_number+1);
                        $finish(4);
                    end
                end
                result_end_cycle = elapsed_cycles;
                while (!snapshot_available) @(negedge clk);
                if (snapshot_board_id != board_number + 1 ||
                    snapshot_width != width_i || snapshot_height != height_i ||
                    snapshot_total_mines != mines_i || snapshot_protocol_error ||
                    snapshot_overflow) begin
                    $display("ERROR: result snapshot mismatch at board %0d", board_number+1);
                    $finish(4);
                end

                // Keep the score exact as an integer rational until the CSV
                // boundary.  Signed division truncates toward zero.
                score_numerator = $signed({1'b0, snapshot_safe}) * mines_i -
                                  $signed({1'b0, snapshot_mines}) *
                                  (width_i * height_i - mines_i);
                score_denominator = (width_i * height_i - mines_i) * mines_i;
                score_scaled_at_output = (score_numerator * 10000) /
                                         score_denominator;
                if (score_scaled_at_output != $signed(snapshot_score_scaled)) begin
                    $display("ERROR: score mismatch at board %0d: csv=%0d rtl=%0d safe=%0d opened_mines=%0d total_mines=%0d size=%0dx%0d",
                             board_number+1, score_scaled_at_output,
                             $signed(snapshot_score_scaled), snapshot_safe,
                             snapshot_mines, mines_i, width_i, height_i);
                    $finish(5);
                end
                board_number = board_number + 1;
                processed_count = processed_count + 1;
                score_real = $itor(score_scaled_at_output) / 10000.0;
                if (DETERMINISTIC_SOLVER)
`ifdef SIM_PROFILE
                    $fdisplay(result_fd,
                        "%0d,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                        board_number, board_name, width_i, height_i, mines_i,
                        snapshot_selections, snapshot_safe, snapshot_mines,
                        snapshot_cycles,
                        cfg_end_cycle - board_begin_cycle,
                        load_end_cycle - cfg_end_cycle,
                        solver_end_cycle - solver_begin_cycle,
                        result_end_cycle - solver_end_cycle,
                        result_end_cycle - board_begin_cycle,
                        score_numerator, score_denominator,
                        score_scaled_at_output, score_real, snapshot_stalled,
                        dut.g_deterministic.u_core.u_solver.profile_reveal_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_r123_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_r4_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_r5_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_collector_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_builder_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_enumeration_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_candidate_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_corner_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_other_cycles,
                        dut.g_deterministic.u_core.u_solver.profile_component_attempts,
                        dut.g_deterministic.u_core.u_solver.profile_component_completions,
                        dut.g_deterministic.u_core.u_solver.profile_component_forced,
                        dut.g_deterministic.u_core.u_solver.profile_component_closed,
                        dut.g_deterministic.u_core.u_solver.profile_component_incomplete,
                        dut.g_deterministic.u_core.u_solver.profile_component_duplicate_skips,
                        dut.g_deterministic.u_core.u_solver.profile_enumeration_nodes);
`else
                    $fdisplay(result_fd,
                        "%0d,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d",
                        board_number, board_name, width_i, height_i, mines_i,
                        snapshot_selections, snapshot_safe, snapshot_mines,
                        snapshot_cycles,
                        cfg_end_cycle - board_begin_cycle,
                        load_end_cycle - cfg_end_cycle,
                        solver_end_cycle - solver_begin_cycle,
                        result_end_cycle - solver_end_cycle,
                        result_end_cycle - board_begin_cycle,
                        score_numerator, score_denominator,
                        score_scaled_at_output, score_real, snapshot_stalled);
`endif
                else
                    $fdisplay(result_fd,
                        "%0d,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f",
                        board_number, board_name, width_i, height_i, mines_i,
                        snapshot_selections, snapshot_safe, snapshot_mines,
                        snapshot_cycles,
                        cfg_end_cycle - board_begin_cycle,
                        load_end_cycle - cfg_end_cycle,
                        solver_end_cycle - solver_begin_cycle,
                        result_end_cycle - solver_end_cycle,
                        result_end_cycle - board_begin_cycle,
                        score_numerator, score_denominator,
                        score_scaled_at_output, score_real);
                result_ack = 1;
                @(negedge clk);
                result_ack = 0;
                end
            end
        end
        $fclose(input_fd);
        $fclose(result_fd);
`ifdef SIM_PROFILE
        if (profile_event_fd != 0)
            $fclose(profile_event_fd);
        if (frontier_event_fd != 0)
            $fclose(frontier_event_fd);
`endif
        $display("OFFICIAL FILE RUN COMPLETE: %0d boards (start %0d)",
                 processed_count, board_start);
        $finish;
    end
endmodule
