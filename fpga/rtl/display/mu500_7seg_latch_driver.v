`timescale 1ns/1ps

// MU500-7SEG has 64 shared data pins and nine active-high latch enables.
// SEL0..7 update rows A..H of seven-segment digits; SEL8 updates the 64 LEDs.
module mu500_7seg_latch_driver (
    input  wire         clk,
    input  wire         reset,
    input  wire [511:0] digit_segments,
    input  wire [63:0]  led_bitmap,
    output wire [7:0]   SEG_A,
    output wire [7:0]   SEG_B,
    output wire [7:0]   SEG_C,
    output wire [7:0]   SEG_D,
    output wire [7:0]   SEG_E,
    output wire [7:0]   SEG_F,
    output wire [7:0]   SEG_G,
    output wire [7:0]   SEG_H,
    output reg  [8:0]   SEG_SEL
);
    localparam ST_SETUP = 2'd0;
    localparam ST_LATCH = 2'd1;
    localparam ST_HOLD  = 2'd2;
    reg [1:0] state;
    reg [3:0] plane;
    reg [63:0] data_lines;

    assign SEG_A = data_lines[7:0];
    assign SEG_B = data_lines[15:8];
    assign SEG_C = data_lines[23:16];
    assign SEG_D = data_lines[31:24];
    assign SEG_E = data_lines[39:32];
    assign SEG_F = data_lines[47:40];
    assign SEG_G = data_lines[55:48];
    assign SEG_H = data_lines[63:56];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_SETUP;
            plane <= 4'd0;
            data_lines <= 64'd0;
            SEG_SEL <= 9'd0;
        end else begin
            case (state)
                ST_SETUP: begin
                    SEG_SEL <= 9'd0;
                    if (plane == 8)
                        data_lines <= led_bitmap;
                    else
                        data_lines <= digit_segments[plane*64 +: 64];
                    state <= ST_LATCH;
                end
                ST_LATCH: begin
                    SEG_SEL <= (9'b000000001 << plane);
                    state <= ST_HOLD;
                end
                default: begin
                    SEG_SEL <= 9'd0;
                    if (plane == 8)
                        plane <= 4'd0;
                    else
                        plane <= plane + 1'b1;
                    state <= ST_SETUP;
                end
            endcase
        end
    end
endmodule

