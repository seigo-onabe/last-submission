`timescale 1ns/1ps

// Holds one complete result until the selected transport acknowledges it.
module result_snapshot (
    input  wire       clk,
    input  wire       reset,
    input  wire       capture,
    input  wire [15:0] board_id,
    input  wire [4:0] width,
    input  wire [4:0] height,
    input  wire [8:0] total_mines,
    input  wire [8:0] selections,
    input  wire       stalled,
    input  wire [8:0] opened_safe,
    input  wire [8:0] opened_mines,
    input  wire [31:0] cycles,
    input  wire signed [31:0] score_scaled,
    input  wire       protocol_error_in,
    input  wire       acknowledge,
    output reg        available,
    output reg [15:0] result_board_id,
    output reg [4:0] result_width,
    output reg [4:0] result_height,
    output reg [8:0] result_total_mines,
    output reg [8:0] result_selections,
    output reg       result_stalled,
    output reg [8:0] result_opened_safe,
    output reg [8:0] result_opened_mines,
    output reg [31:0] result_cycles,
    output reg signed [31:0] result_score_scaled,
    output reg       result_protocol_error,
    output reg       overflow_error
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            available <= 0;
            result_board_id <= 0;
            result_width <= 0;
            result_height <= 0;
            result_total_mines <= 0;
            result_selections <= 0;
            result_stalled <= 0;
            result_opened_safe <= 0;
            result_opened_mines <= 0;
            result_cycles <= 0;
            result_score_scaled <= 0;
            result_protocol_error <= 0;
            overflow_error <= 0;
        end else begin
            if (acknowledge)
                available <= 0;
            if (capture) begin
                if (available && !acknowledge)
                    overflow_error <= 1;
                else begin
                    available <= 1;
                    result_board_id <= board_id;
                    result_width <= width;
                    result_height <= height;
                    result_total_mines <= total_mines;
                    result_selections <= selections;
                    result_stalled <= stalled;
                    result_opened_safe <= opened_safe;
                    result_opened_mines <= opened_mines;
                    result_cycles <= cycles;
                    result_score_scaled <= score_scaled;
                    result_protocol_error <= protocol_error_in;
                end
            end
        end
    end
endmodule
