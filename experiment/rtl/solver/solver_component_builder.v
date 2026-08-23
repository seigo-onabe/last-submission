`timescale 1ns/1ps

// Builds one bounded, connected frontier component from a stream of global
// cell indices. The output format feeds solver_small_enumerator directly.
module solver_component_builder #(
    parameter MAX_VARIABLES = 12,
    parameter MAX_CONSTRAINTS = 16,
    parameter SKIP_DISCONNECTED = 0
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     clear,
    input  wire                     begin_valid,
    output wire                     begin_ready,
    input  wire [4:0]               begin_mines,
    input  wire                     cell_valid,
    output wire                     cell_ready,
    input  wire [8:0]               cell_index,
    input  wire                     end_valid,
    output wire                     end_ready,
    input  wire                     finish,
    output wire                     finish_ready,
    output reg                      done,
    output reg                      component_valid,
    output reg                      overflow,
    output reg                      contradiction,
    output reg                      disconnected,
    output reg                      malformed,
    output reg                      constraint_accepted,
    output reg                      constraint_incomplete,
    output reg [3:0]                variable_count,
    output reg [4:0]                constraint_count,
    input  wire [3:0]               query_variable,
    output reg [8:0]                query_cell,
    input  wire [3:0]               query_constraint,
    output reg [MAX_VARIABLES-1:0]  query_constraint_mask,
    output reg [4:0]                query_constraint_mines
);
    reg building;
    reg sealed;
    reg [8:0] variable_cells [0:MAX_VARIABLES-1];
    reg [MAX_VARIABLES-1:0] constraint_masks [0:MAX_CONSTRAINTS-1];
    reg [4:0] constraint_mines [0:MAX_CONSTRAINTS-1];
    reg [MAX_VARIABLES-1:0] current_mask;
    reg [4:0] current_mines;
    reg [3:0] existing_variable_count;
    reg current_overlap;
    reg current_overflow;

    integer search_index;
    reg cell_found;
    reg [3:0] found_variable;
    integer compare_index;
    reg same_mask_found;
    reg same_mask_mines_mismatch;

    wire any_error = overflow || contradiction || disconnected || malformed;
    assign begin_ready = !building && !sealed && !any_error;
    assign cell_ready = building && !any_error;
    assign end_ready = building && !any_error;
    assign finish_ready = !building && !sealed && !any_error;

    function integer count_ones;
        input [MAX_VARIABLES-1:0] value;
        integer index;
        begin
            count_ones = 0;
            for (index = 0; index < MAX_VARIABLES; index = index + 1)
                count_ones = count_ones + value[index];
        end
    endfunction

    always @* begin
        cell_found = 1'b0;
        found_variable = 4'd0;
        for (search_index = 0; search_index < MAX_VARIABLES;
             search_index = search_index + 1) begin
            if (!cell_found && search_index < variable_count &&
                variable_cells[search_index] == cell_index) begin
                cell_found = 1'b1;
                found_variable = search_index[3:0];
            end
        end

        same_mask_found = 1'b0;
        same_mask_mines_mismatch = 1'b0;
        for (compare_index = 0; compare_index < MAX_CONSTRAINTS;
             compare_index = compare_index + 1) begin
            if (compare_index < constraint_count &&
                constraint_masks[compare_index] == current_mask) begin
                same_mask_found = 1'b1;
                if (constraint_mines[compare_index] != current_mines)
                    same_mask_mines_mismatch = 1'b1;
            end
        end

        query_cell = 9'd0;
        if (query_variable < variable_count)
            query_cell = variable_cells[query_variable];
        query_constraint_mask = {MAX_VARIABLES{1'b0}};
        query_constraint_mines = 5'd0;
        if (query_constraint < constraint_count) begin
            query_constraint_mask = constraint_masks[query_constraint];
            query_constraint_mines = constraint_mines[query_constraint];
        end
    end

    always @(posedge clk) begin
        if (reset || clear) begin
            building <= 1'b0;
            sealed <= 1'b0;
            done <= 1'b0;
            component_valid <= 1'b0;
            overflow <= 1'b0;
            contradiction <= 1'b0;
            disconnected <= 1'b0;
            malformed <= 1'b0;
            constraint_accepted <= 1'b0;
            constraint_incomplete <= 1'b0;
            variable_count <= 4'd0;
            constraint_count <= 5'd0;
            current_mask <= {MAX_VARIABLES{1'b0}};
            current_mines <= 5'd0;
            existing_variable_count <= 4'd0;
            current_overlap <= 1'b0;
            current_overflow <= 1'b0;
        end else begin
            done <= 1'b0;
            constraint_accepted <= 1'b0;
            constraint_incomplete <= 1'b0;

            if (begin_valid && begin_ready) begin
                building <= 1'b1;
                current_mask <= {MAX_VARIABLES{1'b0}};
                current_mines <= begin_mines;
                existing_variable_count <= variable_count;
                current_overlap <= 1'b0;
                current_overflow <= 1'b0;
            end

            if (cell_valid && cell_ready) begin
                if (cell_found) begin
                    current_mask[found_variable] <= 1'b1;
                    if (found_variable < existing_variable_count)
                        current_overlap <= 1'b1;
                end else if (variable_count < MAX_VARIABLES) begin
                    variable_cells[variable_count] <= cell_index;
                    current_mask[variable_count] <= 1'b1;
                    variable_count <= variable_count + 1'b1;
                end else begin
                    if (SKIP_DISCONNECTED) begin
                        current_overflow <= 1'b1;
                    end else begin
                        overflow <= 1'b1;
                        building <= 1'b0;
                    end
                end
            end

            if (end_valid && end_ready) begin
                building <= 1'b0;
                if (current_overflow) begin
                    variable_count <= existing_variable_count;
                    if (current_overlap)
                        constraint_incomplete <= 1'b1;
                end else if (current_mask == 0 ||
                    current_mines > count_ones(current_mask)) begin
                    malformed <= 1'b1;
                end else if (constraint_count != 0 && !current_overlap) begin
                    variable_count <= existing_variable_count;
                    if (!SKIP_DISCONNECTED)
                        disconnected <= 1'b1;
                end else if (same_mask_mines_mismatch) begin
                    contradiction <= 1'b1;
                end else if (!same_mask_found) begin
                    if (constraint_count < MAX_CONSTRAINTS) begin
                        constraint_masks[constraint_count] <= current_mask;
                        constraint_mines[constraint_count] <= current_mines;
                        constraint_count <= constraint_count + 1'b1;
                        constraint_accepted <= 1'b1;
                    end else begin
                        variable_count <= existing_variable_count;
                        if (SKIP_DISCONNECTED)
                            constraint_incomplete <= 1'b1;
                        else
                            overflow <= 1'b1;
                    end
                end
            end

            if (finish && finish_ready) begin
                sealed <= 1'b1;
                done <= 1'b1;
                component_valid <= variable_count != 0 &&
                                   constraint_count != 0;
            end
        end
    end
endmodule
