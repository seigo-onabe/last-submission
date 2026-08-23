`timescale 1ns/1ps

// Fixed-length Virtual-JTAG data-register shifter.  A received word is
// committed on the 64th qualified Shift-DR clock, so command delivery does
// not depend on observing Update-DR after the Quartus Tcl scan returns.
module virtual_jtag_shift64 (
    input  wire        tck,
    input  wire        virtual_state_cdr,
    input  wire        virtual_state_sdr,
    input  wire        tdi,
    output wire        tdo,
    input  wire [63:0] capture_word,
    output reg  [63:0] received_word,
    output reg         received_toggle,
    output reg         scan_error
);
    reg [63:0] shift_reg;
    reg [6:0] shift_count;
    reg scan_active;
    wire [63:0] shifted_word = {tdi, shift_reg[63:1]};

    initial begin
        shift_reg = 0;
        shift_count = 0;
        scan_active = 0;
        received_word = 0;
        received_toggle = 0;
        scan_error = 0;
    end

    assign tdo = shift_reg[0];

    always @(posedge tck) begin
        if (virtual_state_cdr) begin
            if (scan_active && shift_count != 0)
                scan_error <= 1;
            shift_reg <= capture_word;
            shift_count <= 0;
            scan_active <= 1;
        end else if (virtual_state_sdr) begin
            shift_reg <= shifted_word;
            if (!scan_active) begin
                scan_error <= 1;
            end else if (shift_count == 7'd63) begin
                received_word <= shifted_word;
                received_toggle <= ~received_toggle;
                shift_count <= 0;
                scan_active <= 0;
            end else begin
                shift_count <= shift_count + 1'b1;
            end
        end
    end
endmodule
