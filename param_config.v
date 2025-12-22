`timescale 1ns / 1ps

module param_config(
    input clk,
    input rst_n,
    input [7:0] uart_rx_data,
    input rx_done,
    output reg [3:0] max_mat_num,    // 每种规格矩阵最大存储个数(1~5)
    output reg [7:0] val_min,       // 矩阵元素最小值(-3~20，补码表示)
    output reg [7:0] val_max,       // 矩阵元素最大值(0~20)
    output reg config_done,         // 配置完成标志(高电平脉冲)
    output reg [2:0] error_type     // 错误类型(000=无错,010=指令格式错,011=参数非法,100=存储个数非法)
);

// 负数补码参数定义(提升可读性)
localparam MIN_NEG3 = 8'd253;  // -3的8位补码
localparam MIN_NEG2 = 8'd254;  // -2的8位补码
localparam MIN_NEG1 = 8'd255;  // -1的8位补码
localparam MAX_VAL  = 8'd20;   // 元素最大值上限
localparam MIN_VAL  = 8'd0;    // 元素默认最小值

// 指令缓冲区(最大存储16字节指令)
reg [7:0] cmd_buf [0:15];
reg [3:0] cmd_cnt;             // 指令字节计数器
reg cmd_ready;                 // 指令接收完成标志

// 临时寄存器(存储解析中的参数值)
reg [7:0] new_val_min;
reg [7:0] new_val_max;
reg [3:0] new_max_mat_num;
reg parsing_error;             // 指令解析错误标志

// 状态定义
reg [1:0] state;
localparam IDLE  = 2'b00;      // 空闲状态(等待指令)
localparam PARSE = 2'b01;      // 指令解析状态
localparam CHECK = 2'b10;      // 参数校验与更新状态

// --- 将integer变量移至模块级声明区域 ---
integer i;
integer comma_idx;  // 逗号位置索引(解析range指令用)
integer max_len;    // 最大值数字长度(解析range指令用)
integer min_idx;    // 最小值起始索引(过滤空格用)
// ----------------------------------------

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化：恢复默认参数
        cmd_cnt <= 4'd0;
        cmd_ready <= 1'b0;
        parsing_error <= 1'b0;
        config_done <= 1'b0;
        error_type <= 3'b000;
        state <= IDLE;
        
        // 初始化指令缓冲区
        for (i = 0; i < 16; i = i + 1) begin
            cmd_buf[i] <= 8'd0;
        end
        
        // 初始化临时寄存器(默认参数)
        new_max_mat_num <= 4'd2;  // 默认存储2个同规格矩阵
        new_val_min <= MIN_VAL;   // 默认元素最小值0
        new_val_max <= 8'd9;      // 默认元素最大值9
        
        // 初始化输出寄存器(默认参数)
        max_mat_num <= 4'd2;
        val_min <= MIN_VAL;
        val_max <= 8'd9;
    end else begin
        case (state)
            // 状态1：空闲态，接收UART指令
            IDLE: begin
                config_done <= 1'b0;  // 清零配置完成标志
                error_type <= 3'b000; // 清零错误类型
                if (rx_done) begin
                    if (uart_rx_data == 8'h0D) begin  // 检测到回车符(指令结束)
                        cmd_ready <= 1'b1;
                        cmd_cnt <= 4'd0;              // 重置计数器，准备下一条指令
                        state <= PARSE;
                    end else if (cmd_cnt < 4'd15) begin  // 指令未超缓冲区，继续接收
                        cmd_buf[cmd_cnt] <= uart_rx_data;
                        cmd_cnt <= cmd_cnt + 4'd1;
                    end
                end
            end
            
            // 状态2：解析指令(x=N 或 range=min,max)
            PARSE: begin
                cmd_ready <= 1'b0;
                parsing_error <= 1'b0;
                error_type <= 3'b000;
                
                // 解析"x=N"指令(设置同规格矩阵最大存储个数)
                if (cmd_buf[0] == "x" && cmd_buf[1] == "=") begin
                    case (cmd_buf[2])
                        "1": new_max_mat_num <= 4'd1;
                        "2": new_max_mat_num <= 4'd2;
                        "3": new_max_mat_num <= 4'd3;
                        "4": new_max_mat_num <= 4'd4;
                        "5": new_max_mat_num <= 4'd5;
                        default: begin  // 存储个数超出1~5范围
                            parsing_error <= 1'b1;
                            error_type <= 3'b100;
                        end
                    endcase
                end
                // 解析"range=min,max"指令(设置元素值范围)
                else if (cmd_buf[0] == "r" && cmd_buf[1] == "a" && 
                         cmd_buf[2] == "n" && cmd_buf[3] == "g" && 
                         cmd_buf[4] == "e" && cmd_buf[5] == "=") begin
                    // 步骤1：找到逗号分隔符
                    comma_idx = 6;
                    while (comma_idx < 15 && cmd_buf[comma_idx] != ",") begin
                        comma_idx = comma_idx + 1;
                    end
                    
                    if (comma_idx >= 15) begin  // 未找到逗号，指令格式错误
                        parsing_error <= 1'b1;
                        error_type <= 3'b010;
                    end else begin
                        // 步骤2：解析最小值(过滤空格，支持负数)
                        min_idx = 6;
                        while (min_idx < comma_idx && cmd_buf[min_idx] == " ") begin  // 跳过空格
                            min_idx = min_idx + 1;
                        end
                        
                        if (cmd_buf[min_idx] == "-") begin  // 处理负数(-1~-3)
                            case (cmd_buf[min_idx+1])
                                "1": new_val_min <= MIN_NEG1;
                                "2": new_val_min <= MIN_NEG2;
                                "3": new_val_min <= MIN_NEG3;
                                default: begin  // 负数超出-3范围
                                    parsing_error <= 1'b1;
                                    error_type <= 3'b011;
                                end
                            endcase
                        end else begin  // 处理正数(0~20)
                            if (comma_idx - min_idx == 1) begin  // 1位正数(如"5,")
                                new_val_min <= cmd_buf[min_idx] - 8'h30;
                            end else if (comma_idx - min_idx == 2) begin  // 2位正数(如"15,")
                                new_val_min <= (cmd_buf[min_idx] - 8'h30) * 10 + (cmd_buf[min_idx+1] - 8'h30);
                            end else begin  // 正数位数错误
                                parsing_error <= 1'b1;
                                error_type <= 3'b011;
                            end
                        end
                        
                        // 步骤3：解析最大值(逗号后，仅支持正数0~20)
                        max_len = cmd_cnt - comma_idx - 1;  // 最大值数字长度
                        if (max_len == 1) begin  // 1位最大值(如",5")
                            new_val_max <= cmd_buf[comma_idx+1] - 8'h30;
                        end else if (max_len == 2) begin  // 2位最大值(如",15")
                            new_val_max <= (cmd_buf[comma_idx+1] - 8'h30) * 10 + (cmd_buf[comma_idx+2] - 8'h30);
                        end else begin  // 最大值位数错误
                            parsing_error <= 1'b1;
                            error_type <= 3'b011;
                        end
                    end
                end
                // 未知指令格式
                else begin
                    parsing_error <= 1'b1;
                    error_type <= 3'b010;
                end
                
                state <= CHECK;  // 进入参数校验状态
            end
            
            // 状态3：参数合法性校验与更新
            CHECK: begin
                if (!parsing_error) begin
                    // 子步骤1：更新参数(根据指令类型)
                    if (cmd_buf[0] == "x") begin  // 处理x=N指令
                        max_mat_num <= new_max_mat_num;
                        // 二次校验存储个数(确保1~5)
                        if (max_mat_num < 4'd1) begin
                            max_mat_num <= 4'd1;
                            error_type <= 3'b100;
                        end else if (max_mat_num > 4'd5) begin
                            max_mat_num <= 4'd5;
                            error_type <= 3'b100;
                        end
                    end else if (cmd_buf[0] == "r") begin  // 处理range指令
                        val_min <= new_val_min;
                        val_max <= new_val_max;
                        // 二次校验元素范围
                        // 校验val_min：-3(253)~20
                        if (val_min < MIN_NEG3 || val_min > MAX_VAL) begin
                            val_min <= MIN_VAL;
                            error_type <= 3'b011;
                        end
                        // 校验val_max：0~20
                        if (val_max < MIN_VAL || val_max > MAX_VAL) begin
                            val_max <= 8'd9;
                            error_type <= 3'b011;
                        end
                        // 校验val_max >= val_min(否则恢复默认0~9)
                        if (val_max < val_min) begin
                            val_min <= MIN_VAL;
                            val_max <= 8'd9;
                            error_type <= 3'b011;
                        end
                    end
                    
                    // 子步骤2：设置配置完成标志(无错误时)
                    if (error_type == 3'b000) begin
                        config_done <= 1'b1;
                    end
                end
                
                // 子步骤3：清理缓冲区与临时寄存器
                cmd_cnt <= 4'd0;
                for (i = 0; i < 16; i = i + 1) begin
                    cmd_buf[i] <= 8'd0;
                end
                new_val_min <= MIN_VAL;   // 重置临时最小值
                new_val_max <= 8'd9;      // 重置临时最大值
                new_max_mat_num <= 4'd2;  // 重置临时存储个数
                
                state <= IDLE;  // 返回空闲态，等待下一条指令
            end
        endcase
    end
end

endmodule


