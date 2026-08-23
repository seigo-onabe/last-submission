`timescale 1ns/1ps

// Small deterministic hardware smoke-test pack. The three 3x3 boards each
// contain one mine and exercise different four-corner outcomes.
module board_rom_loader (
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    output reg        begin_valid,
    input  wire       begin_ready,
    output reg [15:0] begin_board_id,
    output wire [4:0] begin_width,
    output wire [4:0] begin_height,
    output wire [8:0] begin_mines,
    output reg        cell_valid,
    input  wire       cell_ready,
    output reg [8:0]  cell_ordinal,
    output reg [3:0]  cell_value,
    output reg        commit_valid,
    input  wire       commit_ready,
    input  wire       result_available,
    output reg        result_ack,
    output reg        finished
);
    localparam ST_BEGIN  = 3'd0;
    localparam ST_CELLS  = 3'd1;
    localparam ST_COMMIT = 3'd2;
    localparam ST_WAIT   = 3'd3;
    localparam ST_DONE   = 3'd4;

    reg [2:0] state;
    reg [1:0] board_number;

    assign begin_width = 5'd3;
    assign begin_height = 5'd3;
    assign begin_mines = 9'd1;

    function [3:0] rom_cell;
        input [1:0] board_no;
        input [3:0] ordinal;
        begin
            case (board_no)
                0: case (ordinal)
                    0:rom_cell=1; 1:rom_cell=1; 2:rom_cell=1;
                    3:rom_cell=1; 4:rom_cell=9; 5:rom_cell=1;
                    6:rom_cell=1; 7:rom_cell=1; default:rom_cell=1;
                endcase
                1: case (ordinal)
                    0:rom_cell=9; 1:rom_cell=1; 2:rom_cell=0;
                    3:rom_cell=1; 4:rom_cell=1; 5:rom_cell=0;
                    6:rom_cell=0; 7:rom_cell=0; default:rom_cell=0;
                endcase
                default: case (ordinal)
                    0:rom_cell=0; 1:rom_cell=0; 2:rom_cell=0;
                    3:rom_cell=0; 4:rom_cell=1; 5:rom_cell=1;
                    6:rom_cell=0; 7:rom_cell=1; default:rom_cell=9;
                endcase
            endcase
        end
    endfunction

    always @* begin
        begin_valid = 0;
        cell_valid = 0;
        commit_valid = 0;
        begin_board_id = board_number + 1'b1;
        cell_value = rom_cell(board_number, cell_ordinal[3:0]);
        if (enable) begin
            if (state == ST_BEGIN) begin_valid = 1;
            if (state == ST_CELLS) cell_valid = 1;
            if (state == ST_COMMIT) commit_valid = 1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_BEGIN;
            board_number <= 0;
            cell_ordinal <= 0;
            result_ack <= 0;
            finished <= 0;
        end else begin
            result_ack <= 0;
            if (enable) begin
                case (state)
                    ST_BEGIN: if (begin_ready) begin
                        cell_ordinal <= 0;
                        state <= ST_CELLS;
                    end
                    ST_CELLS: if (cell_ready) begin
                        if (cell_ordinal == 8)
                            state <= ST_COMMIT;
                        else
                            cell_ordinal <= cell_ordinal + 1'b1;
                    end
                    ST_COMMIT: if (commit_ready)
                        state <= ST_WAIT;
                    ST_WAIT: if (result_available) begin
                        result_ack <= 1;
                        if (board_number == 2) begin
                            finished <= 1;
                            state <= ST_DONE;
                        end else begin
                            board_number <= board_number + 1'b1;
                            state <= ST_BEGIN;
                        end
                    end
                    default: state <= ST_DONE;
                endcase
            end
        end
    end
endmodule
