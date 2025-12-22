`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_compute - 修复版
// 修复内容:
//   1. 改进矩阵乘法的累加逻辑，修复时序问题
//   2. 添加更完善的错误检测
//   3. 优化状态机转换逻辑
//////////////////////////////////////////////////////////////////////////////

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

    // 状态参数
    localparam S_OP_EXEC = 4'b0110;
    
    // 运算类型
    localparam OP_TRANSPOSE = 3'b000;
    localparam OP_ADD = 3'b001;
    localparam OP_SCALAR = 3'b010;
    localparam OP_MULTIPLY = 3'b011;
    localparam OP_CONV = 3'b100;
    
    // 计算状态机
    localparam COMP_IDLE = 3'd0;
    localparam COMP_CHECK = 3'd1;
    localparam COMP_EXECUTE = 3'd2;
    localparam COMP_MULT_ACC = 3'd3;  // 新增：乘法累加状态
    localparam COMP_DONE = 3'd4;
    localparam COMP_ERROR = 3'd5;
    
    // 错误类型
    localparam ERR_NONE = 3'b000;
    localparam ERR_OP_MISMATCH = 3'b010;
    localparam ERR_INVALID_OP = 3'b011;

    // 内部寄存器
    reg [2:0] state;
    reg [4:0] calc_idx;
    reg [4:0] total_elem;
    reg [3:0] calc_row;
    reg [3:0] calc_col;
    reg [3:0] calc_k;
    reg [15:0] acc;
    
    // 保存的操作数维度
    reg [3:0] saved_op1_m;
    reg [3:0] saved_op1_n;
    reg [3:0] saved_op2_m;
    reg [3:0] saved_op2_n;
    
    // 边沿检测
    reg op_start_d;
    wire op_start_pulse;
    
    // 索引计算
    wire [4:0] trans_src_idx;
    wire [4:0] trans_dst_idx;
    wire [4:0] add_idx;
    wire [4:0] mult_op1_idx;
    wire [4:0] mult_op2_idx;
    wire [4:0] mult_dst_idx;
    
    // 数据提取
    wire [7:0] trans_src_data;
    wire [7:0] add_op1_data;
    wire [7:0] add_op2_data;
    wire [7:0] scalar_op1_data;
    wire [7:0] mult_op1_data;
    wire [7:0] mult_op2_data;
    
    // 边沿检测逻辑
    assign op_start_pulse = op_start && (!op_start_d);
    
    // 索引计算（组合逻辑）
    // 转置: A[i][j] -> B[j][i]
    assign trans_src_idx = calc_row * saved_op1_n + calc_col;
    assign trans_dst_idx = calc_col * saved_op1_m + calc_row;
    
    // 加法/标量乘: 线性索引
    assign add_idx = calc_idx;
    
    // 矩阵乘法: C[i][j] = sum(A[i][k] * B[k][j])
    assign mult_op1_idx = calc_row * saved_op1_n + calc_k;
    assign mult_op2_idx = calc_k * saved_op2_n + calc_col;
    assign mult_dst_idx = calc_row * saved_op2_n + calc_col;
    
    // 数据提取（组合逻辑）
    assign trans_src_data = operand1_data[trans_src_idx*8 +: 8];
    assign add_op1_data = operand1_data[add_idx*8 +: 8];
    assign add_op2_data = operand2_data[add_idx*8 +: 8];
    assign scalar_op1_data = operand1_data[add_idx*8 +: 8];
    assign mult_op1_data = operand1_data[mult_op1_idx*8 +: 8];
    assign mult_op2_data = operand2_data[mult_op2_idx*8 +: 8];

    // 边沿检测寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            op_start_d <= 1'b0;
        else
            op_start_d <= op_start;
    end

    // 主状态机
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
            op_done <= 1'b0;
            error_type <= ERR_NONE;
            display_en <= 1'b0;
            display_type <= 2'd0;
            saved_op1_m <= 4'd0;
            saved_op1_n <= 4'd0;
            saved_op2_m <= 4'd0;
            saved_op2_n <= 4'd0;
        end
        else begin
            // 默认输出
            op_done <= 1'b0;
            display_en <= 1'b0;
            
            case (state)
                //====================================
                // 空闲状态：等待运算开始信号
                //====================================
                COMP_IDLE: begin
                    if (current_mode == S_OP_EXEC && op_start_pulse) begin
                        state <= COMP_CHECK;
                        error_type <= ERR_NONE;
                        calc_idx <= 5'd0;
                        calc_row <= 4'd0;
                        calc_col <= 4'd0;
                        calc_k <= 4'd0;
                        acc <= 16'd0;
                        result_mat_flat <= 400'd0;
                    end
                end
                
                //====================================
                // 检查状态：验证操作数并初始化计算参数
                //====================================
                COMP_CHECK: begin
                    case (current_op)
                        OP_TRANSPOSE: begin
                            if (operand1_valid && operand1_m >= 4'd1 && operand1_m <= 4'd5 &&
                                operand1_n >= 4'd1 && operand1_n <= 4'd5) begin
                                result_m <= operand1_n;  // 转置后行数=原列数
                                result_n <= operand1_m;  // 转置后列数=原行数
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
                                operand1_m == operand2_m && operand1_n == operand2_n &&
                                operand1_m >= 4'd1 && operand1_m <= 4'd5 &&
                                operand1_n >= 4'd1 && operand1_n <= 4'd5) begin
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
                            if (operand1_valid && 
                                operand1_m >= 4'd1 && operand1_m <= 4'd5 &&
                                operand1_n >= 4'd1 && operand1_n <= 4'd5) begin
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
                            // 矩阵乘法要求: A(m*n) * B(n*p) = C(m*p)
                            if (operand1_valid && operand2_valid && 
                                operand1_n == operand2_m &&
                                operand1_m >= 4'd1 && operand1_m <= 4'd5 &&
                                operand1_n >= 4'd1 && operand1_n <= 4'd5 &&
                                operand2_n >= 4'd1 && operand2_n <= 4'd5) begin
                                result_m <= operand1_m;
                                result_n <= operand2_n;
                                saved_op1_m <= operand1_m;
                                saved_op1_n <= operand1_n;
                                saved_op2_m <= operand2_m;
                                saved_op2_n <= operand2_n;
                                state <= COMP_EXECUTE;
                            end
                            else begin
                                error_type <= ERR_OP_MISMATCH;
                                state <= COMP_ERROR;
                            end
                        end
                        
                        default: begin
                            error_type <= ERR_INVALID_OP;
                            state <= COMP_ERROR;
                        end
                    endcase
                end
                
                //====================================
                // 执行状态：根据运算类型进行计算
                //====================================
                COMP_EXECUTE: begin
                    case (current_op)
                        //--------------------------------
                        // 转置运算
                        //--------------------------------
                        OP_TRANSPOSE: begin
                            // 写入转置后的位置
                            result_mat_flat[trans_dst_idx*16 +: 16] <= {8'd0, trans_src_data};
                            
                            // 更新索引
                            if (calc_col >= saved_op1_n - 4'd1) begin
                                if (calc_row >= saved_op1_m - 4'd1) begin
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
                        
                        //--------------------------------
                        // 加法运算
                        //--------------------------------
                        OP_ADD: begin
                            result_mat_flat[calc_idx*16 +: 16] <= {8'd0, add_op1_data} + {8'd0, add_op2_data};
                            
                            if (calc_idx >= total_elem - 5'd1) begin
                                state <= COMP_DONE;
                            end
                            else begin
                                calc_idx <= calc_idx + 5'd1;
                            end
                        end
                        
                        //--------------------------------
                        // 标量乘法
                        //--------------------------------
                        OP_SCALAR: begin
                            result_mat_flat[calc_idx*16 +: 16] <= scalar * scalar_op1_data;
                            
                            if (calc_idx >= total_elem - 5'd1) begin
                                state <= COMP_DONE;
                            end
                            else begin
                                calc_idx <= calc_idx + 5'd1;
                            end
                        end
                        
                        //--------------------------------
                        // 矩阵乘法：开始累加
                        //--------------------------------
                        OP_MULTIPLY: begin
                            // 初始化累加器，开始计算C[row][col]
                            acc <= 16'd0;
                            calc_k <= 4'd0;
                            state <= COMP_MULT_ACC;
                        end
                        
                        default: state <= COMP_ERROR;
                    endcase
                end
                
                //====================================
                // 矩阵乘法累加状态
                //====================================
                COMP_MULT_ACC: begin
                    // 累加：acc += A[row][k] * B[k][col]
                    acc <= acc + mult_op1_data * mult_op2_data;
                    
                    if (calc_k >= saved_op1_n - 4'd1) begin
                        // 当前元素计算完成，写入结果
                        result_mat_flat[mult_dst_idx*16 +: 16] <= acc + mult_op1_data * mult_op2_data;
                        
                        // 移动到下一个结果元素
                        if (calc_col >= saved_op2_n - 4'd1) begin
                            if (calc_row >= saved_op1_m - 4'd1) begin
                                // 所有元素计算完成
                                state <= COMP_DONE;
                            end
                            else begin
                                // 下一行
                                calc_col <= 4'd0;
                                calc_row <= calc_row + 4'd1;
                                acc <= 16'd0;
                                calc_k <= 4'd0;
                            end
                        end
                        else begin
                            // 下一列
                            calc_col <= calc_col + 4'd1;
                            acc <= 16'd0;
                            calc_k <= 4'd0;
                        end
                    end
                    else begin
                        calc_k <= calc_k + 4'd1;
                    end
                end
                
                //====================================
                // 完成状态
                //====================================
                COMP_DONE: begin
                    op_done <= 1'b1;
                    display_en <= 1'b1;
                    display_type <= 2'b01;  // 正常结果
                    state <= COMP_IDLE;
                end
                
                //====================================
                // 错误状态
                //====================================
                COMP_ERROR: begin
                    op_done <= 1'b1;
                    display_en <= 1'b1;
                    display_type <= 2'b10;  // 错误标志
                    state <= COMP_IDLE;
                end
                
                default: state <= COMP_IDLE;
            endcase
        end
    end

endmodule
