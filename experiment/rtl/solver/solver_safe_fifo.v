`timescale 1ns/1ps

// A bounded safe-cell queue. queued_bitmap prevents duplicate insertion.
module solver_safe_fifo #(
    parameter MAX_CELLS = 361
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       clear,
    input  wire       push_valid,
    input  wire [8:0] push_index,
    input  wire [4:0] push_x,
    input  wire [4:0] push_y,
    output wire       push_ready,
    output wire       push_duplicate,
    output wire       pop_valid,
    output wire [8:0] pop_index,
    output wire [4:0] pop_x,
    output wire [4:0] pop_y,
    input  wire       pop_ready,
    output reg  [8:0] count,
    output reg        overflow_error
);
    reg [9:0] queue_mem [0:MAX_CELLS-1];
    reg [8:0] head;
    reg [8:0] tail;
    reg [MAX_CELLS-1:0] queued_bitmap;
    wire [9:0] queue_head_data = queue_mem[head];

    wire push_in_range = push_index < MAX_CELLS;
    assign push_duplicate = push_in_range && queued_bitmap[push_index];
    assign push_ready = push_in_range && (count < MAX_CELLS) &&
                        !push_duplicate;
    assign pop_valid = (count != 0);
    assign pop_x = queue_head_data[4:0];
    assign pop_y = queue_head_data[9:5];
    assign pop_index = (pop_y << 4) + (pop_y << 1) + pop_y + pop_x;

    function [8:0] increment_pointer;
        input [8:0] value;
        begin
            increment_pointer = (value == MAX_CELLS - 1) ?
                                9'd0 : value + 9'd1;
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 9'd0;
            tail <= 9'd0;
            count <= 9'd0;
            queued_bitmap <= {MAX_CELLS{1'b0}};
            overflow_error <= 1'b0;
        end else if (clear) begin
            head <= 9'd0;
            tail <= 9'd0;
            count <= 9'd0;
            queued_bitmap <= {MAX_CELLS{1'b0}};
            overflow_error <= 1'b0;
        end else begin
            if (push_valid && !push_ready && !push_duplicate)
                overflow_error <= 1'b1;

            case ({push_valid && push_ready, pop_valid && pop_ready})
                2'b10: begin
                    queue_mem[tail] <= {push_y, push_x};
                    queued_bitmap[push_index] <= 1'b1;
                    tail <= increment_pointer(tail);
                    count <= count + 9'd1;
                end
                2'b01: begin
                    queued_bitmap[pop_index] <= 1'b0;
                    head <= increment_pointer(head);
                    count <= count - 9'd1;
                end
                2'b11: begin
                    queue_mem[tail] <= {push_y, push_x};
                    queued_bitmap[push_index] <= 1'b1;
                    queued_bitmap[pop_index] <= 1'b0;
                    tail <= increment_pointer(tail);
                    head <= increment_pointer(head);
                end
            endcase
        end
    end
endmodule
