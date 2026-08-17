`timescale 1ns/1ps

// Active-low mechanical button conditioner.  A press pulse is emitted only
// after the synchronized input has stayed low for DEBOUNCE_CYCLES clocks.
// Release merely rearms the next press and never emits a pulse.
module button_press_debouncer #(
    parameter DEBOUNCE_CYCLES = 400000,
    parameter COUNTER_WIDTH = 19
) (
    input  wire clk,
    input  wire reset,
    input  wire button_n,
    output reg  stable_n,
    output reg  press_pulse
);
    reg sync_meta;
    reg sync_value;
    reg [COUNTER_WIDTH-1:0] stable_counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_meta <= 1'b1;
            sync_value <= 1'b1;
            stable_n <= 1'b1;
            stable_counter <= {COUNTER_WIDTH{1'b0}};
            press_pulse <= 1'b0;
        end else begin
            sync_meta <= button_n;
            sync_value <= sync_meta;
            press_pulse <= 1'b0;

            if (sync_value == stable_n) begin
                stable_counter <= {COUNTER_WIDTH{1'b0}};
            end else if (stable_counter == DEBOUNCE_CYCLES - 1) begin
                stable_counter <= {COUNTER_WIDTH{1'b0}};
                stable_n <= sync_value;
                if (stable_n && !sync_value)
                    press_pulse <= 1'b1;
            end else begin
                stable_counter <= stable_counter + 1'b1;
            end
        end
    end
endmodule

