`timescale 1ns/1ps

// Submission top: deterministic local solver with eight regular probability
// feedback guesses, then saturating feedback while fewer than half of all safe
// cells are open, plus bounded edge-midpoint rescue.
module minesweeper_jtag_submission_local_top (
    input  wire       CLK_20MHZ,
    input  wire       RESET_N,
    input  wire [3:0] HEX_A,
    input  wire [3:0] HEX_B,
    output wire [7:0] SEG_A,
    output wire [7:0] SEG_B,
    output wire [7:0] SEG_C,
    output wire [7:0] SEG_D,
    output wire [7:0] SEG_E,
    output wire [7:0] SEG_F,
    output wire [7:0] SEG_G,
    output wire [7:0] SEG_H,
    output wire [8:0] SEG_SEL
);
    minesweeper_jtag_top #(
        .SIMULATION(0),
        .DETERMINISTIC_SOLVER(1),
        .FORCE_JTAG_MODE(1),
        .FORCE_FULL_SPEED(1),
        .MAX_PROBABILITY_GUESSES(15),
        .ENABLE_ADAPTIVE_FEEDBACK(0),
        .ENABLE_SATURATING_HALF_SAFE_FEEDBACK(1),
        .BASE_PROBABILITY_GUESSES(8),
        .ADAPTIVE_FEEDBACK_SAFE_THRESHOLD(32),
        .ENABLE_LOW_SCORE_EDGE_RESCUE(1),
        .LOW_SCORE_RESCUE_SAFE_THRESHOLD(16)
    ) u_top (
        .CLK_20MHZ(CLK_20MHZ), .RESET_N(RESET_N),
        .HEX_A(HEX_A), .HEX_B(HEX_B),
        .SEG_A(SEG_A), .SEG_B(SEG_B), .SEG_C(SEG_C), .SEG_D(SEG_D),
        .SEG_E(SEG_E), .SEG_F(SEG_F), .SEG_G(SEG_G), .SEG_H(SEG_H),
        .SEG_SEL(SEG_SEL)
    );
endmodule
