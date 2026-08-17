`timescale 1ns/1ps

// Exact, bounded enumerator for a single reduced frontier component.
//
// Constraints are loaded before start. Each constraint is a bit mask over at
// most 12 local variables and an exact mine count. The engine performs a
// depth-first traversal and rejects a partial assignment as soon as an exact
// constraint can no longer be met. It records the distribution by mine count
// and the same distribution for each mined variable.
module solver_small_enumerator #(
    parameter MAX_VARIABLES = 12,
    parameter MAX_CONSTRAINTS = 16,
    parameter COUNT_WIDTH = 32
) (
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         constraint_we,
    input  wire [3:0]                   constraint_write_index,
    input  wire [MAX_VARIABLES-1:0]     constraint_write_mask,
    input  wire [3:0]                   constraint_write_mines,
    input  wire                         start,
    input  wire [3:0]                   variable_count,
    input  wire [4:0]                   constraint_count,
    input  wire [3:0]                   maximum_mines,
    output reg                          busy,
    output reg                          done,
    output reg                          contradiction,
    output reg [31:0]                   enumeration_nodes,
    output reg [COUNT_WIDTH-1:0]        total_ways,
    output reg [MAX_VARIABLES-1:0]      forced_safe_mask,
    output reg [MAX_VARIABLES-1:0]      forced_mine_mask,
    input  wire [3:0]                   query_mine_count,
    input  wire [3:0]                   query_variable,
    output reg [COUNT_WIDTH-1:0]        query_ways,
    output reg [COUNT_WIDTH-1:0]        query_mine_ways,
    output reg [COUNT_WIDTH-1:0]        query_mine_total
);
    localparam ST_IDLE             = 4'd0;
    localparam ST_CLEAR            = 4'd1;
    localparam ST_VALIDATE         = 4'd2;
    localparam ST_CHECK_NODE       = 4'd3;
    localparam ST_CHECK_CONSTRAINT = 4'd4;
    localparam ST_EXPAND           = 4'd5;
    localparam ST_RECORD           = 4'd6;
    localparam ST_BACKTRACK        = 4'd7;
    localparam ST_FINISH           = 4'd8;
    localparam ST_LEGACY_ASSIGN    = 4'd9;
    localparam ST_LEGACY_CONSTRAINT = 4'd10;
    localparam ST_LEGACY_NEXT      = 4'd11;

    reg [3:0] state;
    reg [MAX_VARIABLES-1:0] constraint_masks [0:MAX_CONSTRAINTS-1];
    reg [3:0] constraint_mines [0:MAX_CONSTRAINTS-1];
    reg [COUNT_WIDTH-1:0] ways_by_mines [0:MAX_VARIABLES];
    reg [COUNT_WIDTH-1:0] mine_ways
        [0:MAX_VARIABLES*(MAX_VARIABLES+1)-1];
    reg [COUNT_WIDTH-1:0] mine_total [0:MAX_VARIABLES-1];

    reg [3:0] active_variable_count;
    reg [4:0] active_constraint_count;
    reg [3:0] active_maximum_mines;
    reg [MAX_VARIABLES-1:0] active_variable_mask;
    reg [MAX_VARIABLES-1:0] assignment;
    reg [MAX_VARIABLES-1:0] mine_branch_pending;
    reg [3:0] assignment_depth;
    reg [MAX_VARIABLES:0] assignment_limit;
    reg use_dfs;
    reg [MAX_CONSTRAINTS-1:0] pending_constraint_mask;
    reg [4:0] constraint_cursor;
    reg [3:0] clear_mine_count;
    integer variable_index;
    integer assignment_mines;
    integer assigned_constraint_mines;
    integer unassigned_constraint_variables;
    integer selected_constraint;
    integer second_assigned_constraint_mines;
    integer second_unassigned_constraint_variables;
    integer second_selected_constraint;
    reg [MAX_CONSTRAINTS-1:0] remaining_constraint_mask;
    reg [MAX_CONSTRAINTS-1:0] node_constraint_mask;

    function integer count_ones;
        input [MAX_VARIABLES-1:0] value;
        integer bit_index;
        begin
            count_ones = 0;
            for (bit_index = 0; bit_index < MAX_VARIABLES;
                 bit_index = bit_index + 1)
                count_ones = count_ones + value[bit_index];
        end
    endfunction

    function integer first_constraint;
        input [MAX_CONSTRAINTS-1:0] mask;
        integer mask_index;
        begin
            first_constraint = 0;
            for (mask_index = MAX_CONSTRAINTS-1;
                 mask_index >= 0; mask_index = mask_index - 1)
                if (mask[mask_index])
                    first_constraint = mask_index;
        end
    endfunction

    function [3:0] deepest_pending_branch;
        input [MAX_VARIABLES-1:0] mask;
        integer mask_index;
        begin
            deepest_pending_branch = 0;
            for (mask_index = 0; mask_index < MAX_VARIABLES;
                 mask_index = mask_index + 1)
                if (mask[mask_index])
                    deepest_pending_branch = mask_index[3:0];
        end
    endfunction

    wire [MAX_VARIABLES-1:0] active_pending_branches =
        mine_branch_pending & prefix_mask(assignment_depth);
    wire [3:0] backtrack_depth =
        deepest_pending_branch(active_pending_branches);

    function [MAX_VARIABLES-1:0] prefix_mask;
        input [3:0] depth;
        begin
            if (depth == 0)
                prefix_mask = {MAX_VARIABLES{1'b0}};
            else if (depth >= MAX_VARIABLES)
                prefix_mask = {MAX_VARIABLES{1'b1}};
            else
                prefix_mask =
                    {MAX_VARIABLES{1'b1}} >> (MAX_VARIABLES - depth);
        end
    endfunction

    always @* begin
        query_ways = {COUNT_WIDTH{1'b0}};
        query_mine_ways = {COUNT_WIDTH{1'b0}};
        query_mine_total = {COUNT_WIDTH{1'b0}};
        if (query_mine_count <= MAX_VARIABLES)
            query_ways = ways_by_mines[query_mine_count];
        if (query_variable < MAX_VARIABLES &&
            query_mine_count <= MAX_VARIABLES)
            query_mine_ways =
                mine_ways[query_variable * (MAX_VARIABLES+1) +
                          query_mine_count];
        if (query_variable < MAX_VARIABLES)
            query_mine_total = mine_total[query_variable];
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            contradiction <= 1'b0;
            enumeration_nodes <= 32'd0;
            total_ways <= {COUNT_WIDTH{1'b0}};
            forced_safe_mask <= {MAX_VARIABLES{1'b0}};
            forced_mine_mask <= {MAX_VARIABLES{1'b0}};
            active_variable_count <= 4'd0;
            active_constraint_count <= 5'd0;
            active_maximum_mines <= 4'd0;
            active_variable_mask <= {MAX_VARIABLES{1'b0}};
            assignment <= {MAX_VARIABLES{1'b0}};
            mine_branch_pending <= {MAX_VARIABLES{1'b0}};
            assignment_depth <= 4'd0;
            assignment_limit <= {(MAX_VARIABLES+1){1'b0}};
            use_dfs <= 1'b0;
            pending_constraint_mask <= {MAX_CONSTRAINTS{1'b0}};
            constraint_cursor <= 5'd0;
            clear_mine_count <= 4'd0;
        end else begin
            done <= 1'b0;

            if (constraint_we && !busy &&
                constraint_write_index < MAX_CONSTRAINTS) begin
                constraint_masks[constraint_write_index] <=
                    constraint_write_mask;
                constraint_mines[constraint_write_index] <=
                    constraint_write_mines;
            end

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        contradiction <= 1'b0;
                        enumeration_nodes <= 32'd0;
                        total_ways <= {COUNT_WIDTH{1'b0}};
                        forced_safe_mask <= {MAX_VARIABLES{1'b0}};
                        forced_mine_mask <= {MAX_VARIABLES{1'b0}};
                        if (variable_count == 0 ||
                            variable_count > MAX_VARIABLES ||
                            constraint_count > MAX_CONSTRAINTS) begin
                            contradiction <= 1'b1;
                            done <= 1'b1;
                            busy <= 1'b0;
                        end else begin
                            busy <= 1'b1;
                            active_variable_count <= variable_count;
                            active_constraint_count <= constraint_count;
                            active_maximum_mines <= maximum_mines;
                            active_variable_mask <=
                                ({MAX_VARIABLES{1'b1}} >>
                                 (MAX_VARIABLES - variable_count));
                            assignment_limit <=
                                ({{MAX_VARIABLES{1'b0}}, 1'b1} <<
                                 variable_count);
                            use_dfs <= constraint_count >= 2;
                            clear_mine_count <= 4'd0;
                            state <= ST_CLEAR;
                        end
                    end
                end

                ST_CLEAR: begin
                    ways_by_mines[clear_mine_count] <=
                        {COUNT_WIDTH{1'b0}};
                    for (variable_index = 0;
                         variable_index < MAX_VARIABLES;
                         variable_index = variable_index + 1) begin
                        mine_ways[variable_index * (MAX_VARIABLES+1) +
                                  clear_mine_count] <=
                            {COUNT_WIDTH{1'b0}};
                        if (clear_mine_count == 0)
                            mine_total[variable_index] <=
                                {COUNT_WIDTH{1'b0}};
                    end
                    if (clear_mine_count == MAX_VARIABLES) begin
                        constraint_cursor <= 5'd0;
                        state <= ST_VALIDATE;
                    end else begin
                        clear_mine_count <= clear_mine_count + 1'b1;
                    end
                end

                ST_VALIDATE: begin
                    if (active_constraint_count == 0) begin
                        assignment <= {MAX_VARIABLES{1'b0}};
                        mine_branch_pending <= {MAX_VARIABLES{1'b0}};
                        assignment_depth <= 4'd0;
                        state <= use_dfs ? ST_CHECK_NODE : ST_LEGACY_ASSIGN;
                    end else if ((constraint_masks[constraint_cursor] &
                                  ~active_variable_mask) != 0 ||
                                 constraint_mines[constraint_cursor] >
                                  count_ones(constraint_masks[constraint_cursor] &
                                             active_variable_mask)) begin
                        contradiction <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (constraint_cursor + 1'b1 >=
                                 active_constraint_count) begin
                        assignment <= {MAX_VARIABLES{1'b0}};
                        mine_branch_pending <= {MAX_VARIABLES{1'b0}};
                        assignment_depth <= 4'd0;
                        state <= use_dfs ? ST_CHECK_NODE : ST_LEGACY_ASSIGN;
                    end else begin
                        constraint_cursor <= constraint_cursor + 1'b1;
                    end
                end

                ST_CHECK_NODE: begin
                    assignment_mines = count_ones(assignment);
                    if (assignment_depth == active_variable_count)
                        enumeration_nodes <= enumeration_nodes + 1'b1;
                    if (assignment_mines > active_maximum_mines) begin
                        state <= ST_BACKTRACK;
                    end else if (assignment_depth == 0) begin
                        state <= ST_EXPAND;
                    end else begin
                        for (variable_index = 0;
                             variable_index < MAX_CONSTRAINTS;
                             variable_index = variable_index + 1)
                            node_constraint_mask[variable_index] =
                                variable_index < active_constraint_count &&
                                constraint_masks[variable_index]
                                                [assignment_depth-1'b1];
                        selected_constraint =
                            first_constraint(node_constraint_mask);
                        remaining_constraint_mask = node_constraint_mask;
                        remaining_constraint_mask[selected_constraint] = 1'b0;
                        assigned_constraint_mines =
                            count_ones(assignment &
                                       constraint_masks[selected_constraint] &
                                       prefix_mask(assignment_depth));
                        unassigned_constraint_variables =
                            count_ones(constraint_masks[selected_constraint] &
                                       active_variable_mask &
                                       ~prefix_mask(assignment_depth));
                        if (node_constraint_mask == 0) begin
                            if (assignment_depth == active_variable_count)
                                state <= ST_RECORD;
                            else
                                state <= ST_EXPAND;
                        end else if (assigned_constraint_mines >
                                     constraint_mines[selected_constraint] ||
                                     assigned_constraint_mines +
                                       unassigned_constraint_variables <
                                       constraint_mines[selected_constraint]) begin
                            state <= ST_BACKTRACK;
                        end else if (remaining_constraint_mask == 0) begin
                            if (assignment_depth == active_variable_count)
                                state <= ST_RECORD;
                            else
                                state <= ST_EXPAND;
                        end else begin
                            pending_constraint_mask <=
                                remaining_constraint_mask;
                            state <= ST_CHECK_CONSTRAINT;
                        end
                    end
                end

                ST_CHECK_CONSTRAINT: begin
                    selected_constraint =
                        first_constraint(pending_constraint_mask);
                    remaining_constraint_mask = pending_constraint_mask;
                    remaining_constraint_mask[selected_constraint] = 1'b0;
                    second_selected_constraint =
                        first_constraint(remaining_constraint_mask);
                    assigned_constraint_mines =
                        count_ones(assignment &
                                   constraint_masks[selected_constraint] &
                                   prefix_mask(assignment_depth));
                    unassigned_constraint_variables =
                        count_ones(constraint_masks[selected_constraint] &
                                   active_variable_mask &
                                   ~prefix_mask(assignment_depth));
                    second_assigned_constraint_mines =
                        count_ones(assignment &
                                   constraint_masks[second_selected_constraint] &
                                   prefix_mask(assignment_depth));
                    second_unassigned_constraint_variables =
                        count_ones(constraint_masks[second_selected_constraint] &
                                   active_variable_mask &
                                   ~prefix_mask(assignment_depth));
                    if (pending_constraint_mask == 0) begin
                        if (assignment_depth == active_variable_count)
                            state <= ST_RECORD;
                        else
                            state <= ST_EXPAND;
                    end else if (assigned_constraint_mines >
                        constraint_mines[selected_constraint] ||
                        assigned_constraint_mines +
                            unassigned_constraint_variables <
                        constraint_mines[selected_constraint] ||
                        (remaining_constraint_mask != 0 &&
                         (second_assigned_constraint_mines >
                            constraint_mines[second_selected_constraint] ||
                          second_assigned_constraint_mines +
                            second_unassigned_constraint_variables <
                            constraint_mines[second_selected_constraint]))) begin
                        state <= ST_BACKTRACK;
                    end else begin
                        pending_constraint_mask[selected_constraint] <= 1'b0;
                        if (remaining_constraint_mask != 0)
                            pending_constraint_mask[second_selected_constraint]
                                <= 1'b0;
                    end
                end

                ST_EXPAND: begin
                    assignment[assignment_depth] <= 1'b0;
                    mine_branch_pending[assignment_depth] <= 1'b1;
                    assignment_depth <= assignment_depth + 1'b1;
                    state <= ST_CHECK_NODE;
                end

                ST_RECORD: begin
                    assignment_mines = count_ones(assignment);
                    total_ways <= total_ways + 1'b1;
                    ways_by_mines[assignment_mines] <=
                        ways_by_mines[assignment_mines] + 1'b1;
                    for (variable_index = 0;
                         variable_index < MAX_VARIABLES;
                         variable_index = variable_index + 1)
                        if (assignment[variable_index])
                        begin
                            mine_ways[variable_index * (MAX_VARIABLES+1) +
                                      assignment_mines] <=
                                mine_ways[variable_index *
                                          (MAX_VARIABLES+1) +
                                          assignment_mines] +
                                1'b1;
                            mine_total[variable_index] <=
                                mine_total[variable_index] + 1'b1;
                        end
                    state <= use_dfs ? ST_BACKTRACK : ST_LEGACY_NEXT;
                end

                ST_BACKTRACK: begin
                    if (active_pending_branches == 0) begin
                        state <= ST_FINISH;
                    end else begin
                        assignment <=
                            (assignment & prefix_mask(backtrack_depth)) |
                            ({{(MAX_VARIABLES-1){1'b0}}, 1'b1} <<
                             backtrack_depth);
                        mine_branch_pending <=
                            mine_branch_pending &
                            prefix_mask(backtrack_depth);
                        assignment_depth <= backtrack_depth + 4'd1;
                        state <= ST_CHECK_NODE;
                    end
                end

                ST_LEGACY_ASSIGN: begin
                    enumeration_nodes <= enumeration_nodes + 1'b1;
                    assignment_mines = count_ones(assignment);
                    if (assignment_mines > active_maximum_mines) begin
                        state <= ST_LEGACY_NEXT;
                    end else if (active_constraint_count == 0) begin
                        state <= ST_RECORD;
                    end else begin
                        constraint_cursor <= 5'd0;
                        state <= ST_LEGACY_CONSTRAINT;
                    end
                end

                ST_LEGACY_CONSTRAINT: begin
                    if (count_ones(assignment &
                                   constraint_masks[constraint_cursor]) !=
                        constraint_mines[constraint_cursor]) begin
                        state <= ST_LEGACY_NEXT;
                    end else if (constraint_cursor + 1'b1 >=
                                 active_constraint_count) begin
                        state <= ST_RECORD;
                    end else begin
                        constraint_cursor <= constraint_cursor + 1'b1;
                    end
                end

                ST_LEGACY_NEXT: begin
                    if ({1'b0, assignment} + 1'b1 >= assignment_limit) begin
                        state <= ST_FINISH;
                    end else begin
                        assignment <= assignment + 1'b1;
                        state <= ST_LEGACY_ASSIGN;
                    end
                end

                ST_FINISH: begin
                    contradiction <= total_ways == 0;
                    for (variable_index = 0;
                         variable_index < MAX_VARIABLES;
                         variable_index = variable_index + 1) begin
                        forced_safe_mask[variable_index] <=
                            active_variable_mask[variable_index] &&
                            total_ways != 0 &&
                            mine_total[variable_index] == 0;
                        forced_mine_mask[variable_index] <=
                            active_variable_mask[variable_index] &&
                            total_ways != 0 &&
                            mine_total[variable_index] == total_ways;
                    end
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
