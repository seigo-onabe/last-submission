`timescale 1ns/1ps

module minesweeper_demo_leds #(parameter CLOCK_HZ=20000000) (
    input wire clk, input wire reset, input wire heartbeat,
    input wire batch_begin, input wire [15:0] expected_boards,
    input wire board_complete, input wire batch_end,
    input wire error_active, input wire overflow_active,
    output reg [63:0] led_bitmap, output reg batch_active, output reg batch_done
);
    localparam [63:0] OUTER=64'hFFFF80018001FFFF;
    localparam [63:0] INNER=64'h00007FFE7FFE0000;
    localparam [63:0] CHECK_A=64'hAAAA5555AAAA5555;
    localparam [63:0] CHECK_B=64'h5555AAAA5555AAAA;
    localparam integer TICK_DIV=CLOCK_HZ/10;
    reg [31:0] tick_counter;
    reg [15:0] expected_latched;
    reg [16:0] progress_accum;
    reg [6:0] lit_count;
    reg progress_updating;
    reg [5:0] animation_step;
    reg [2:0] slow_div;
    integer row, col, logical_index, physical_index;

    function [63:0] progress_mask;
        input [6:0] count;
        integer frow, fcol, findex, fphysical;
        begin
            progress_mask=64'd0;
            for(findex=0;findex<64;findex=findex+1) begin
                frow=findex/16; fcol=findex%16;
                fphysical=frow*16+((frow%2)?(15-fcol):fcol);
                if(findex<count) progress_mask[fphysical]=1'b1;
            end
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            tick_counter<=0; expected_latched<=0; progress_accum<=0; lit_count<=0;
            progress_updating<=0; animation_step<=0; slow_div<=0; batch_active<=0; batch_done<=0;
        end else begin
            if(tick_counter>=TICK_DIV-1) begin
                tick_counter<=0; slow_div<=slow_div+1'b1;
                if(batch_done&&animation_step<31) animation_step<=animation_step+1'b1;
            end else tick_counter<=tick_counter+1'b1;
            if(batch_begin) begin
                expected_latched<=(expected_boards==0)?16'd1:expected_boards;
                progress_accum<=0; lit_count<=0; progress_updating<=0;
                animation_step<=0; batch_active<=1; batch_done<=0;
            end else begin
                if(board_complete&&batch_active) begin progress_accum<=progress_accum+17'd64; progress_updating<=1; end
                else if(progress_updating) begin
                    if(progress_accum>=expected_latched&&lit_count<64) begin
                        progress_accum<=progress_accum-expected_latched; lit_count<=lit_count+1'b1;
                    end else progress_updating<=0;
                end
                if(batch_end) begin batch_active<=0; batch_done<=1; lit_count<=64; animation_step<=0; end
            end
        end
    end

    always @* begin
        led_bitmap=64'd0;
        if(error_active) led_bitmap=slow_div[0]?CHECK_A:CHECK_B;
        else if(batch_done) begin
            case(animation_step)
                0,1,4,6,8,10,12,14,16,18,20:led_bitmap=64'hFFFFFFFFFFFFFFFF;
                2,3,7,11,15,19:led_bitmap=64'd0;
                5,9:led_bitmap=OUTER;
                13,17:led_bitmap=INNER;
                default:led_bitmap=OUTER|(slow_div[2]?INNER:64'd0);
            endcase
        end else if(batch_active) begin
            led_bitmap=progress_mask(lit_count);
            if(lit_count<64&&slow_div[0]) led_bitmap=led_bitmap|progress_mask(lit_count+1'b1);
            if(overflow_active) led_bitmap[63]=slow_div[0];
        end else begin
            if(heartbeat) begin led_bitmap[23]=1; led_bitmap[24]=1; led_bitmap[39]=1; led_bitmap[40]=1; end
            if(overflow_active) led_bitmap[63]=slow_div[0];
        end
    end
endmodule
