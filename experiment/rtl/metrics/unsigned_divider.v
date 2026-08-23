`timescale 1ns/1ps

// Unsigned restoring divider.  One result is produced in 32 clocks.
module unsigned_divider (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] numerator,
    input  wire [31:0] denominator,
    output reg         busy,
    output reg         done,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder_out,
    output reg         divide_by_zero
);
    reg [31:0] dividend_work;
    reg [31:0] divisor_work;
    reg [31:0] quotient_work;
    reg [32:0] remainder_work;
    reg [5:0] iteration;
    wire [32:0] shifted_remainder;
    wire subtract;
    wire [32:0] next_remainder;
    wire [31:0] next_quotient;

    assign shifted_remainder = {remainder_work[31:0],
                                dividend_work[31]};
    assign subtract = shifted_remainder >= {1'b0, divisor_work};
    assign next_remainder = subtract ?
        shifted_remainder - {1'b0, divisor_work} : shifted_remainder;
    assign next_quotient = {quotient_work[30:0], subtract};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            quotient <= 32'd0;
            remainder_out <= 32'd0;
            divide_by_zero <= 1'b0;
            dividend_work <= 32'd0;
            divisor_work <= 32'd0;
            quotient_work <= 32'd0;
            remainder_work <= 33'd0;
            iteration <= 6'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                divide_by_zero <= (denominator == 0);
                if (denominator == 0) begin
                    quotient <= 32'hffff_ffff;
                    remainder_out <= numerator;
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    dividend_work <= numerator;
                    divisor_work <= denominator;
                    quotient_work <= 32'd0;
                    remainder_work <= 33'd0;
                    iteration <= 6'd0;
                end
            end else if (busy) begin
                dividend_work <= {dividend_work[30:0], 1'b0};
                quotient_work <= next_quotient;
                remainder_work <= next_remainder;
                if (iteration == 6'd31) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    quotient <= next_quotient;
                    remainder_out <= next_remainder[31:0];
                end else begin
                    iteration <= iteration + 6'd1;
                end
            end
        end
    end
endmodule

