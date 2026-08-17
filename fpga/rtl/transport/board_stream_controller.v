`timescale 1ns/1ps

// Converts a source-neutral board transaction into the existing cfg/load/start
// interface. Cells are supplied in compact row-major order and translated to
// the core's fixed 19-column stride.
module board_stream_controller (
    input  wire       clk,
    input  wire       reset,

    input  wire       begin_valid,
    output wire       begin_ready,
    input  wire [15:0] begin_board_id,
    input  wire [4:0] begin_width,
    input  wire [4:0] begin_height,
    input  wire [8:0] begin_mines,

    input  wire       cell_valid,
    output wire       cell_ready,
    input  wire [8:0] cell_ordinal,
    input  wire [3:0] cell_value,

    input  wire       commit_valid,
    output wire       commit_ready,

    output wire       cfg_valid,
    input  wire       cfg_ready,
    output reg  [4:0] cfg_width,
    output reg  [4:0] cfg_height,
    output reg  [8:0] cfg_total_mines,
    output wire       load_valid,
    input  wire       load_ready,
    output wire [8:0] load_index,
    output wire [3:0] load_value,
    output reg        start_solver,

    input  wire       result_valid,
    output reg        board_done,
    output reg [15:0] active_board_id,
    output reg        protocol_error
);
    localparam ST_IDLE   = 3'd0;
    localparam ST_CFG    = 3'd1;
    localparam ST_LOAD   = 3'd2;
    localparam ST_COMMIT = 3'd3;
    localparam ST_RUN    = 3'd4;

    reg [2:0] state;
    reg [8:0] expected_ordinal;
    reg [8:0] expected_cells;
    reg [4:0] load_x;
    reg [4:0] load_y;

    wire header_legal = begin_width >= 1 && begin_width <= 19 &&
                        begin_height >= 1 && begin_height <= 19 &&
                        begin_mines >= 1 &&
                        begin_mines < begin_width * begin_height;

    assign begin_ready = (state == ST_IDLE);
    assign cell_ready = (state == ST_LOAD) && load_ready;
    assign commit_ready = (state == ST_COMMIT);
    assign cfg_valid = (state == ST_CFG);
    assign load_valid = (state == ST_LOAD) && cell_valid;
    assign load_index = (load_y << 4) + (load_y << 1) + load_y + load_x;
    assign load_value = cell_value;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            expected_ordinal <= 0;
            expected_cells <= 0;
            load_x <= 0;
            load_y <= 0;
            cfg_width <= 0;
            cfg_height <= 0;
            cfg_total_mines <= 0;
            start_solver <= 0;
            board_done <= 0;
            active_board_id <= 0;
            protocol_error <= 0;
        end else begin
            board_done <= 0;
            start_solver <= 0;

            case (state)
                ST_IDLE: begin
                    if (begin_valid) begin
                        if (!header_legal) begin
                            protocol_error <= 1;
                        end else begin
                            active_board_id <= begin_board_id;
                            cfg_width <= begin_width;
                            cfg_height <= begin_height;
                            cfg_total_mines <= begin_mines;
                            expected_cells <= begin_width * begin_height;
                            expected_ordinal <= 0;
                            load_x <= 0;
                            load_y <= 0;
                            state <= ST_CFG;
                        end
                    end
                end

                ST_CFG: begin
                    if (cfg_ready) begin
                        state <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (cell_valid && load_ready) begin
                        if (cell_ordinal != expected_ordinal || cell_value > 9) begin
                            protocol_error <= 1;
                            state <= ST_IDLE;
                        end else begin
                            expected_ordinal <= expected_ordinal + 1'b1;
                            if (load_x + 1'b1 == cfg_width) begin
                                load_x <= 0;
                                load_y <= load_y + 1'b1;
                            end else begin
                                load_x <= load_x + 1'b1;
                            end
                            if (expected_ordinal + 1'b1 == expected_cells) begin
                                state <= ST_COMMIT;
                            end
                        end
                    end
                end

                ST_COMMIT: begin
                    if (commit_valid) begin
                        start_solver <= 1;
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (result_valid) begin
                        board_done <= 1;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
