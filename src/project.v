/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Internal signals for 16-bit ALU
    reg [15:0] operand_a, operand_b;
    reg [3:0] operation;
    wire [15:0] result;
    wire zero_flag, carry_flag, overflow_flag, negative_flag;
    
    // Input/Output mapping for 16-bit data through 8-bit interface
    reg [1:0] input_state;
    reg [15:0] result_reg;
    reg [3:0] flags_reg;
    
    // Configure IOs as outputs for result
    assign uio_oe = 8'hFF;
    
    // Output mapping: lower 8 bits of result
    assign uo_out = result_reg[7:0];
    // Upper 8 bits of result + flags
    assign uio_out = {flags_reg, result_reg[11:8]};
    
    // Instantiate 16-bit ALU
    alu_16bit alu_inst (
        .a(operand_a),
        .b(operand_b),
        .op(operation),
        .result(result),
        .zero(zero_flag),
        .carry(carry_flag),
        .overflow(overflow_flag),
        .negative(negative_flag)
    );
    
    // Input state machine for loading 16-bit operands
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a <= 16'h0000;
            operand_b <= 16'h0000;
            operation <= 4'h0;
            input_state <= 2'b00;
            result_reg <= 16'h0000;
            flags_reg <= 4'h0;
        end else begin
            case (input_state)
                2'b00: begin // Load operand A lower byte
                    operand_a[7:0] <= ui_in;
                    input_state <= 2'b01;
                end
                2'b01: begin // Load operand A upper byte + operation
                    operand_a[15:8] <= ui_in[7:4];
                    operation <= ui_in[3:0];
                    input_state <= 2'b10;
                end
                2'b10: begin // Load operand B lower byte
                    operand_b[7:0] <= ui_in;
                    input_state <= 2'b11;
                end
                2'b11: begin // Load operand B upper byte and execute
                    operand_b[15:8] <= ui_in;
                    result_reg <= result;
                    flags_reg <= {zero_flag, carry_flag, overflow_flag, negative_flag};
                    input_state <= 2'b00;
                end
            endcase
        end
    end

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, uio_in, 1'b0};

endmodule

// 16-bit ALU Core Module
module alu_16bit (
    input [15:0] a,
    input [15:0] b,
    input [3:0] op,
    output reg [15:0] result,
    output zero,
    output carry,
    output overflow,
    output negative
);

    // Internal signals
    wire [16:0] add_result, sub_result;
    wire [15:0] and_result, or_result, xor_result, not_result;
    wire [15:0] inc_result, dec_result;
    wire [31:0] mult_result;
    wire [15:0] div_result;
    reg carry_out, overflow_out;
    
    // Arithmetic operations
    assign add_result = {1'b0, a} + {1'b0, b};
    assign sub_result = {1'b0, a} - {1'b0, b};
    assign inc_result = a + 1'b1;
    assign dec_result = a - 1'b1;
    
    // Logical operations
    assign and_result = a & b;
    assign or_result = a | b;
    assign xor_result = a ^ b;
    assign not_result = ~a;
    
    // Simple multiplier (partial - lower 16 bits)
    assign mult_result = a * b;
    
    // Basic divider (simplified)
    assign div_result = (b != 0) ? a / b : 16'hFFFF;
    
    // Operation decoder and result multiplexer
    always @(*) begin
        carry_out = 1'b0;
        overflow_out = 1'b0;
        
        case (op)
            4'h0: begin // ADD
                result = add_result[15:0];
                carry_out = add_result[16];
                overflow_out = (a[15] == b[15]) && (result[15] != a[15]);
            end
            4'h1: begin // SUB
                result = sub_result[15:0];
                carry_out = sub_result[16];
                overflow_out = (a[15] != b[15]) && (result[15] != a[15]);
            end
            4'h2: begin // INC
                result = inc_result;
                carry_out = (a == 16'hFFFF);
                overflow_out = (a == 16'h7FFF);
            end
            4'h3: begin // DEC
                result = dec_result;
                carry_out = (a == 16'h0000);
                overflow_out = (a == 16'h8000);
            end
            4'h4: begin // MUL (lower 16 bits)
                result = mult_result[15:0];
                carry_out = |mult_result[31:16];
            end
            4'h5: begin // DIV
                result = div_result;
            end
            4'h6: result = 16'h0000; // Reserved arithmetic operation
            4'h7: result = 16'h0000; // Reserved arithmetic operation
            4'h8: result = and_result; // AND
            4'h9: result = or_result;  // OR
            4'hA: result = xor_result; // XOR
            4'hB: result = not_result; // NOT
            4'hC: result = a; // Pass A
            4'hD: result = b; // Pass B
            4'hE: result = 16'h0000; // Clear
            4'hF: result = 16'hFFFF; // Set all
            default: result = 16'h0000;
        endcase
    end
    
    // Flag generation
    assign zero = (result == 16'h0000);
    assign carry = carry_out;
    assign overflow = overflow_out;
    assign negative = result[15];

endmodule

// Additional helper modules for gate count optimization

// 16-bit Adder/Subtractor using carry-lookahead structure
module cla_16bit (
    input [15:0] a,
    input [15:0] b,
    input cin,
    input sub, // 1 for subtract, 0 for add
    output [15:0] sum,
    output cout,
    output overflow
);

    wire [15:0] b_xor = b ^ {16{sub}};
    wire cin_actual = cin ^ sub;
    
    // 4-bit CLA blocks
    wire [3:0] carry;
    wire [3:0] g, p; // Generate and propagate for each 4-bit block
    
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : cla_blocks
            cla_4bit cla4 (
                .a(a[4*i+3:4*i]),
                .b(b_xor[4*i+3:4*i]),
                .cin((i == 0) ? cin_actual : carry[i-1]),
                .sum(sum[4*i+3:4*i]),
                .cout(carry[i]),
                .g(g[i]),
                .p(p[i])
            );
        end
    endgenerate
    
    assign cout = carry[3];
    assign overflow = (a[15] == b_xor[15]) && (sum[15] != a[15]);

endmodule

// 4-bit Carry Lookahead Adder
module cla_4bit (
    input [3:0] a,
    input [3:0] b,
    input cin,
    output [3:0] sum,
    output cout,
    output g, p
);

    wire [3:0] gi, pi, ci;
    
    // Generate and propagate
    assign gi = a & b;
    assign pi = a ^ b;
    
    // Carry calculation
    assign ci[0] = cin;
    assign ci[1] = gi[0] | (pi[0] & ci[0]);
    assign ci[2] = gi[1] | (pi[1] & gi[0]) | (pi[1] & pi[0] & ci[0]);
    assign ci[3] = gi[2] | (pi[2] & gi[1]) | (pi[2] & pi[1] & gi[0]) | (pi[2] & pi[1] & pi[0] & ci[0]);
    
    // Sum calculation
    assign sum = pi ^ {ci[2:0], cin};
    assign cout = gi[3] | (pi[3] & ci[3]);
    
    // Block generate and propagate
    assign g = gi[3] | (pi[3] & gi[2]) | (pi[3] & pi[2] & gi[1]) | (pi[3] & pi[2] & pi[1] & gi[0]);
    assign p = &pi;

endmodule
