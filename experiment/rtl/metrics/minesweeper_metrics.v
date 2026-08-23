`timescale 1ns/1ps

// Per-board and cumulative counters.  Scores are signed fixed point with four
// decimal places, matching truncation toward zero in the contest definition.
module minesweeper_metrics (
    input  wire        clk,
    input  wire        reset,
    input  wire        board_done,
    input  wire [4:0]  board_width,
    input  wire [4:0]  board_height,
    input  wire [8:0]  total_mines,
    input  wire [8:0]  opened_safe,
    input  wire [8:0]  opened_mines,
    input  wire [8:0]  selections,
    input  wire [31:0] board_cycles,
    output reg         busy,
    output reg         result_valid,
    output reg         protocol_error,
    output reg  [15:0] boards_processed,
    output reg  [15:0] boards_fully_solved,
    output reg  [8:0]  current_safe,
    output reg  [8:0]  current_mines,
    output reg  [8:0]  current_selections,
    output reg  [31:0] current_cycles,
    output reg  [63:0] total_cycles,
    output reg signed [31:0] current_score_scaled,
    output reg signed [31:0] total_score_scaled
);
    localparam S_IDLE       = 3'd0;
    localparam S_SAFE_START = 3'd1;
    localparam S_SAFE_WAIT  = 3'd2;
    localparam S_COMMIT     = 3'd5;

    reg [2:0] state;
    reg [9:0] safe_cells;
    reg [8:0] mines_latched;
    reg [31:0] safe_term;
    reg numerator_negative;
    reg divider_start;
    reg [31:0] divider_numerator;
    reg [31:0] divider_denominator;
    wire divider_busy;
    wire divider_done;
    wire [31:0] divider_quotient;
    wire [31:0] divider_remainder;
    wire divider_zero;
    wire [19:0] safe_product;
    wire [19:0] mine_product;
    wire signed [20:0] rational_difference;
    wire [20:0] rational_magnitude;
    wire signed [32:0] score_difference;

    assign safe_product = current_safe * mines_latched;
    assign mine_product = current_mines * safe_cells;
    assign rational_difference = $signed({1'b0, safe_product}) -
                                 $signed({1'b0, mine_product});
    assign rational_magnitude = rational_difference[20] ?
                                (~rational_difference + 21'd1) :
                                rational_difference;
    assign score_difference = numerator_negative ?
                              -$signed({1'b0, safe_term}) :
                              $signed({1'b0, safe_term});

    unsigned_divider u_divider (
        .clk(clk), .reset(reset), .start(divider_start),
        .numerator(divider_numerator),
        .denominator(divider_denominator),
        .busy(divider_busy), .done(divider_done),
        .quotient(divider_quotient), .remainder_out(divider_remainder),
        .divide_by_zero(divider_zero)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            busy <= 1'b0;
            result_valid <= 1'b0;
            protocol_error <= 1'b0;
            boards_processed <= 16'd0;
            boards_fully_solved <= 16'd0;
            current_safe <= 9'd0;
            current_mines <= 9'd0;
            current_selections <= 9'd0;
            current_cycles <= 32'd0;
            total_cycles <= 64'd0;
            current_score_scaled <= 32'sd0;
            total_score_scaled <= 32'sd0;
            safe_cells <= 10'd0;
            mines_latched <= 9'd0;
            safe_term <= 32'd0;
            numerator_negative <= 1'b0;
            divider_start <= 1'b0;
            divider_numerator <= 32'd0;
            divider_denominator <= 32'd0;
        end else begin
            result_valid <= 1'b0;
            divider_start <= 1'b0;
            if (board_done && (state != S_IDLE))
                protocol_error <= 1'b1;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (board_done) begin
                        busy <= 1'b1;
                        current_safe <= opened_safe;
                        current_mines <= opened_mines;
                        current_selections <= selections;
                        current_cycles <= board_cycles;
                        safe_cells <= board_width * board_height - total_mines;
                        mines_latched <= total_mines;
                        total_cycles <= total_cycles + board_cycles;
                        if ((total_mines == 0) ||
                            (total_mines >= board_width * board_height)) begin
                            protocol_error <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            state <= S_SAFE_START;
                        end
                    end
                end
                S_SAFE_START: begin
                    // Calculate the complete rational expression before
                    // division.  This matches truncation of the final score,
                    // unlike truncating its two fractions independently.
                    divider_numerator <= rational_magnitude * 32'd10000;
                    divider_denominator <= safe_cells * mines_latched;
                    numerator_negative <= rational_difference[20];
                    divider_start <= 1'b1;
                    state <= S_SAFE_WAIT;
                end
                S_SAFE_WAIT: if (divider_done) begin
                    safe_term <= divider_quotient;
                    state <= S_COMMIT;
                end
                S_COMMIT: begin
                    current_score_scaled <= score_difference[31:0];
                    total_score_scaled <= total_score_scaled +
                                          score_difference[31:0];
                    boards_processed <= boards_processed + 16'd1;
                    if (current_safe == safe_cells)
                        boards_fully_solved <= boards_fully_solved + 16'd1;
                    result_valid <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end
                default: begin
                    protocol_error <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
