`timescale 1ns/1ps

// Scans the eight neighbors of one open clue, emits R2/R3 deductions, and
// returns the local constraint snapshot consumed by the R5 cache.
module solver_neighbor_scan (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [4:0] board_width,
    input  wire [4:0] board_height,
    input  wire [4:0] center_x,
    input  wire [4:0] center_y,
    input  wire [3:0] center_clue,
    output wire [8:0] read_index,
    input  wire [2:0] read_state,
    output wire       result_valid,
    output wire [8:0] result_index,
    output wire [4:0] result_x,
    output wire [4:0] result_y,
    output wire [2:0] result_state,
    input  wire       result_ready,
    output reg        busy,
    output reg        done,
    output reg        contradiction,
    output wire [7:0] constraint_unknown_mask,
    output wire [3:0] constraint_unknown_count,
    output wire [3:0] constraint_remaining_mines
);
    localparam CELL_UNKNOWN     = 3'd0;
    localparam CELL_QUEUED_SAFE = 3'd1;
    localparam CELL_KNOWN_MINE  = 3'd3;
    localparam CELL_OPEN_MINE   = 3'd4;

    localparam ST_IDLE = 3'd0;
    localparam ST_ADDR = 3'd1;
    localparam ST_READ = 3'd2;
    localparam ST_CLASSIFY = 3'd3;
    localparam ST_EMIT = 3'd4;

    reg [2:0] state;
    reg [3:0] direction;
    reg [3:0] unknown_count;
    reg [3:0] known_mines;
    reg [7:0] unknown_mask;
    reg [3:0] emit_count;
    reg [3:0] emit_position;
    reg [2:0] emit_state;
    reg [4:0] unknown_x [0:7];
    reg [4:0] unknown_y [0:7];
    reg [4:0] width;
    reg [4:0] height;
    reg [4:0] cx;
    reg [4:0] cy;
    reg [3:0] clue;
    integer nx;
    integer ny;
    integer index_calc;
    wire neighbor_in_range;

    always @* begin
        case (direction)
            0: begin nx = cx - 1; ny = cy - 1; end
            1: begin nx = cx;     ny = cy - 1; end
            2: begin nx = cx + 1; ny = cy - 1; end
            3: begin nx = cx - 1; ny = cy;     end
            4: begin nx = cx + 1; ny = cy;     end
            5: begin nx = cx - 1; ny = cy + 1; end
            6: begin nx = cx;     ny = cy + 1; end
            default: begin nx = cx + 1; ny = cy + 1; end
        endcase
        index_calc = (ny << 4) + (ny << 1) + ny + nx;
    end

    assign neighbor_in_range = nx >= 0 && ny >= 0 &&
                               nx < width && ny < height;
    assign read_index = neighbor_in_range ? index_calc[8:0] : 9'd0;
    assign result_valid = (state == ST_EMIT);
    assign result_x = unknown_x[emit_position];
    assign result_y = unknown_y[emit_position];
    assign result_index = (result_y << 4) + (result_y << 1) +
                          result_y + result_x;
    assign result_state = emit_state;
    assign constraint_unknown_mask = unknown_mask;
    assign constraint_unknown_count = unknown_count;
    assign constraint_remaining_mines = clue - known_mines;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            direction <= 0;
            unknown_count <= 0;
            known_mines <= 0;
            unknown_mask <= 0;
            emit_count <= 0;
            emit_position <= 0;
            emit_state <= CELL_UNKNOWN;
            busy <= 0;
            done <= 0;
            contradiction <= 0;
            width <= 0;
            height <= 0;
            cx <= 0;
            cy <= 0;
            clue <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        width <= board_width;
                        height <= board_height;
                        cx <= center_x;
                        cy <= center_y;
                        clue <= center_clue;
                        direction <= 0;
                        unknown_count <= 0;
                        known_mines <= 0;
                        unknown_mask <= 0;
                        contradiction <= 0;
                        busy <= 1'b1;
                        state <= ST_ADDR;
                    end
                end
                ST_ADDR: begin
                    // One cycle for the synchronous state RAM read port.
                    state <= ST_READ;
                end
                ST_READ: begin
                    if (neighbor_in_range) begin
                        if (read_state == CELL_UNKNOWN) begin
                            unknown_x[unknown_count] <= nx[4:0];
                            unknown_y[unknown_count] <= ny[4:0];
                            unknown_count <= unknown_count + 1'b1;
                            unknown_mask[direction] <= 1'b1;
                        end else if (read_state == CELL_KNOWN_MINE ||
                                     read_state == CELL_OPEN_MINE) begin
                            known_mines <= known_mines + 1'b1;
                        end
                    end
                    if (direction == 7) state <= ST_CLASSIFY;
                    else begin
                        direction <= direction + 1'b1;
                        state <= ST_ADDR;
                    end
                end
                ST_CLASSIFY: begin
                    emit_count <= unknown_count;
                    emit_position <= 0;
                    if (clue < known_mines ||
                        clue > known_mines + unknown_count) begin
                        contradiction <= 1'b1;
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else if (unknown_count != 0 && clue == known_mines) begin
                        emit_state <= CELL_QUEUED_SAFE;
                        state <= ST_EMIT;
                    end else if (unknown_count != 0 &&
                                 clue - known_mines == unknown_count) begin
                        emit_state <= CELL_KNOWN_MINE;
                        state <= ST_EMIT;
                    end else begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
                ST_EMIT: begin
                    if (result_ready) begin
                        if (emit_position + 1'b1 == emit_count) begin
                            state <= ST_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            emit_position <= emit_position + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
