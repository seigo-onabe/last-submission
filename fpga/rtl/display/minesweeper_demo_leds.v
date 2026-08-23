`timescale 1ns/1ps

// Explicit five-state controller for the MU500 4x16 LED matrix.
module minesweeper_demo_leds #(parameter CLOCK_HZ=20000000) (
    input wire clk, input wire reset, input wire heartbeat,
    input wire batch_begin, input wire [15:0] expected_boards,
    input wire board_complete, input wire batch_end,
    input wire error_active, input wire overflow_active,
    output reg [63:0] led_bitmap,
    output wire batch_active, output wire batch_done,
    output wire [2:0] debug_state,
    output wire [15:0] debug_completed_count,
    output wire [15:0] debug_expected_boards
);
    localparam [2:0] LED_WAIT=0, LED_RUN=1, LED_FINISH=2,
                     LED_FINISHED=3, LED_ERROR=4;
    localparam [63:0] OUTER=64'hFFFF80018001FFFF;
    localparam [63:0] INNER=64'h00007FFE7FFE0000;
    localparam [63:0] CHECK_A=64'hAAAA5555AAAA5555;
    localparam [63:0] CHECK_B=64'h5555AAAA5555AAAA;
    localparam integer TICK_DIV=CLOCK_HZ/10; // 100 ms

    reg [2:0] state;
    reg [31:0] tick_counter;
    reg [15:0] expected_latched, completed_count;
    reg [16:0] progress_accum;
    reg [6:0] lit_count;
    reg progress_updating;
    reg [4:0] animation_step;
    reg [2:0] slow_div;

    assign batch_active=(state==LED_RUN);
    assign batch_done=(state==LED_FINISH)||(state==LED_FINISHED);
    assign debug_state=state;
    assign debug_completed_count=completed_count;
    assign debug_expected_boards=expected_latched;

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
            state<=LED_WAIT; tick_counter<=0; expected_latched<=1;
            completed_count<=0; progress_accum<=0; lit_count<=0;
            progress_updating<=0; animation_step<=0; slow_div<=0;
        end else begin
            if(tick_counter>=TICK_DIV-1) begin
                tick_counter<=0; slow_div<=slow_div+1'b1;
                if(state==LED_FINISH) begin
                    if(animation_step>=20) begin state<=LED_FINISHED; animation_step<=0; end
                    else animation_step<=animation_step+1'b1;
                end
            end else tick_counter<=tick_counter+1'b1;

            // Error has highest priority and remains latched until a clean
            // BATCH_BEGIN explicitly starts a new demonstration.
            if(error_active||overflow_active) begin
                state<=LED_ERROR; progress_updating<=0;
            end else if(batch_begin) begin
                state<=LED_RUN;
                expected_latched<=(expected_boards==0)?16'd1:expected_boards;
                completed_count<=0; progress_accum<=0; lit_count<=0;
                progress_updating<=0; animation_step<=0;
            end else case(state)
                LED_RUN: begin
                    if(board_complete) begin
                        completed_count<=completed_count+1'b1;
                        progress_accum<=progress_accum+17'd64;
                        progress_updating<=1;
                        if(completed_count+1'b1>=expected_latched) begin
                            state<=LED_FINISH; lit_count<=64;
                            animation_step<=0; progress_updating<=0;
                        end
                    end else if(progress_updating) begin
                        if(progress_accum>=expected_latched&&lit_count<64) begin
                            progress_accum<=progress_accum-expected_latched;
                            lit_count<=lit_count+1'b1;
                        end else progress_updating<=0;
                    end
                    if(batch_end) begin
                        state<=LED_FINISH; lit_count<=64;
                        animation_step<=0; progress_updating<=0;
                    end
                end
                default: begin end
            endcase
        end
    end

    always @* begin
        led_bitmap=64'd0;
        case(state)
            LED_WAIT: if(heartbeat) begin
                led_bitmap[23]=1; led_bitmap[24]=1;
                led_bitmap[39]=1; led_bitmap[40]=1;
            end
            LED_RUN: begin
                led_bitmap=progress_mask(lit_count);
                if(lit_count<64&&slow_div[0])
                    led_bitmap=led_bitmap|progress_mask(lit_count+1'b1);
            end
            LED_FINISH: begin
                case(animation_step)
                    0,1:led_bitmap=64'hFFFFFFFFFFFFFFFF;
                    3,5,11:led_bitmap=OUTER;
                    7,9,12:led_bitmap=INNER;
                    13,15,17,19,20:led_bitmap=64'hFFFFFFFFFFFFFFFF;
                    default:led_bitmap=64'd0;
                endcase
            end
            LED_FINISHED:led_bitmap=OUTER|(slow_div[2]?INNER:64'd0);
            LED_ERROR:led_bitmap=slow_div[0]?CHECK_A:CHECK_B;
            default:led_bitmap=64'd0;
        endcase
    end
endmodule
