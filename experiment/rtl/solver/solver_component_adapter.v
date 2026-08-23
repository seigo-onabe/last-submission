`timescale 1ns/1ps

// Converts cached clue constraints (8-neighbor local masks) and derived R5
// constraints (25-bit 5x5 masks) into the cell-index stream consumed by
// solver_component_builder. Board storage always uses the fixed stride 19.
module solver_component_adapter (
    input  wire              clk,
    input  wire              reset,
    input  wire              start,
    output wire              start_ready,
    input  wire              is_derived,
    input  wire [4:0]        board_width,
    input  wire [4:0]        board_height,
    input  wire [4:0]        center_x,
    input  wire [4:0]        center_y,
    input  wire signed [6:0] base_x,
    input  wire signed [6:0] base_y,
    input  wire [7:0]        local_mask,
    input  wire [24:0]       derived_mask,
    input  wire [4:0]        mines,
    output wire              builder_begin_valid,
    input  wire              builder_begin_ready,
    output wire [4:0]        builder_begin_mines,
    output wire              builder_cell_valid,
    input  wire              builder_cell_ready,
    output reg [8:0]         builder_cell_index,
    output wire              builder_end_valid,
    input  wire              builder_end_ready,
    output reg               done,
    output reg               coordinate_error
);
    localparam ST_IDLE  = 3'd0;
    localparam ST_BEGIN = 3'd1;
    localparam ST_SCAN  = 3'd2;
    localparam ST_EMIT  = 3'd3;
    localparam ST_END   = 3'd4;

    reg [2:0] state;
    reg active_derived;
    reg [4:0] active_width;
    reg [4:0] active_height;
    reg [4:0] active_center_x;
    reg [4:0] active_center_y;
    reg signed [6:0] active_base_x;
    reg signed [6:0] active_base_y;
    reg [24:0] active_mask;
    reg [4:0] active_mines;
    reg [4:0] position;
    integer cell_x_calc;
    integer cell_y_calc;
    integer cell_index_calc;
    reg position_selected;
    reg position_last;

    assign start_ready = state == ST_IDLE;
    assign builder_begin_valid = state == ST_BEGIN;
    assign builder_begin_mines = active_mines;
    assign builder_cell_valid = state == ST_EMIT;
    assign builder_end_valid = state == ST_END;

    always @* begin
        cell_x_calc = 0;
        cell_y_calc = 0;
        if (active_derived) begin
            cell_x_calc = active_base_x + (position % 5);
            cell_y_calc = active_base_y + (position / 5);
            position_selected = active_mask[position];
            position_last = position == 24;
        end else begin
            case (position[2:0])
                0: begin cell_x_calc = active_center_x - 1;
                         cell_y_calc = active_center_y - 1; end
                1: begin cell_x_calc = active_center_x;
                         cell_y_calc = active_center_y - 1; end
                2: begin cell_x_calc = active_center_x + 1;
                         cell_y_calc = active_center_y - 1; end
                3: begin cell_x_calc = active_center_x - 1;
                         cell_y_calc = active_center_y; end
                4: begin cell_x_calc = active_center_x + 1;
                         cell_y_calc = active_center_y; end
                5: begin cell_x_calc = active_center_x - 1;
                         cell_y_calc = active_center_y + 1; end
                6: begin cell_x_calc = active_center_x;
                         cell_y_calc = active_center_y + 1; end
                default: begin cell_x_calc = active_center_x + 1;
                               cell_y_calc = active_center_y + 1; end
            endcase
            position_selected = active_mask[position];
            position_last = position == 7;
        end
        cell_index_calc = (cell_y_calc << 4) + (cell_y_calc << 1) +
                          cell_y_calc + cell_x_calc;
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            done <= 1'b0;
            coordinate_error <= 1'b0;
            builder_cell_index <= 9'd0;
            position <= 5'd0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        active_derived <= is_derived;
                        active_width <= board_width;
                        active_height <= board_height;
                        active_center_x <= center_x;
                        active_center_y <= center_y;
                        active_base_x <= base_x;
                        active_base_y <= base_y;
                        active_mask <= is_derived ?
                                       derived_mask : {17'd0, local_mask};
                        active_mines <= mines;
                        coordinate_error <= 1'b0;
                        position <= 5'd0;
                        state <= ST_BEGIN;
                    end
                end

                ST_BEGIN: begin
                    if (builder_begin_ready)
                        state <= ST_SCAN;
                end

                ST_SCAN: begin
                    if (!position_selected) begin
                        if (position_last)
                            state <= ST_END;
                        else
                            position <= position + 1'b1;
                    end else if (cell_x_calc < 0 || cell_y_calc < 0 ||
                                 cell_x_calc >= active_width ||
                                 cell_y_calc >= active_height) begin
                        coordinate_error <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        builder_cell_index <= cell_index_calc[8:0];
                        state <= ST_EMIT;
                    end
                end

                ST_EMIT: begin
                    if (builder_cell_ready) begin
                        if (position_last)
                            state <= ST_END;
                        else begin
                            position <= position + 1'b1;
                            state <= ST_SCAN;
                        end
                    end
                end

                ST_END: begin
                    if (builder_end_ready) begin
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    coordinate_error <= 1'b1;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
