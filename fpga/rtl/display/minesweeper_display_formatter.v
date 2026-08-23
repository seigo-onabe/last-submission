`timescale 1ns/1ps

// Demonstration-oriented 4-row x 16-column formatter. The upper rows show
// batch progress and outcomes; the lower rows show aggregate measurements.
module minesweeper_display_formatter (
    input wire clk, input wire reset,
    input wire [15:0] boards_processed,
    input wire [15:0] boards_fully_solved,
    input wire [63:0] total_cycles,
    input wire signed [31:0] total_score_scaled,
    input wire batch_active, input wire batch_done, input wire display_error,
    output reg [511:0] segments, output wire overflow
);
    localparam ST_CLEAR=0, ST_LABEL=1, ST_LOAD=2, ST_CONVERT=3,
               ST_WRITE=4, ST_COMMIT=5;
    reg [2:0] state, field;
    reg [5:0] shift_count;
    reg [31:0] binary_work, bcd_work, bcd_adjusted;
    reg [511:0] work_segments;
    reg field_negative;
    reg [15:0] s_processed, s_solved, s_partial;
    reg [63:0] s_total_cycles;
    reg signed [31:0] s_total_score;
    reg s_batch_active, s_batch_done, s_error, s_cycle_overflow, s_score_overflow;
    integer j;

    wire score_negative_overflow = total_score_scaled[31] &&
        ((~total_score_scaled + 1'b1) > 32'd9999999);
    wire score_positive_overflow = !total_score_scaled[31] &&
        (total_score_scaled > 32'sd99999999);
    assign overflow = (total_cycles > 64'd99999999) ||
                      score_negative_overflow || score_positive_overflow;

    // Segment order is {a,b,c,d,e,f,g,dp}; letters are 7-segment approximations.
    function [7:0] glyph;
        input [5:0] c;
        begin case (c)
            0:glyph=8'hFC; 1:glyph=8'h60; 2:glyph=8'hDA; 3:glyph=8'hF2;
            4:glyph=8'h66; 5:glyph=8'hB6; 6:glyph=8'hBE; 7:glyph=8'hE0;
            8:glyph=8'hFE; 9:glyph=8'hF6;
            10:glyph=8'hEE; 11:glyph=8'h3E; 12:glyph=8'h9C; // A b C
            13:glyph=8'h7A; 14:glyph=8'h9E; 15:glyph=8'h8E; // d E F
            16:glyph=8'h1C; 17:glyph=8'h2A; 18:glyph=8'h3A; // L n o
            19:glyph=8'h0A; 20:glyph=8'hB6; 21:glyph=8'h1E; // r S t
            22:glyph=8'h76; 23:glyph=8'hCE; 24:glyph=8'h7C; // Y P U
            25:glyph=8'h00; default:glyph=8'h02;            // blank, dash
        endcase end
    endfunction
    function [31:0] magnitude;
        input signed [31:0] v;
        begin magnitude = v[31] ? (~v + 1'b1) : v; end
    endfunction
    always @* begin
        bcd_adjusted = bcd_work;
        for (j=0; j<8; j=j+1)
            if (bcd_work[j*4 +: 4] >= 5)
                bcd_adjusted[j*4 +: 4] = bcd_work[j*4 +: 4] + 4'd3;
    end
    task put_glyph;
        input integer position; input [5:0] code;
        begin work_segments[position*8 +: 8] <= glyph(code); end
    endtask

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=ST_CLEAR; field<=0; shift_count<=0; binary_work<=0;
            bcd_work<=0; work_segments<=0; segments<=0; field_negative<=0;
        end else case (state)
            ST_CLEAR: begin
                s_processed<=boards_processed; s_solved<=boards_fully_solved;
                s_partial<=boards_processed-boards_fully_solved;
                s_total_cycles<=total_cycles; s_total_score<=total_score_scaled;
                s_batch_active<=batch_active; s_batch_done<=batch_done; s_error<=display_error;
                s_cycle_overflow<=total_cycles>64'd99999999;
                s_score_overflow<=score_negative_overflow||score_positive_overflow;
                work_segments<=0; field<=0; state<=ST_LABEL;
            end
            ST_LABEL: begin
                // Row 1: boArd 0000 <state>
                put_glyph(0,11); put_glyph(1,18); put_glyph(2,10); put_glyph(3,19); put_glyph(4,13);
                // Row 2: FULL0000PArt0000
                put_glyph(16,15); put_glyph(17,24); put_glyph(18,16); put_glyph(19,16);
                put_glyph(24,23); put_glyph(25,10); put_glyph(26,19); put_glyph(27,21);
                // Rows 3 and 4 labels.
                put_glyph(33,12); put_glyph(34,22); put_glyph(35,12); put_glyph(36,16); put_glyph(37,14);
                put_glyph(49,20); put_glyph(50,12); put_glyph(51,18); put_glyph(52,19); put_glyph(53,14);
                if (s_error) begin
                    put_glyph(11,14); put_glyph(12,19); put_glyph(13,19);
                end else if (s_batch_done) begin
                    put_glyph(11,13); put_glyph(12,18); put_glyph(13,17); put_glyph(14,14);
                end else if (s_batch_active) begin
                    put_glyph(11,19); put_glyph(12,24); put_glyph(13,17);
                end else begin
                    put_glyph(11,24); put_glyph(12,10); put_glyph(13,17); put_glyph(14,21);
                end
                state<=ST_LOAD;
            end
            ST_LOAD: begin
                bcd_work<=0; shift_count<=0; field_negative<=0;
                case(field)
                    0:binary_work<=(s_processed>9999)?9999:s_processed;
                    1:binary_work<=(s_solved>9999)?9999:s_solved;
                    2:binary_work<=(s_partial>9999)?9999:s_partial;
                    3:binary_work<=s_cycle_overflow?0:s_total_cycles[31:0];
                    default:begin binary_work<=s_score_overflow?0:magnitude(s_total_score); field_negative<=s_total_score[31]; end
                endcase
                state<=ST_CONVERT;
            end
            ST_CONVERT: begin
                bcd_work<={bcd_adjusted[30:0],binary_work[31]};
                binary_work<={binary_work[30:0],1'b0};
                if(shift_count==31) state<=ST_WRITE; else shift_count<=shift_count+1'b1;
            end
            ST_WRITE: begin
                case(field)
                    0:for(j=0;j<4;j=j+1) work_segments[(6+j)*8+:8]<=glyph(bcd_work[(3-j)*4+:4]);
                    1:for(j=0;j<4;j=j+1) work_segments[(20+j)*8+:8]<=glyph(bcd_work[(3-j)*4+:4]);
                    2:for(j=0;j<4;j=j+1) work_segments[(28+j)*8+:8]<=glyph(bcd_work[(3-j)*4+:4]);
                    3:for(j=0;j<8;j=j+1) work_segments[(40+j)*8+:8]<=s_cycle_overflow?glyph(63):glyph(bcd_work[(7-j)*4+:4]);
                    default:begin
                        for(j=0;j<8;j=j+1) work_segments[(56+j)*8+:8]<=s_score_overflow?glyph(63):glyph(bcd_work[(7-j)*4+:4]);
                        work_segments[59*8]<=1'b1;
                        if(field_negative&&!s_score_overflow) work_segments[56*8+:8]<=glyph(63);
                    end
                endcase
                if(field==4) state<=ST_COMMIT; else begin field<=field+1'b1; state<=ST_LOAD; end
            end
            ST_COMMIT:begin segments<=work_segments; state<=ST_CLEAR; end
            default:state<=ST_CLEAR;
        endcase
    end
endmodule
