`timescale 1ns/1ps

// Solver-owned knowledge only. It never contains unopened board values.
module solver_state_ram #(
    parameter MAX_CELLS = 361
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       clear_start,
    output reg        clear_busy,
    output reg        clear_done,
    input  wire       write_valid,
    input  wire [8:0] write_index,
    input  wire [2:0] write_state,
    input  wire [3:0] write_clue,
    input  wire [8:0] read_index,
    output reg  [2:0] read_state,
    output reg  [3:0] read_clue
);
    localparam CELL_UNKNOWN = 3'd0;

    reg [6:0] knowledge_mem [0:MAX_CELLS-1];
    reg [6:0] read_data;
    reg [8:0] clear_index;
    wire memory_write = clear_busy ||
                        (write_valid && write_index < MAX_CELLS);
    wire [8:0] memory_write_index = clear_busy ? clear_index : write_index;
    wire [6:0] memory_write_data = clear_busy ?
        {4'd0, CELL_UNKNOWN} : {write_clue, write_state};

    always @* begin
        read_state = read_data[2:0];
        read_clue = read_data[6:3];
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clear_busy <= 1'b0;
            clear_done <= 1'b0;
            clear_index <= 9'd0;
        end else begin
            clear_done <= 1'b0;
            if (clear_start && !clear_busy) begin
                clear_busy <= 1'b1;
                clear_index <= 9'd0;
            end else if (clear_busy) begin
                if (clear_index == MAX_CELLS - 1) begin
                    clear_busy <= 1'b0;
                    clear_done <= 1'b1;
                end else begin
                    clear_index <= clear_index + 9'd1;
                end
            end
        end
    end

    // The read port is deliberately synchronous so Quartus can map the two
    // arrays to embedded memory instead of thousands of logic registers.
    always @(posedge clk) begin
        read_data <= knowledge_mem[read_index];
        if (memory_write)
            knowledge_mem[memory_write_index] <= memory_write_data;
    end
endmodule
