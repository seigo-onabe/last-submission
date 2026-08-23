`timescale 1ns/1ps

// Hash table for non-trivial R5 difference constraints. Masks are normalized
// to their top-left occupied cell before hashing, so equivalent global sets
// produced from different 5x5 windows compare equal.
module solver_derived_constraint_store #(
    parameter TABLE_SIZE = 256,
    parameter MAX_PROBES = 32
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        clear,
    input  wire        insert_valid,
    output wire        insert_ready,
    input  wire signed [6:0] insert_base_x,
    input  wire signed [6:0] insert_base_y,
    input  wire [24:0] insert_mask,
    input  wire [4:0]  insert_mines,
    input  wire [7:0]  insert_generation,
    output reg         done,
    output reg         inserted,
    output reg         duplicate,
    output reg         contradiction,
    output reg         overflow,
    output reg [8:0]   stored_count,
    input  wire        scan_valid,
    output wire        scan_ready,
    input  wire [7:0]  scan_index,
    output reg         scan_response_valid,
    output reg         scan_slot_valid,
    output wire [24:0] scan_mask,
    output wire signed [6:0] scan_base_x,
    output wire signed [6:0] scan_base_y,
    output wire [4:0]  scan_mines,
    output wire [7:0]  scan_generation
);
    localparam ST_IDLE = 3'd0;
    localparam ST_NORMALIZE_Y = 3'd1;
    localparam ST_NORMALIZE_X = 3'd2;
    localparam ST_READ = 3'd3;
    localparam ST_COMPARE = 3'd4;

    reg [2:0] state;
    reg [TABLE_SIZE-1:0] slot_valid;
    reg [51:0] constraint_mem [0:TABLE_SIZE-1];
    reg [51:0] read_data;
    reg [7:0] probe_index;
    reg [5:0] probe_count;
    reg [24:0] pending_mask;
    reg signed [6:0] pending_base_x;
    reg signed [6:0] pending_base_y;
    reg [4:0] pending_mines;
    reg [7:0] pending_generation;

    wire [24:0] read_mask = read_data[24:0];
    wire signed [6:0] read_base_x = read_data[31:25];
    wire signed [6:0] read_base_y = read_data[38:32];
    wire [4:0] read_mines = read_data[43:39];
    wire [7:0] read_generation = read_data[51:44];
    wire internal_read_request = state == ST_READ &&
                                 slot_valid[probe_index];
    wire external_read_request = scan_valid && scan_ready;
    wire [7:0] shared_read_index = internal_read_request ?
                                   probe_index : scan_index;

    assign insert_ready = state == ST_IDLE;
    assign scan_ready = state == ST_IDLE && !insert_valid;
    assign scan_mask = read_data[24:0];
    assign scan_base_x = read_data[31:25];
    assign scan_base_y = read_data[38:32];
    assign scan_mines = read_data[43:39];
    assign scan_generation = read_data[51:44];

    function integer count_ones25;
        input [24:0] value;
        integer index;
        begin
            count_ones25 = 0;
            for (index = 0; index < 25; index = index + 1)
                count_ones25 = count_ones25 + value[index];
        end
    endfunction

    function [7:0] hash_key;
        input [24:0] mask;
        input [6:0] base_x;
        input [6:0] base_y;
        begin
            hash_key = mask[7:0] ^ mask[15:8] ^
                       {mask[23:16]} ^ {7'd0, mask[24]} ^
                       {1'b0, base_x} ^ {1'b0, base_y};
        end
    endfunction

    always @(posedge clk) begin
        if (reset || clear) begin
            state <= ST_IDLE;
            slot_valid <= {TABLE_SIZE{1'b0}};
            done <= 1'b0;
            inserted <= 1'b0;
            duplicate <= 1'b0;
            contradiction <= 1'b0;
            overflow <= 1'b0;
            stored_count <= 9'd0;
            probe_index <= 8'd0;
            probe_count <= 6'd0;
            scan_response_valid <= 1'b0;
            scan_slot_valid <= 1'b0;
        end else begin
            done <= 1'b0;
            scan_response_valid <= external_read_request;
            if (external_read_request)
                scan_slot_valid <= slot_valid[scan_index];
            if (internal_read_request || external_read_request)
                read_data <= constraint_mem[shared_read_index];
            case (state)
                ST_IDLE: begin
                    if (insert_valid) begin
                        inserted <= 1'b0;
                        duplicate <= 1'b0;
                        contradiction <= 1'b0;
                        overflow <= 1'b0;
                        if (insert_mask == 0 || insert_mines == 0 ||
                            insert_mines >= count_ones25(insert_mask)) begin
                            contradiction <= 1'b1;
                            done <= 1'b1;
                        end else begin
                            pending_mask <= insert_mask;
                            pending_base_x <= insert_base_x;
                            pending_base_y <= insert_base_y;
                            pending_mines <= insert_mines;
                            pending_generation <= insert_generation;
                            probe_count <= 6'd0;
                            state <= ST_NORMALIZE_Y;
                        end
                    end
                end

                ST_NORMALIZE_Y: begin
                    if (pending_mask[4:0] == 0) begin
                        pending_mask <= pending_mask >> 5;
                        pending_base_y <= pending_base_y + 1'b1;
                    end else begin
                        state <= ST_NORMALIZE_X;
                    end
                end

                ST_NORMALIZE_X: begin
                    if (!(pending_mask[0] || pending_mask[5] ||
                          pending_mask[10] || pending_mask[15] ||
                          pending_mask[20])) begin
                        pending_mask <= {
                            1'b0, pending_mask[24:21],
                            1'b0, pending_mask[19:16],
                            1'b0, pending_mask[14:11],
                            1'b0, pending_mask[9:6],
                            1'b0, pending_mask[4:1]
                        };
                        pending_base_x <= pending_base_x + 1'b1;
                    end else begin
                        probe_index <= hash_key(pending_mask,
                                                pending_base_x,
                                                pending_base_y);
                        state <= ST_READ;
                    end
                end

                ST_READ: begin
                    if (!slot_valid[probe_index]) begin
                        constraint_mem[probe_index] <=
                            {pending_generation, pending_mines,
                             pending_base_y, pending_base_x, pending_mask};
                        slot_valid[probe_index] <= 1'b1;
                        stored_count <= stored_count + 1'b1;
                        inserted <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_COMPARE;
                    end
                end

                ST_COMPARE: begin
                    if (read_generation == pending_generation &&
                        read_base_x == pending_base_x &&
                        read_base_y == pending_base_y &&
                        read_mask == pending_mask) begin
                        if (read_mines == pending_mines)
                            duplicate <= 1'b1;
                        else
                            contradiction <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (probe_count + 1'b1 >= MAX_PROBES) begin
                        overflow <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        probe_index <= probe_index + 1'b1;
                        probe_count <= probe_count + 1'b1;
                        state <= ST_READ;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
