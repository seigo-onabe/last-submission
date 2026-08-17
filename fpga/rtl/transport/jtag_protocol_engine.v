`timescale 1ns/1ps

// Executes 64-bit host commands delivered by the Virtual JTAG mailbox.
module jtag_protocol_engine #(
    parameter [15:0] BUILD_ID = 16'h0001
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       command_valid,
    output wire       command_ready,
    input  wire [63:0] command_word,
    output reg  [63:0] response_word,

    output reg        begin_valid,
    input  wire       begin_ready,
    output reg [15:0] begin_board_id,
    output reg [4:0]  begin_width,
    output reg [4:0]  begin_height,
    output reg [8:0]  begin_mines,
    output reg        cell_valid,
    input  wire       cell_ready,
    output reg [8:0]  cell_ordinal,
    output reg [3:0]  cell_value,
    output reg        commit_valid,
    input  wire       commit_ready,

    input  wire       solver_busy,
    input  wire       result_available,
    input  wire [15:0] result_board_id,
    input  wire [4:0] result_width,
    input  wire [4:0] result_height,
    input  wire [8:0] result_total_mines,
    input  wire [8:0] result_selections,
    input  wire       result_stalled,
    input  wire [8:0] result_opened_safe,
    input  wire [8:0] result_opened_mines,
    input  wire [31:0] result_cycles,
    input  wire signed [31:0] result_score_scaled,
    input  wire       result_protocol_error,
    output reg        result_ack,
    output reg        transport_error
);
    localparam OP_NOP      = 4'h0;
    localparam OP_BEGIN    = 4'h1;
    localparam OP_DATA     = 4'h2;
    localparam OP_COMMIT   = 4'h3;
    localparam OP_STATUS   = 4'h4;
    localparam OP_RESULT_A = 4'h5;
    localparam OP_RESULT_B = 4'h6;
    localparam OP_ACK      = 4'h7;
    localparam OP_VERSION  = 4'h8;
    localparam OP_PING     = 4'h9;
    localparam OP_RESULT_C = 4'hA;

    localparam EX_IDLE   = 2'd0;
    localparam EX_BEGIN  = 2'd1;
    localparam EX_DATA   = 2'd2;
    localparam EX_COMMIT = 2'd3;

    reg [1:0] exec_state;
    reg [3:0] data_remaining;
    reg [43:0] data_values;
    reg [15:0] running_crc;
    reg crc_error;

    assign command_ready = (exec_state == EX_IDLE);

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data;
        integer i;
        reg [15:0] crc;
        begin
            crc = crc_in ^ (data << 8);
            for (i=0; i<8; i=i+1)
                crc = crc[15] ? (crc << 1) ^ 16'h1021 : (crc << 1);
            crc16_byte = crc;
        end
    endfunction

    task set_status;
        begin
            response_word <= {
                4'hA, BUILD_ID,
                8'd0,
                1'b0, transport_error, crc_error, result_protocol_error,
                result_available, solver_busy,
                (exec_state != EX_IDLE), begin_ready,
                28'd0
            };
        end
    endtask

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exec_state <= EX_IDLE;
            response_word <= {4'hA, BUILD_ID, 44'd0};
            begin_valid <= 0;
            begin_board_id <= 0;
            begin_width <= 0;
            begin_height <= 0;
            begin_mines <= 0;
            cell_valid <= 0;
            cell_ordinal <= 0;
            cell_value <= 0;
            commit_valid <= 0;
            result_ack <= 0;
            transport_error <= 0;
            data_remaining <= 0;
            data_values <= 0;
            running_crc <= 16'hFFFF;
            crc_error <= 0;
        end else begin
            result_ack <= 0;

            case (exec_state)
                EX_BEGIN: begin
                    begin_valid <= 1;
                    if (begin_valid && begin_ready) begin
                        begin_valid <= 0;
                        exec_state <= EX_IDLE;
                    end
                end
                EX_DATA: begin
                    cell_valid <= 1;
                    if (cell_valid && cell_ready) begin
                        running_crc <= crc16_byte(running_crc, {4'd0, cell_value});
                        data_values <= data_values >> 4;
                        cell_value <= data_values[7:4];
                        cell_ordinal <= cell_ordinal + 1'b1;
                        if (data_remaining == 1) begin
                            cell_valid <= 0;
                            exec_state <= EX_IDLE;
                        end
                        data_remaining <= data_remaining - 1'b1;
                    end
                end
                EX_COMMIT: begin
                    commit_valid <= 1;
                    if (commit_valid && commit_ready) begin
                        commit_valid <= 0;
                        exec_state <= EX_IDLE;
                    end
                end
                default: begin
                    begin_valid <= 0;
                    cell_valid <= 0;
                    commit_valid <= 0;
                    if (command_valid) begin
                        case (command_word[63:60])
                            OP_NOP, OP_STATUS: set_status();
                            OP_VERSION:
                                response_word <= {4'hB, BUILD_ID, 8'd2, 8'd0, 28'd0};
                            OP_PING:
                                response_word <= {4'hD,
                                    command_word[59:0] ^ 60'h5A5A5A5A5A5A5A5};
                            OP_BEGIN: begin
                                if (!begin_ready || result_available) begin
                                    transport_error <= 1;
                                end else begin
                                    begin_board_id <= command_word[59:44];
                                    begin_width <= command_word[43:39];
                                    begin_height <= command_word[38:34];
                                    begin_mines <= command_word[33:25];
                                    running_crc <= crc16_byte(
                                        crc16_byte(
                                            crc16_byte(
                                                crc16_byte(16'hFFFF, {3'd0, command_word[43:39]}),
                                                {3'd0, command_word[38:34]}),
                                            command_word[32:25]),
                                        {7'd0, command_word[33]});
                                    crc_error <= 0;
                                    exec_state <= EX_BEGIN;
                                end
                            end
                            OP_DATA: begin
                                if (command_word[50:47] > 10) begin
                                    transport_error <= 1;
                                end else begin
                                    cell_ordinal <= command_word[59:51];
                                    cell_value <= command_word[3:0];
                                    data_remaining <= command_word[50:47] + 1'b1;
                                    data_values <= command_word[43:0];
                                    exec_state <= EX_DATA;
                                end
                            end
                            OP_COMMIT: begin
                                if (running_crc != command_word[15:0]) begin
                                    crc_error <= 1;
                                    transport_error <= 1;
                                end else begin
                                    exec_state <= EX_COMMIT;
                                end
                            end
                            OP_RESULT_A: begin
                                response_word <= {
                                    4'hC, result_board_id, result_width,
                                    result_height, result_total_mines,
                                    result_selections[2:0], result_opened_safe,
                                    result_opened_mines, 4'd0
                                };
                            end
                            OP_RESULT_B:
                                response_word <= {result_cycles, result_score_scaled};
                            OP_RESULT_C:
                                response_word <= {4'hE, result_selections,
                                                  result_stalled, 50'd0};
                            OP_ACK: begin
                                if (result_available)
                                    result_ack <= 1;
                                else
                                    transport_error <= 1;
                            end
                            default: transport_error <= 1;
                        endcase
                    end
                end
            endcase
        end
    end
endmodule
