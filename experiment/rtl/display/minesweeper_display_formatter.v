`timescale 1ns/1ps

// Fixed decimal layout for all 64 MU500-7SEG digits.  Binary-to-BCD uses one
// shared 32-cycle double-dabble engine, avoiding long combinational dividers.
module minesweeper_display_formatter (
    input wire clk, input wire reset,
    input wire [15:0] boards_processed,
    input wire [15:0] boards_fully_solved,
    input wire [15:0] current_board_number,
    input wire [8:0] selections,
    input wire [8:0] opened_safe, input wire [8:0] opened_mines,
    input wire [4:0] board_width, input wire [4:0] board_height,
    input wire [8:0] total_mines, input wire [3:0] status_code,
    input wire [31:0] current_cycles, input wire [63:0] total_cycles,
    input wire signed [31:0] current_score_scaled,
    input wire signed [31:0] total_score_scaled,
    output reg [511:0] segments, output wire overflow
);
    localparam ST_CLEAR=0, ST_LOAD=1, ST_CONVERT=2, ST_WRITE=3, ST_COMMIT=4;
    reg [2:0] state;
    reg [3:0] field;
    reg [5:0] shift_count;
    reg [31:0] binary_work;
    reg [31:0] bcd_work;
    reg [31:0] bcd_adjusted;
    reg [511:0] work_segments;
    reg field_negative;
    integer j;

    reg [15:0] s_processed, s_solved, s_board_number;
    reg [8:0] s_selections;
    reg [8:0] s_safe, s_mines_opened, s_total_mines;
    reg [4:0] s_width, s_height;
    reg [3:0] s_status;
    reg [31:0] s_current_cycles;
    reg [63:0] s_total_cycles;
    reg signed [31:0] s_current_score, s_total_score;

    assign overflow = (boards_processed > 9999) ||
        (boards_fully_solved > 9999) || (current_board_number > 9999) ||
        (current_cycles > 99999999) || (total_cycles > 99999999) ||
        ((total_score_scaled < 0) &&
         ((~total_score_scaled + 1'b1) > 9999999)) ||
        ((total_score_scaled >= 0) && (total_score_scaled > 99999999));

    function [7:0] enc;
        input [3:0] d;
        begin case(d)
            0:enc=8'hFC; 1:enc=8'h60; 2:enc=8'hDA; 3:enc=8'hF2;
            4:enc=8'h66; 5:enc=8'hB6; 6:enc=8'hBE; 7:enc=8'hE0;
            8:enc=8'hFE; 9:enc=8'hF6; default:enc=8'h00;
        endcase end
    endfunction
    function [31:0] mag;
        input signed [31:0] v;
        begin mag = v[31] ? (~v + 1'b1) : v; end
    endfunction
    function [31:0] cap4;
        input [31:0] v; begin cap4=(v>9999)?9999:v; end
    endfunction
    function [31:0] cap8;
        input [63:0] v; begin cap8=(v>99999999)?99999999:v[31:0]; end
    endfunction

    // Add-three stage of double dabble.  The following shift is registered.
    always @* begin
        bcd_adjusted = bcd_work;
        for (j=0; j<8; j=j+1)
            if (bcd_work[j*4 +: 4] >= 5)
                bcd_adjusted[j*4 +: 4] = bcd_work[j*4 +: 4] + 4'd3;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=ST_CLEAR; field<=0; shift_count<=0;
            binary_work<=0; bcd_work<=0; work_segments<=0; segments<=0;
            field_negative<=0;
        end else case(state)
            ST_CLEAR: begin
                s_processed<=boards_processed; s_solved<=boards_fully_solved;
                s_board_number<=current_board_number; s_selections<=selections;
                s_safe<=opened_safe; s_mines_opened<=opened_mines;
                s_width<=board_width; s_height<=board_height;
                s_total_mines<=total_mines; s_status<=status_code;
                s_current_cycles<=current_cycles; s_total_cycles<=total_cycles;
                s_current_score<=current_score_scaled;
                s_total_score<=total_score_scaled;
                work_segments<=0; field<=0; state<=ST_LOAD;
            end
            ST_LOAD: begin
                bcd_work<=0; shift_count<=0; field_negative<=0;
                case(field)
                    0: binary_work<=cap4(s_processed);
                    1: binary_work<=cap4(s_solved);
                    2: binary_work<=cap4(s_board_number);
                    3: binary_work<=s_selections;
                    4: binary_work<=s_safe;
                    5: binary_work<=s_mines_opened;
                    6: binary_work<=s_width;
                    7: binary_work<=s_height;
                    8: binary_work<=s_total_mines;
                    9: binary_work<=cap8({32'd0,s_current_cycles});
                    10: binary_work<=cap8(s_total_cycles);
                    11: begin
                        binary_work<=mag(s_current_score);
                        field_negative<=s_current_score[31];
                    end
                    default: begin
                        field_negative<=s_total_score[31];
                        if (s_total_score[31] && mag(s_total_score)>9999999)
                            binary_work<=9999999;
                        else if (!s_total_score[31] && mag(s_total_score)>99999999)
                            binary_work<=99999999;
                        else binary_work<=mag(s_total_score);
                    end
                endcase
                state<=ST_CONVERT;
            end
            ST_CONVERT: begin
                bcd_work<={bcd_adjusted[30:0],binary_work[31]};
                binary_work<={binary_work[30:0],1'b0};
                if (shift_count==31) state<=ST_WRITE;
                else shift_count<=shift_count+1'b1;
            end
            ST_WRITE: begin
                case(field)
                    0: for(j=0;j<4;j=j+1) work_segments[(0+j)*8 +:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    1: for(j=0;j<4;j=j+1) work_segments[(4+j)*8 +:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    2: for(j=0;j<4;j=j+1) work_segments[(8+j)*8 +:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    3: for(j=0;j<4;j=j+1) work_segments[(12+j)*8+:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    4: for(j=0;j<4;j=j+1) work_segments[(16+j)*8+:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    5: for(j=0;j<4;j=j+1) work_segments[(20+j)*8+:8]<=enc(bcd_work[(3-j)*4 +:4]);
                    6: for(j=0;j<2;j=j+1) work_segments[(24+j)*8+:8]<=enc(bcd_work[(1-j)*4 +:4]);
                    7: for(j=0;j<2;j=j+1) work_segments[(26+j)*8+:8]<=enc(bcd_work[(1-j)*4 +:4]);
                    8: for(j=0;j<3;j=j+1) work_segments[(28+j)*8+:8]<=enc(bcd_work[(2-j)*4 +:4]);
                    9: for(j=0;j<8;j=j+1) work_segments[(32+j)*8+:8]<=enc(bcd_work[(7-j)*4 +:4]);
                    10:for(j=0;j<8;j=j+1) work_segments[(40+j)*8+:8]<=enc(bcd_work[(7-j)*4 +:4]);
                    11:begin
                        for(j=0;j<8;j=j+1) work_segments[(48+j)*8+:8]<=enc(bcd_work[(7-j)*4 +:4]);
                        work_segments[51*8]<=1'b1;
                        if(field_negative) work_segments[48*8+:8]<=8'h02;
                    end
                    default:begin
                        for(j=0;j<8;j=j+1) work_segments[(56+j)*8+:8]<=enc(bcd_work[(7-j)*4 +:4]);
                        work_segments[59*8]<=1'b1;
                        if(field_negative) work_segments[56*8+:8]<=8'h02;
                    end
                endcase
                if(field==12) begin
                    work_segments[31*8+:8]<=enc(s_status);
                    state<=ST_COMMIT;
                end else begin field<=field+1'b1; state<=ST_LOAD; end
            end
            ST_COMMIT: begin segments<=work_segments; state<=ST_CLEAR; end
            default: state<=ST_CLEAR;
        endcase
    end
endmodule
