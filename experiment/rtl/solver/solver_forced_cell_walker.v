`timescale 1ns/1ps

// Converts enumerator forced-variable masks back to global board cell update
// requests using the component builder's variable-to-cell query port.
module solver_forced_cell_walker #(
    parameter MAX_VARIABLES = 12
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     start,
    output wire                     start_ready,
    input  wire [3:0]               variable_count,
    input  wire [MAX_VARIABLES-1:0] forced_safe_mask,
    input  wire [MAX_VARIABLES-1:0] forced_mine_mask,
    output reg [3:0]                query_variable,
    input  wire [8:0]               query_cell,
    output wire                     result_valid,
    input  wire                     result_ready,
    output wire [8:0]               result_cell,
    output wire                     result_is_mine,
    output reg                      done,
    output reg                      contradiction
);
    localparam ST_IDLE = 2'd0;
    localparam ST_SCAN = 2'd1;
    localparam ST_EMIT = 2'd2;

    reg [1:0] state;
    reg [3:0] active_variable_count;
    reg [MAX_VARIABLES-1:0] active_safe_mask;
    reg [MAX_VARIABLES-1:0] active_mine_mask;

    assign start_ready = state == ST_IDLE;
    assign result_valid = state == ST_EMIT;
    assign result_cell = query_cell;
    assign result_is_mine = active_mine_mask[query_variable];

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            query_variable <= 4'd0;
            active_variable_count <= 4'd0;
            active_safe_mask <= {MAX_VARIABLES{1'b0}};
            active_mine_mask <= {MAX_VARIABLES{1'b0}};
            done <= 1'b0;
            contradiction <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        active_variable_count <= variable_count;
                        active_safe_mask <= forced_safe_mask;
                        active_mine_mask <= forced_mine_mask;
                        query_variable <= 4'd0;
                        contradiction <= 1'b0;
                        if (variable_count == 0 ||
                            variable_count > MAX_VARIABLES) begin
                            contradiction <= 1'b1;
                            done <= 1'b1;
                        end else begin
                            state <= ST_SCAN;
                        end
                    end
                end

                ST_SCAN: begin
                    if (active_safe_mask[query_variable] &&
                        active_mine_mask[query_variable]) begin
                        contradiction <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (active_safe_mask[query_variable] ||
                                 active_mine_mask[query_variable]) begin
                        state <= ST_EMIT;
                    end else if (query_variable + 1'b1 >=
                                 active_variable_count) begin
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        query_variable <= query_variable + 1'b1;
                    end
                end

                ST_EMIT: begin
                    if (result_ready) begin
                        if (query_variable + 1'b1 >=
                            active_variable_count) begin
                            done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            query_variable <= query_variable + 1'b1;
                            state <= ST_SCAN;
                        end
                    end
                end

                default: begin
                    contradiction <= 1'b1;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
