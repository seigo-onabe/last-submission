`timescale 1ns/1ps

// Orchestrates one bounded component from constraint conversion through exact
// enumeration and forced-cell emission. Constraint discovery and board-state
// application remain responsibilities of the parent solver FSM.
module solver_small_component_pipeline #(
    parameter SKIP_DISCONNECTED = 0,
    parameter MAX_CONSTRAINTS = 16
) (
    input  wire              clk,
    input  wire              reset,
    input  wire              clear,
    input  wire              constraint_valid,
    output wire              constraint_ready,
    input  wire              constraint_is_derived,
    input  wire [4:0]        board_width,
    input  wire [4:0]        board_height,
    input  wire [4:0]        constraint_center_x,
    input  wire [4:0]        constraint_center_y,
    input  wire signed [6:0] constraint_base_x,
    input  wire signed [6:0] constraint_base_y,
    input  wire [7:0]        constraint_local_mask,
    input  wire [24:0]       constraint_derived_mask,
    input  wire [4:0]        constraint_mines,
    output wire              constraint_done,
    output wire              constraint_added,
    output wire              constraint_incomplete,
    input  wire              solve_start,
    output wire              solve_ready,
    input  wire [3:0]        maximum_mines,
    input  wire              closed_local,
    output wire              result_valid,
    input  wire              result_ready,
    output wire [8:0]        result_cell,
    output wire              result_is_mine,
    output reg               done,
    output reg               error,
    output wire              overflow,
    output wire [3:0]        variable_count,
    output wire [4:0]        component_constraint_count,
    output wire [31:0]       enumeration_nodes,
    output wire [31:0]       total_ways,
    output wire              candidate_valid,
    input  wire              candidate_ready,
    output reg [8:0]         candidate_cell,
    output reg [31:0]        candidate_mine_ways,
    output reg [31:0]        candidate_total_ways,
    output wire              candidate_closed_local,
    output wire [3:0]        profile_state
);
    localparam ST_LOAD           = 4'd0;
    localparam ST_BUILDER_FINISH = 4'd1;
    localparam ST_BUILDER_WAIT   = 4'd2;
    localparam ST_ENUM_LOAD      = 4'd3;
    localparam ST_ENUM_START     = 4'd4;
    localparam ST_ENUM_WAIT      = 4'd5;
    localparam ST_WALK_START     = 4'd6;
    localparam ST_WALK_WAIT      = 4'd7;
    localparam ST_COMPLETE       = 4'd8;
    localparam ST_ERROR          = 4'd9;
    localparam ST_CAND_READ      = 4'd10;
    localparam ST_CAND_COMPARE   = 4'd11;
    localparam ST_CAND_OUTPUT    = 4'd12;

    reg [3:0] state;
    reg [3:0] load_constraint_index;
    reg [3:0] candidate_variable;
    reg [8:0] candidate_current_cell;
    reg [31:0] candidate_current_mines;
    reg candidate_best_valid;
    reg [8:0] candidate_best_cell;
    reg [31:0] candidate_best_mines;

    wire adapter_start_ready;
    wire adapter_done;
    wire adapter_coordinate_error;
    wire builder_begin_valid;
    wire builder_begin_ready;
    wire [4:0] builder_begin_mines;
    wire builder_cell_valid;
    wire builder_cell_ready;
    wire [8:0] builder_cell_index;
    wire builder_end_valid;
    wire builder_end_ready;

    wire builder_done;
    wire builder_component_valid;
    wire builder_overflow;
    wire builder_contradiction;
    wire builder_disconnected;
    wire builder_malformed;
    wire builder_constraint_accepted;
    wire builder_constraint_incomplete;
    wire [11:0] builder_constraint_mask;
    wire [4:0] builder_constraint_mines;
    wire [3:0] walker_query_variable;
    wire [8:0] builder_query_cell;

    wire enum_done;
    wire enum_contradiction;
    wire [11:0] enum_forced_safe;
    wire [11:0] enum_forced_mine;
    wire [31:0] enum_query_mine_total;
    wire walker_done;
    wire walker_contradiction;
    wire child_reset = reset || clear;

    assign constraint_ready = state == ST_LOAD && adapter_start_ready;
    assign constraint_done = state == ST_LOAD && adapter_done;
    assign constraint_added = constraint_done &&
                              builder_constraint_accepted;
    assign constraint_incomplete = constraint_done &&
                                   builder_constraint_incomplete;
    assign solve_ready = state == ST_LOAD && adapter_start_ready &&
                         !constraint_valid;
    assign overflow = builder_overflow;
    assign candidate_valid = state == ST_CAND_OUTPUT;
    assign candidate_closed_local = candidate_valid && closed_local;
    assign profile_state = state;

    solver_component_adapter u_adapter (
        .clk(clk), .reset(child_reset),
        .start(constraint_valid && constraint_ready),
        .start_ready(adapter_start_ready),
        .is_derived(constraint_is_derived),
        .board_width(board_width), .board_height(board_height),
        .center_x(constraint_center_x), .center_y(constraint_center_y),
        .base_x(constraint_base_x), .base_y(constraint_base_y),
        .local_mask(constraint_local_mask),
        .derived_mask(constraint_derived_mask), .mines(constraint_mines),
        .builder_begin_valid(builder_begin_valid),
        .builder_begin_ready(builder_begin_ready),
        .builder_begin_mines(builder_begin_mines),
        .builder_cell_valid(builder_cell_valid),
        .builder_cell_ready(builder_cell_ready),
        .builder_cell_index(builder_cell_index),
        .builder_end_valid(builder_end_valid),
        .builder_end_ready(builder_end_ready), .done(adapter_done),
        .coordinate_error(adapter_coordinate_error)
    );

    solver_component_builder #(
        .MAX_CONSTRAINTS(MAX_CONSTRAINTS),
        .SKIP_DISCONNECTED(SKIP_DISCONNECTED)
    ) u_builder (
        .clk(clk), .reset(child_reset), .clear(1'b0),
        .begin_valid(builder_begin_valid), .begin_ready(builder_begin_ready),
        .begin_mines(builder_begin_mines), .cell_valid(builder_cell_valid),
        .cell_ready(builder_cell_ready), .cell_index(builder_cell_index),
        .end_valid(builder_end_valid), .end_ready(builder_end_ready),
        .finish(state == ST_BUILDER_FINISH), .finish_ready(),
        .done(builder_done), .component_valid(builder_component_valid),
        .overflow(builder_overflow), .contradiction(builder_contradiction),
        .disconnected(builder_disconnected), .malformed(builder_malformed),
        .constraint_accepted(builder_constraint_accepted),
        .constraint_incomplete(builder_constraint_incomplete),
        .variable_count(variable_count),
        .constraint_count(component_constraint_count),
        .query_variable((state == ST_CAND_READ ||
                         state == ST_CAND_COMPARE ||
                         state == ST_CAND_OUTPUT) ?
                        candidate_variable : walker_query_variable),
        .query_cell(builder_query_cell),
        .query_constraint(load_constraint_index),
        .query_constraint_mask(builder_constraint_mask),
        .query_constraint_mines(builder_constraint_mines)
    );

    solver_small_enumerator u_enumerator (
        .clk(clk), .reset(child_reset),
        .constraint_we(state == ST_ENUM_LOAD),
        .constraint_write_index(load_constraint_index),
        .constraint_write_mask(builder_constraint_mask),
        .constraint_write_mines(builder_constraint_mines[3:0]),
        .start(state == ST_ENUM_START), .variable_count(variable_count),
        .constraint_count(component_constraint_count),
        .maximum_mines(maximum_mines), .busy(), .done(enum_done),
        .contradiction(enum_contradiction),
        .enumeration_nodes(enumeration_nodes), .total_ways(total_ways),
        .forced_safe_mask(enum_forced_safe),
        .forced_mine_mask(enum_forced_mine), .query_mine_count(4'd0),
        .query_variable(candidate_variable), .query_ways(),
        .query_mine_ways(), .query_mine_total(enum_query_mine_total)
    );

    solver_forced_cell_walker u_walker (
        .clk(clk), .reset(child_reset), .start(state == ST_WALK_START),
        .start_ready(), .variable_count(variable_count),
        .forced_safe_mask(enum_forced_safe),
        .forced_mine_mask(enum_forced_mine),
        .query_variable(walker_query_variable),
        .query_cell(builder_query_cell), .result_valid(result_valid),
        .result_ready(result_ready), .result_cell(result_cell),
        .result_is_mine(result_is_mine), .done(walker_done),
        .contradiction(walker_contradiction)
    );

    always @(posedge clk) begin
        if (child_reset) begin
            state <= ST_LOAD;
            load_constraint_index <= 4'd0;
            done <= 1'b0;
            error <= 1'b0;
            candidate_variable <= 4'd0;
            candidate_current_cell <= 9'd0;
            candidate_current_mines <= 32'd0;
            candidate_best_valid <= 1'b0;
            candidate_best_cell <= 9'd0;
            candidate_best_mines <= 32'd0;
            candidate_cell <= 9'd0;
            candidate_mine_ways <= 32'd0;
            candidate_total_ways <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_LOAD: begin
                    if (adapter_done && adapter_coordinate_error) begin
                        error <= 1'b1;
                        state <= ST_ERROR;
                    end else if (builder_overflow || builder_contradiction ||
                                 (!SKIP_DISCONNECTED &&
                                  builder_disconnected) ||
                                 builder_malformed) begin
                        error <= 1'b1;
                        state <= ST_ERROR;
                    end else if (solve_start && solve_ready) begin
                        state <= ST_BUILDER_FINISH;
                    end
                end

                ST_BUILDER_FINISH: state <= ST_BUILDER_WAIT;

                ST_BUILDER_WAIT: begin
                    if (builder_done) begin
                        if (!builder_component_valid) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else begin
                            load_constraint_index <= 4'd0;
                            state <= ST_ENUM_LOAD;
                        end
                    end
                end

                ST_ENUM_LOAD: begin
                    if (load_constraint_index + 1'b1 >=
                        component_constraint_count) begin
                        state <= ST_ENUM_START;
                    end else begin
                        load_constraint_index <=
                            load_constraint_index + 1'b1;
                    end
                end

                ST_ENUM_START: state <= ST_ENUM_WAIT;

                ST_ENUM_WAIT: begin
                    if (enum_done) begin
                        if (enum_contradiction) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else if ((enum_forced_safe |
                                     enum_forced_mine) == 0) begin
                            if (closed_local) begin
                                candidate_variable <= 4'd0;
                                candidate_best_valid <= 1'b0;
                                state <= ST_CAND_READ;
                            end else begin
                                state <= ST_COMPLETE;
                            end
                        end else begin
                            state <= ST_WALK_START;
                        end
                    end
                end

                ST_WALK_START: state <= ST_WALK_WAIT;

                ST_WALK_WAIT: begin
                    if (walker_done) begin
                        if (walker_contradiction) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else begin
                            state <= ST_COMPLETE;
                        end
                    end
                end

                ST_CAND_READ: begin
                    candidate_current_cell <= builder_query_cell;
                    candidate_current_mines <= enum_query_mine_total;
                    state <= ST_CAND_COMPARE;
                end

                ST_CAND_COMPARE: begin
                    if (!candidate_best_valid ||
                        candidate_current_mines < candidate_best_mines ||
                        (candidate_current_mines == candidate_best_mines &&
                         candidate_current_cell < candidate_best_cell)) begin
                        candidate_best_valid <= 1'b1;
                        candidate_best_cell <= candidate_current_cell;
                        candidate_best_mines <= candidate_current_mines;
                    end
                    if (candidate_variable + 1'b1 >= variable_count) begin
                        candidate_cell <= (!candidate_best_valid ||
                            candidate_current_mines < candidate_best_mines ||
                            (candidate_current_mines == candidate_best_mines &&
                             candidate_current_cell < candidate_best_cell)) ?
                            candidate_current_cell : candidate_best_cell;
                        candidate_mine_ways <= (!candidate_best_valid ||
                            candidate_current_mines < candidate_best_mines ||
                            (candidate_current_mines == candidate_best_mines &&
                             candidate_current_cell < candidate_best_cell)) ?
                            candidate_current_mines : candidate_best_mines;
                        candidate_total_ways <= total_ways;
                        state <= ST_CAND_OUTPUT;
                    end else begin
                        candidate_variable <= candidate_variable + 1'b1;
                        state <= ST_CAND_READ;
                    end
                end

                ST_CAND_OUTPUT: begin
                    if (candidate_ready)
                        state <= ST_COMPLETE;
                end

                ST_COMPLETE: begin
                    done <= 1'b1;
                    state <= ST_LOAD;
                end

                ST_ERROR: begin
                    done <= 1'b1;
                    state <= ST_ERROR;
                end

                default: begin
                    error <= 1'b1;
                    state <= ST_ERROR;
                end
            endcase
        end
    end
endmodule
