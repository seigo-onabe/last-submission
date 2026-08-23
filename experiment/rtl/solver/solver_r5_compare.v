`timescale 1ns/1ps

// Compares two cached 3x3 clue constraints in a common 5x5 coordinate
// window. Trivial differences are emitted as direct deductions; non-trivial
// differences are emitted for the derived-constraint store.
module solver_r5_compare (
    input  wire [4:0] center_a_x,
    input  wire [4:0] center_a_y,
    input  wire [7:0] local_mask_a,
    input  wire [3:0] remaining_a,
    input  wire [4:0] center_b_x,
    input  wire [4:0] center_b_y,
    input  wire [7:0] local_mask_b,
    input  wire [3:0] remaining_b,
    output reg        applicable,
    output reg        contradiction,
    output reg        result_is_mine,
    output reg [24:0] difference_mask,
    output reg        derived_valid,
    output reg [4:0]  difference_mines,
    output reg [4:0]  difference_count,
    output reg signed [6:0] base_x,
    output reg signed [6:0] base_y
);
    reg [24:0] mask_a;
    reg [24:0] mask_b;
    reg [24:0] raw_difference;
    integer direction;
    integer ax;
    integer ay;
    integer bx;
    integer by;
    integer position;
    integer difference_count_calc;
    integer difference_mines_calc;

    function integer count_ones25;
        input [24:0] value;
        integer bit_index;
        begin
            count_ones25 = 0;
            for (bit_index = 0; bit_index < 25; bit_index = bit_index + 1)
                count_ones25 = count_ones25 + value[bit_index];
        end
    endfunction

    always @* begin
        base_x = ($signed({1'b0, center_a_x}) <
                  $signed({1'b0, center_b_x}) ? center_a_x : center_b_x) - 1;
        base_y = ($signed({1'b0, center_a_y}) <
                  $signed({1'b0, center_b_y}) ? center_a_y : center_b_y) - 1;
        mask_a = 25'd0;
        mask_b = 25'd0;

        for (direction = 0; direction < 8; direction = direction + 1) begin
            case (direction)
                0: begin ax = center_a_x - 1; ay = center_a_y - 1; end
                1: begin ax = center_a_x;     ay = center_a_y - 1; end
                2: begin ax = center_a_x + 1; ay = center_a_y - 1; end
                3: begin ax = center_a_x - 1; ay = center_a_y;     end
                4: begin ax = center_a_x + 1; ay = center_a_y;     end
                5: begin ax = center_a_x - 1; ay = center_a_y + 1; end
                6: begin ax = center_a_x;     ay = center_a_y + 1; end
                default: begin ax = center_a_x + 1; ay = center_a_y + 1; end
            endcase
            case (direction)
                0: begin bx = center_b_x - 1; by = center_b_y - 1; end
                1: begin bx = center_b_x;     by = center_b_y - 1; end
                2: begin bx = center_b_x + 1; by = center_b_y - 1; end
                3: begin bx = center_b_x - 1; by = center_b_y;     end
                4: begin bx = center_b_x + 1; by = center_b_y;     end
                5: begin bx = center_b_x - 1; by = center_b_y + 1; end
                6: begin bx = center_b_x;     by = center_b_y + 1; end
                default: begin bx = center_b_x + 1; by = center_b_y + 1; end
            endcase
            position = (ay - base_y) * 5 + (ax - base_x);
            if (local_mask_a[direction] && position >= 0 && position < 25)
                mask_a[position] = 1'b1;
            position = (by - base_y) * 5 + (bx - base_x);
            if (local_mask_b[direction] && position >= 0 && position < 25)
                mask_b[position] = 1'b1;
        end

        applicable = 1'b0;
        contradiction = 1'b0;
        result_is_mine = 1'b0;
        difference_mask = 25'd0;
        derived_valid = 1'b0;
        difference_mines = 5'd0;
        difference_count = 5'd0;
        raw_difference = 25'd0;
        difference_count_calc = 0;
        difference_mines_calc = 0;

        if (mask_a != 0 && mask_a == mask_b) begin
            if (remaining_a != remaining_b)
                contradiction = 1'b1;
        end else if (mask_a != 0 && mask_b != 0 &&
                     (mask_a & ~mask_b) == 0) begin
            raw_difference = mask_b & ~mask_a;
            difference_count_calc = count_ones25(raw_difference);
            difference_mines_calc = remaining_b - remaining_a;
            if (difference_mines_calc < 0 ||
                difference_mines_calc > difference_count_calc) begin
                contradiction = 1'b1;
            end else begin
                difference_mask = raw_difference;
                difference_mines = difference_mines_calc[4:0];
                difference_count = difference_count_calc[4:0];
                if (difference_mines_calc == 0 ||
                    difference_mines_calc == difference_count_calc) begin
                    applicable = difference_count_calc != 0;
                    result_is_mine = difference_mines_calc != 0;
                end else begin
                    derived_valid = difference_count_calc != 0;
                end
            end
        end else if (mask_a != 0 && mask_b != 0 &&
                     (mask_b & ~mask_a) == 0) begin
            raw_difference = mask_a & ~mask_b;
            difference_count_calc = count_ones25(raw_difference);
            difference_mines_calc = remaining_a - remaining_b;
            if (difference_mines_calc < 0 ||
                difference_mines_calc > difference_count_calc) begin
                contradiction = 1'b1;
            end else begin
                difference_mask = raw_difference;
                difference_mines = difference_mines_calc[4:0];
                difference_count = difference_count_calc[4:0];
                if (difference_mines_calc == 0 ||
                    difference_mines_calc == difference_count_calc) begin
                    applicable = difference_count_calc != 0;
                    result_is_mine = difference_mines_calc != 0;
                end else begin
                    derived_valid = difference_count_calc != 0;
                end
            end
        end
    end
endmodule
