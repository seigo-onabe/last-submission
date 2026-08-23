`timescale 1ns/1ps

// Synchronous two-read constraint cache. Port A is shared between writes
// during dirty-clue rebuilds and reads during R5. Port B is read-only.
// Keeping valid bits in the owner lets a new board invalidate every record in
// one clock without adding a reset/clear network to the embedded RAM.
module solver_constraint_cache #(
    parameter MAX_CELLS = 361
) (
    input  wire       clk,
    input  wire       write_valid,
    input  wire [8:0] write_index,
    input  wire [7:0] write_mask,
    input  wire [3:0] write_remaining,
    input  wire [8:0] read_a_index,
    output reg  [7:0] read_a_mask,
    output reg  [3:0] read_a_remaining,
    input  wire [8:0] read_b_index,
    output reg  [7:0] read_b_mask,
    output reg  [3:0] read_b_remaining
);
    reg [11:0] constraint_mem [0:MAX_CELLS-1];
    reg [11:0] read_a_data;
    reg [11:0] read_b_data;

    always @* begin
        read_a_mask = read_a_data[7:0];
        read_a_remaining = read_a_data[11:8];
        read_b_mask = read_b_data[7:0];
        read_b_remaining = read_b_data[11:8];
    end

    always @(posedge clk) begin
        if (write_valid && write_index < MAX_CELLS)
            constraint_mem[write_index] <= {write_remaining, write_mask};
        else
            read_a_data <= constraint_mem[read_a_index];
        read_b_data <= constraint_mem[read_b_index];
    end
endmodule
