`timescale 1ns/1ps

// Rule-compliant four-corner solver for ADC 2026.
//
// The solver never receives the complete board.  It records only reveal events
// and waits for cascade_done before issuing another selection.  A corner that
// was already opened by a previous zero cascade is skipped.
module minesweeper_solver_four_corners #(
    parameter MAX_WIDTH  = 19,
    parameter MAX_HEIGHT = 19,
    parameter MAX_CELLS  = 361
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
    output reg        protocol_error,
    output reg  [2:0] selections_issued,
    output reg  [8:0] observed_safe_count,
    output reg  [8:0] observed_mine_count,
    output reg [31:0] cycle_count
);

    localparam STATE_IDLE    = 3'd0;
    localparam STATE_PREPARE = 3'd1;
    localparam STATE_ISSUE   = 3'd2;
    localparam STATE_WAIT    = 3'd3;
    localparam STATE_FINISH  = 3'd4;
    localparam STATE_ERROR   = 3'd5;

    reg [2:0] state;
    reg [2:0] corner_number;
    reg [4:0] width;
    reg [4:0] height;
    reg [4:0] active_x;
    reg [4:0] active_y;
    reg [MAX_CELLS-1:0] observed_open;

    integer corner_x_calc;
    integer corner_y_calc;
    integer corner_index_calc;
    integer reveal_index_calc;

    assign select_valid = (state == STATE_ISSUE);
    assign select_x = active_x;
    assign select_y = active_y;

    always @* begin
        case (corner_number)
            3'd0: begin
                corner_x_calc = 0;
                corner_y_calc = 0;
            end
            3'd1: begin
                corner_x_calc = width - 1;
                corner_y_calc = 0;
            end
            3'd2: begin
                corner_x_calc = 0;
                corner_y_calc = height - 1;
            end
            default: begin
                corner_x_calc = width - 1;
                corner_y_calc = height - 1;
            end
        endcase
        corner_index_calc = (corner_y_calc << 4) +
                            (corner_y_calc << 1) +
                            corner_y_calc + corner_x_calc;
        reveal_index_calc = (reveal_y << 4) +
                            (reveal_y << 1) + reveal_y + reveal_x;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            corner_number <= 3'd0;
            width <= 5'd0;
            height <= 5'd0;
            active_x <= 5'd0;
            active_y <= 5'd0;
            observed_open <= {MAX_CELLS{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            protocol_error <= 1'b0;
            selections_issued <= 3'd0;
            observed_safe_count <= 9'd0;
            observed_mine_count <= 9'd0;
            cycle_count <= 32'd0;
        end else begin
            done <= 1'b0;

            if (busy && run_enable)
                cycle_count <= cycle_count + 32'd1;

            if ((state == STATE_IDLE) || run_enable) begin
            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        width <= board_width;
                        height <= board_height;
                        corner_number <= 3'd0;
                        observed_open <= {MAX_CELLS{1'b0}};
                        selections_issued <= 3'd0;
                        observed_safe_count <= 9'd0;
                        observed_mine_count <= 9'd0;
                        cycle_count <= 32'd0;
                        protocol_error <= 1'b0;
                        busy <= 1'b1;
                        if ((board_width < 1) ||
                            (board_width > MAX_WIDTH) ||
                            (board_height < 1) ||
                            (board_height > MAX_HEIGHT) ||
                            (total_mines < 1) ||
                            (total_mines >=
                             board_width * board_height)) begin
                            protocol_error <= 1'b1;
                            state <= STATE_ERROR;
                        end else begin
                            state <= STATE_PREPARE;
                        end
                    end
                end

                STATE_PREPARE: begin
                    if (corner_number >= 4) begin
                        state <= STATE_FINISH;
                    end else if (observed_open[corner_index_calc]) begin
                        corner_number <= corner_number + 3'd1;
                    end else begin
                        active_x <= corner_x_calc[4:0];
                        active_y <= corner_y_calc[4:0];
                        state <= STATE_ISSUE;
                    end
                end

                STATE_ISSUE: begin
                    if (select_valid && select_ready) begin
                        selections_issued <= selections_issued + 3'd1;
                        state <= STATE_WAIT;
                    end
                end

                STATE_WAIT: begin
                    if (select_rejected) begin
                        protocol_error <= 1'b1;
                        state <= STATE_ERROR;
                    end else if (cascade_done) begin
                        corner_number <= corner_number + 3'd1;
                        state <= STATE_PREPARE;
                    end
                end

                STATE_FINISH: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= STATE_IDLE;
                end

                STATE_ERROR: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: begin
                    protocol_error <= 1'b1;
                    state <= STATE_ERROR;
                end
            endcase
            end

            // Keep reveal validation after the state machine so a malformed
            // reveal wins over a simultaneous cascade_done transition.
            if (reveal_valid && busy && run_enable) begin
                if ((reveal_x >= width) ||
                    (reveal_y >= height) ||
                    (reveal_index_calc >= MAX_CELLS) ||
                    observed_open[reveal_index_calc]) begin
                    protocol_error <= 1'b1;
                    state <= STATE_ERROR;
                end else begin
                    observed_open[reveal_index_calc] <= 1'b1;
                    if (reveal_is_mine)
                        observed_mine_count <=
                            observed_mine_count + 9'd1;
                    else if (reveal_clue <= 4'd8)
                        observed_safe_count <=
                            observed_safe_count + 9'd1;
                    else begin
                        protocol_error <= 1'b1;
                        state <= STATE_ERROR;
                    end
                end
            end
        end
    end

endmodule
