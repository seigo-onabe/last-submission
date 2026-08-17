`timescale 1ns/1ps

// ADC 2026 Minesweeper game manager.
//
// This module is the only block that may read the complete board.  The solver
// can only observe reveal_* events produced after an accepted selection.  A
// zero-valued cell is expanded with a bounded breadth-first-search queue.
//
// Board storage uses a fixed 19-column stride.  Cell (x,y) is stored at
// y * MAX_WIDTH + x, regardless of the configured board width.
module minesweeper_game_core #(
    parameter MAX_WIDTH  = 19,
    parameter MAX_HEIGHT = 19,
    parameter MAX_CELLS  = 361
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

    input  wire       select_valid,
    output wire       select_ready,
    input  wire [4:0] select_x,
    input  wire [4:0] select_y,

    output reg        reveal_valid,
    output reg  [4:0] reveal_x,
    output reg  [4:0] reveal_y,
    output reg        reveal_is_mine,
    output reg  [3:0] reveal_clue,
    output reg        cascade_done,
    output reg        select_rejected,

    output reg  [8:0] opened_safe_count,
    output reg  [8:0] opened_mine_count,
    output reg        protocol_error
);

    localparam STATE_IDLE     = 3'd0;
    localparam STATE_DEQUEUE  = 3'd1;
    localparam STATE_REVEAL   = 3'd2;
    localparam STATE_SCAN     = 3'd3;
    localparam STATE_CHECK    = 3'd4;

    reg [2:0] state;
    reg [4:0] width;
    reg [4:0] height;
    reg       configured;

    reg [3:0] board_mem [0:MAX_CELLS-1];
    reg [MAX_CELLS-1:0] opened;
    reg [MAX_CELLS-1:0] scheduled;

    reg [9:0] queue_mem [0:MAX_CELLS-1];
    reg [8:0] queue_head;
    reg [8:0] queue_tail;
    reg [8:0] queue_count;
    reg [4:0] current_x;
    reg [4:0] current_y;

    reg [1:0] scan_dx;
    reg [1:0] scan_dy;

    integer i;
    integer select_index_calc;
    integer current_index_calc;
    integer neighbor_x_calc;
    integer neighbor_y_calc;
    integer neighbor_index_calc;

    assign cfg_ready = (state == STATE_IDLE);
    assign load_ready = (state == STATE_IDLE) && configured;
    assign select_ready = run_enable && (state == STATE_IDLE) && configured &&
                          !cfg_valid && !load_valid;

    always @* begin
        select_index_calc = (select_y << 4) +
                            (select_y << 1) + select_y + select_x;
        current_index_calc =
            (current_y << 4) + (current_y << 1) + current_y + current_x;
        neighbor_x_calc = current_x + scan_dx - 1;
        neighbor_y_calc = current_y + scan_dy - 1;
        neighbor_index_calc = (neighbor_y_calc << 4) +
                              (neighbor_y_calc << 1) +
                              neighbor_y_calc + neighbor_x_calc;
    end

    function [8:0] queue_increment;
        input [8:0] value;
        begin
            if (value == MAX_CELLS - 1)
                queue_increment = 9'd0;
            else
                queue_increment = value + 9'd1;
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            width <= 5'd0;
            height <= 5'd0;
            configured <= 1'b0;
            opened <= {MAX_CELLS{1'b0}};
            scheduled <= {MAX_CELLS{1'b0}};
            queue_head <= 9'd0;
            queue_tail <= 9'd0;
            queue_count <= 9'd0;
            current_x <= 5'd0;
            current_y <= 5'd0;
            scan_dx <= 2'd0;
            scan_dy <= 2'd0;
            reveal_valid <= 1'b0;
            reveal_x <= 5'd0;
            reveal_y <= 5'd0;
            reveal_is_mine <= 1'b0;
            reveal_clue <= 4'd0;
            cascade_done <= 1'b0;
            select_rejected <= 1'b0;
            opened_safe_count <= 9'd0;
            opened_mine_count <= 9'd0;
            protocol_error <= 1'b0;
        end else begin
            reveal_valid <= 1'b0;
            cascade_done <= 1'b0;
            select_rejected <= 1'b0;

            if ((state == STATE_IDLE) || run_enable) begin
            case (state)
                STATE_IDLE: begin
                    if (cfg_valid) begin
                        width <= cfg_width;
                        height <= cfg_height;
                        opened <= {MAX_CELLS{1'b0}};
                        scheduled <= {MAX_CELLS{1'b0}};
                        queue_head <= 9'd0;
                        queue_tail <= 9'd0;
                        queue_count <= 9'd0;
                        opened_safe_count <= 9'd0;
                        opened_mine_count <= 9'd0;
                        protocol_error <= 1'b0;
                        configured <=
                            (cfg_width >= 1) &&
                            (cfg_width <= MAX_WIDTH) &&
                            (cfg_height >= 1) &&
                            (cfg_height <= MAX_HEIGHT) &&
                            (cfg_total_mines >= 1) &&
                            (cfg_total_mines < cfg_width * cfg_height);
                        if (!((cfg_width >= 1) &&
                              (cfg_width <= MAX_WIDTH) &&
                              (cfg_height >= 1) &&
                              (cfg_height <= MAX_HEIGHT) &&
                              (cfg_total_mines >= 1) &&
                              (cfg_total_mines <
                               cfg_width * cfg_height)))
                            protocol_error <= 1'b1;
                    end else if (load_valid && load_ready) begin
                        if ((load_index < MAX_CELLS) &&
                            (load_value <= 4'd9))
                            board_mem[load_index] <= load_value;
                        else
                            protocol_error <= 1'b1;
                    end else if (select_valid && select_ready) begin
                        if ((select_x >= width) ||
                            (select_y >= height) ||
                            (select_index_calc >= MAX_CELLS) ||
                            opened[select_index_calc]) begin
                            select_rejected <= 1'b1;
                            cascade_done <= 1'b1;
                        end else begin
                            queue_mem[0] <= {select_y, select_x};
                            queue_head <= 9'd0;
                            queue_tail <= 9'd1;
                            queue_count <= 9'd1;
                            scheduled[select_index_calc] <= 1'b1;
                            state <= STATE_DEQUEUE;
                        end
                    end
                end

                STATE_DEQUEUE: begin
                    if (queue_count == 0) begin
                        state <= STATE_CHECK;
                    end else begin
                        current_x <= queue_mem[queue_head][4:0];
                        current_y <= queue_mem[queue_head][9:5];
                        queue_head <= queue_increment(queue_head);
                        queue_count <= queue_count - 9'd1;
                        state <= STATE_REVEAL;
                    end
                end

                STATE_REVEAL: begin
                    if ((current_x >= width) ||
                        (current_y >= height) ||
                        (current_index_calc >= MAX_CELLS)) begin
                        protocol_error <= 1'b1;
                        state <= STATE_CHECK;
                    end else begin
                        opened[current_index_calc] <= 1'b1;
                        reveal_valid <= 1'b1;
                        reveal_x <= current_x;
                        reveal_y <= current_y;
                        reveal_is_mine <=
                            (board_mem[current_index_calc] == 4'd9);
                        reveal_clue <=
                            (board_mem[current_index_calc] == 4'd9) ?
                            4'd0 : board_mem[current_index_calc];

                        if (board_mem[current_index_calc] == 4'd9) begin
                            opened_mine_count <= opened_mine_count + 9'd1;
                            state <= STATE_CHECK;
                        end else begin
                            opened_safe_count <= opened_safe_count + 9'd1;
                            if (board_mem[current_index_calc] == 4'd0) begin
                                scan_dx <= 2'd0;
                                scan_dy <= 2'd0;
                                state <= STATE_SCAN;
                            end else begin
                                state <= STATE_CHECK;
                            end
                        end
                    end
                end

                STATE_SCAN: begin
                    if (!((scan_dx == 1) && (scan_dy == 1)) &&
                        (neighbor_x_calc >= 0) &&
                        (neighbor_x_calc < width) &&
                        (neighbor_y_calc >= 0) &&
                        (neighbor_y_calc < height) &&
                        (neighbor_index_calc >= 0) &&
                        (neighbor_index_calc < MAX_CELLS) &&
                        !scheduled[neighbor_index_calc] &&
                        (board_mem[neighbor_index_calc] != 4'd9)) begin
                        if (queue_count == MAX_CELLS) begin
                            protocol_error <= 1'b1;
                        end else begin
                            queue_mem[queue_tail] <=
                                {neighbor_y_calc[4:0],
                                 neighbor_x_calc[4:0]};
                            queue_tail <= queue_increment(queue_tail);
                            queue_count <= queue_count + 9'd1;
                            scheduled[neighbor_index_calc] <= 1'b1;
                        end
                    end

                    if (scan_dx == 2) begin
                        scan_dx <= 2'd0;
                        if (scan_dy == 2) begin
                            scan_dy <= 2'd0;
                            state <= STATE_CHECK;
                        end else begin
                            scan_dy <= scan_dy + 2'd1;
                        end
                    end else begin
                        scan_dx <= scan_dx + 2'd1;
                    end
                end

                STATE_CHECK: begin
                    if (queue_count != 0) begin
                        state <= STATE_DEQUEUE;
                    end else begin
                        cascade_done <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    protocol_error <= 1'b1;
                    state <= STATE_IDLE;
                end
            endcase
            end
        end
    end

endmodule
