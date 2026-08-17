`timescale 1ns/1ps

// Clock-enable generator.  The FPGA clock is never gated; only the solver and
// game state machines are paused.  Setting 0 pauses and F runs every cycle.
module solver_speed_control #(
    parameter CLOCK_HZ = 20000000
) (
    input  wire       clk,
    input  wire       reset,
    input  wire [3:0] setting,
    output reg        run_enable,
    output reg        heartbeat
);
    reg [31:0] divider;
    reg [31:0] counter;
    reg [31:0] heartbeat_counter;

    always @* begin
        case (setting)
            4'h0: divider = 32'hffff_ffff; // explicit pause below
            4'h1: divider = CLOCK_HZ / 1;
            4'h2: divider = CLOCK_HZ / 2;
            4'h3: divider = CLOCK_HZ / 5;
            4'h4: divider = CLOCK_HZ / 10;
            4'h5: divider = CLOCK_HZ / 20;
            4'h6: divider = CLOCK_HZ / 50;
            4'h7: divider = CLOCK_HZ / 100;
            4'h8: divider = CLOCK_HZ / 200;
            4'h9: divider = CLOCK_HZ / 500;
            4'hA: divider = CLOCK_HZ / 1000;
            4'hB: divider = CLOCK_HZ / 5000;
            4'hC: divider = CLOCK_HZ / 10000;
            4'hD: divider = CLOCK_HZ / 100000;
            4'hE: divider = CLOCK_HZ / 1000000;
            default: divider = 32'd1;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 32'd0;
            run_enable <= 1'b0;
            heartbeat_counter <= 32'd0;
            heartbeat <= 1'b0;
        end else begin
            run_enable <= 1'b0;
            if (setting == 4'hF) begin
                run_enable <= 1'b1;
                counter <= 32'd0;
            end else if (setting == 4'h0) begin
                counter <= 32'd0;
            end else if (counter >= divider - 1) begin
                counter <= 32'd0;
                run_enable <= 1'b1;
            end else begin
                counter <= counter + 32'd1;
            end

            if (heartbeat_counter >= (CLOCK_HZ / 2) - 1) begin
                heartbeat_counter <= 32'd0;
                heartbeat <= ~heartbeat;
            end else begin
                heartbeat_counter <= heartbeat_counter + 32'd1;
            end
        end
    end
endmodule

