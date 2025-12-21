`timescale 1ns / 1ps

module matrix_compute (
    input wire clk,
    input wire rst_n,
    input wire [3:0] current_mode,
    input wire [2:0] current_op,
    input wire [3:0] scalar,
    input wire [1:0] operand_sel,
    input wire op_start,
    input wire [3:0] operand1_m,
    input wire [3:0] operand1_n,
    input wire [199:0] operand1_data,
    input wire operand1_valid,
    input wire [3:0] operand2_m,
    input wire [3:0] operand2_n,
    input wire [199:0] operand2_data,
    input wire operand2_valid,
    
    output reg [3:0] result_m,
    output reg [3:0] result_n,
    output reg [399:0] result_mat_flat,
    output reg op_done,
    output reg [2:0] error_type,
    output reg display_en,
    output reg [1:0] display_type
);

    localparam S_OP_EXEC = 4'b0110;
    localparam OP_TRANSPOSE = 3'b000;
    localparam OP_ADD = 3'b001;
    localparam OP_SCALAR = 3'b010;
    localparam OP_MULTIPLY = 3'b011;
    localparam COMP_IDLE = 3'd0;
    localparam COMP_CHECK = 3'd1;
    localparam COMP_EXECUTE = 3'd2;
    localparam COMP_DONE = 3'd3;
    localparam COMP_ERROR = 3'd4;
    localparam ERR_NONE = 3'b000;
    localparam ERR_OP_MISMATCH = 3'b010;

    reg [2:0] state;
    reg [4:0] calc_idx;
    reg [4:0] total_elem;
    reg [3:0] calc_row;
    reg [3:0] calc_col;
    reg [3:0] calc_k;
    reg [15:0] acc;
    reg calc_busy;
    
    reg [3:0] saved_op1_m;
    reg [3:0] saved_op1_n;
    reg [3:0] saved_op2_n;
    
    reg op_start_d;
    wire op_start_pulse;
    
    wire [4:0] trans_src_idx;
    wire [4:0] trans_dst_idx;
    wire [4:0] mult_op1_idx;
    wire [4:0] mult_op2_idx;
    wire [4:0] mult_dst_idx;
    
    wire [7:0] trans_src_data;
    wire [7:0] add_op1_data;
    wire [7:0] add_op2_data;
    wire [7:0] scalar_op1_data;
    wire [7:0] mult_op1_data;
    wire [7:0] mult_op2_data;
    
    assign op_start_pulse = op_start && (!op_start_d);
    
    assign trans_src_idx = calc_row * saved_op1_n + calc_col;
    assign trans_dst_idx = calc_col * saved_op1_m + calc_row;
    assign mult_op1_idx = calc_row * saved_op1_n + calc_k;
    assign mult_op2_idx = calc_k * saved_op2_n + calc_col;
    assign mult_dst_idx = calc_row * saved_op2_n + calc_col;
    
    assign trans_src_data = operand1_data[trans_src_idx*8 +: 8];
    assign add_op1_data = operand1_data[calc_idx*8 +: 8];
    assign add_op2_data = operand2_data[calc_idx*8 +: 8];
    assign scalar_op1_data = operand1_data[calc_idx*8 +: 8];
    assign mult_op1_data = operand1_data[mult_op1_idx*8 +: 8];
    assign mult_op2_data = operand2_data[mult_op2_idx*8 +: 8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            op_start_d <= 1'b0;
        else
            op_start_d <= op_start;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= COMP_IDLE;
            result_m <= 4'd0;
            result_n <= 4'd0;
            result_mat_flat <= 400'd0;
            calc_idx <= 5'd0;
            total_elem <= 5'd0;
            calc_row <= 4'd0;
            calc_col <= 4'd0;
            calc_k <= 4'd0;
            acc <= 16'd0;
            calc_busy <= 1'b0;
            op_done <= 1'b0;
            error_type <= ERR_NONE;
            display_en <= 1'b0;
            display_type <= 2'd0;
            saved_op1_m <= 4'd0;
            saved_op1_n <= 4'd0;
            saved_op2_n <= 4'd0;
        end
        else begin
            op_done <= 1'b0;
            display_en <= 1'b0;
            
            case (state)
                COMP_IDLE: begin
                    if (current_mode == S_OP_EXEC && op_start_pulse) begin
                        state <= COMP_CHECK;
                        error_type <= ERR_NONE;
                        calc_idx <= 5'd0;
                        calc_row <= 4'd0;
                        calc_col <= 4'd0;
                        calc_k <= 4'd0;
                        acc <= 16'd0;
                        calc_busy <= 1'b0;
                        result_mat_flat <= 400'd0;
                    end
                end
                
                COMP_CHECK: begin
                    case (current_op)
                        OP_TRANSPOSE: begin
                            if (operand1_valid) begin
                                result_m <= operand1_n;
                                result_n <= operand1_m;
                                saved_op1_m <= operand1_m;
                                saved_op1_n <= operand1_n;
                                total_elem <= operand1_m * operand1_n;
                                state <= COMP_EXECUTE;
                            end
                            else begin
                                error_type <= ERR_OP_MISMATCH;
                                state <= COMP_ERROR;
                            end
                        end
                        
                        OP_ADD: begin
                            if (operand1_valid && operand2_valid && 
                                operand1_m == operand2_m && operand1_n == operand2_n) begin
                                result_m <= operand1_m;
                                result_n <= operand1_n;
                                saved_op1_m <= operand1_m;
                                saved_op1_n <= operand1_n;
                                total_elem <= operand1_m * operand1_n;
                                state <= COMP_EXECUTE;
                            end
                            else begin
                                error_type <= ERR_OP_MISMATCH;
                                state <= COMP_ERROR;
                            end
                        end
                        
                        OP_SCALAR: begin
                            if (operand1_valid) begin
                                result_m <= operand1_m;
                                result_n <= operand1_n;
                                saved_op1_m <= operand1_m;
                                saved_op1_n <= operand1_n;
                                total_elem <= operand1_m * operand1_n;
                                state <= COMP_EXECUTE;
                            end
                            else begin
                                error_type <= ERR_OP_MISMATCH;
                                state <= COMP_ERROR;
                            end
                        end
                        
                        OP_MULTIPLY: begin
                            if (operand1_valid && operand2_valid && operand1_n == operand2_m) begin
                                result_m <= operand1_m;
                                result_n <= operand2_n;
                                saved_op1_m <= operand1_m;
                                saved_op1_n <= operand1_n;
                                saved_op2_n <= operand2_n;
                                state <= COMP_EXECUTE;
                            end
                            else begin
                                error_type <= ERR_OP_MISMATCH;
                                state <= COMP_ERROR;
                            end
                        end
                        
                        default: begin
                            error_type <= ERR_OP_MISMATCH;
                            state <= COMP_ERROR;
                        end
                    endcase
                end
                
                COMP_EXECUTE: begin
                    case (current_op)
                        OP_TRANSPOSE: begin
                            result_mat_flat[trans_dst_idx*16 +: 16] <= {8'd0, trans_src_data};
                            
                            if (calc_col >= saved_op1_n - 1) begin
                                if (calc_row >= saved_op1_m - 1) begin
                                    state <= COMP_DONE;
                                end
                                else begin
                                    calc_col <= 4'd0;
                                    calc_row <= calc_row + 4'd1;
                                end
                            end
                            else begin
                                calc_col <= calc_col + 4'd1;
                            end
                        end
                        
                        OP_ADD: begin
                            result_mat_flat[calc_idx*16 +: 16] <= {8'd0, add_op1_data} + {8'd0, add_op2_data};
                            
                            if (calc_idx >= total_elem - 1) begin
                                state <= COMP_DONE;
                            end
                            else begin
                                calc_idx <= calc_idx + 5'd1;
                            end
                        end
                        
                        OP_SCALAR: begin
                            result_mat_flat[calc_idx*16 +: 16] <= scalar * scalar_op1_data;
                            
                            if (calc_idx >= total_elem - 1) begin
                                state <= COMP_DONE;
                            end
                            else begin
                                calc_idx <= calc_idx + 5'd1;
                            end
                        end
                        
                        OP_MULTIPLY: begin
                            if (!calc_busy) begin
                                calc_busy <= 1'b1;
                                acc <= 16'd0;
                                calc_k <= 4'd0;
                            end
                            else begin
                                acc <= acc + mult_op1_data * mult_op2_data;
                                
                                if (calc_k >= saved_op1_n - 1) begin
                                    result_mat_flat[mult_dst_idx*16 +: 16] <= acc + mult_op1_data * mult_op2_data;
                                    calc_busy <= 1'b0;
                                    
                                    if (calc_col >= saved_op2_n - 1) begin
                                        if (calc_row >= saved_op1_m - 1) begin
                                            state <= COMP_DONE;
                                        end
                                        else begin
                                            calc_col <= 4'd0;
                                            calc_row <= calc_row + 4'd1;
                                        end
                                    end
                                    else begin
                                        calc_col <= calc_col + 4'd1;
                                    end
                                end
                                else begin
                                    calc_k <= calc_k + 4'd1;
                                end
                            end
                        end
                        
                        default: state <= COMP_ERROR;
                    endcase
                end
                
                COMP_DONE: begin
                    op_done <= 1'b1;
                    display_en <= 1'b1;
                    display_type <= 2'b01;
                    state <= COMP_IDLE;
                end
                
                COMP_ERROR: begin
                    op_done <= 1'b1;
                    display_en <= 1'b1;
                    display_type <= 2'b10;
                    state <= COMP_IDLE;
                end
                
                default: state <= COMP_IDLE;
            endcase
        end
    end

endmodule