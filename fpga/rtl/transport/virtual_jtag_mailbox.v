`timescale 1ns/1ps

// A one-command CDC mailbox around the Intel/Altera Virtual JTAG primitive.
// Each 64-bit DR update posts a command; each DR capture returns the most
// recent response. The host must wait for engine_busy to clear between posts.
module virtual_jtag_mailbox #(
    parameter SIMULATION = 0
) (
    input  wire       clk,
    input  wire       reset,
    output reg        command_valid,
    input  wire       command_ready,
    output reg [63:0] command_word,
    input  wire [63:0] response_word,

    input  wire       sim_command_valid,
    input  wire [63:0] sim_command_word,
    output wire [63:0] sim_response_word
);
    assign sim_response_word = response_word;

    generate if (SIMULATION) begin : g_sim
        always @(posedge clk or posedge reset) begin
            if (reset) begin
                command_valid <= 0;
                command_word <= 0;
            end else begin
                command_valid <= 0;
                if (sim_command_valid && command_ready) begin
                    command_valid <= 1;
                    command_word <= sim_command_word;
                end
            end
        end
    end else begin : g_hw
        wire tck;
        wire tdi;
        wire tdo;
        wire virtual_state_cdr;
        wire virtual_state_sdr;
        wire virtual_state_udr;
        wire [0:0] ir_in;
        wire [0:0] ir_out = 1'b0;
        wire [63:0] tck_mailbox;
        wire post_toggle;
        wire scan_error;
        reg [2:0] post_sync;
        reg seen_toggle;

        sld_virtual_jtag #(
            .sld_auto_instance_index("YES"),
            .sld_instance_index(0),
            .sld_ir_width(1)
        ) u_vjtag (
            .ir_in(ir_in), .ir_out(ir_out), .tck(tck), .tdi(tdi), .tdo(tdo),
            .virtual_state_cdr(virtual_state_cdr),
            .virtual_state_sdr(virtual_state_sdr),
            .virtual_state_udr(virtual_state_udr)
        );

        virtual_jtag_shift64 u_shift64 (
            .tck(tck), .virtual_state_cdr(virtual_state_cdr),
            .virtual_state_sdr(virtual_state_sdr), .tdi(tdi), .tdo(tdo),
            .capture_word(response_word), .received_word(tck_mailbox),
            .received_toggle(post_toggle), .scan_error(scan_error)
        );

        always @(posedge clk or posedge reset) begin
            if (reset) begin
                post_sync <= 0;
                seen_toggle <= 0;
                command_valid <= 0;
                command_word <= 0;
            end else begin
                post_sync <= {post_sync[1:0], post_toggle};
                if (command_valid && command_ready)
                    command_valid <= 0;
                if (post_sync[2] != seen_toggle && !command_valid) begin
                    command_word <= tck_mailbox;
                    command_valid <= 1;
                    seen_toggle <= post_sync[2];
                end
            end
        end
    end endgenerate
endmodule
