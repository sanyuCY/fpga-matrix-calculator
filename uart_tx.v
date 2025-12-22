//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/10 21:32:16
// Design Name: 
// Module Name: uart_tx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: uart_tx
// 功能：串口发送模块，支持参数化波特率。
// 设计特点：采用移位寄存器实现 LSB First 发送，带忙碌标志位控制。
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter CLK_FREQ = 100_000_000, // 开发板主频 100MHz
    parameter BAUD_RATE = 115200      // 目标波特率
)(
    input  wire        clk,           // 系统时钟
    input  wire        rst_n,         // 低电平复位
    input  wire        tx_start,      // 发送启动脉冲（高电平有效）
    input  wire [7:0]  tx_data,       // 待发送的 8-bit 数据字节
    output reg         tx,            // UART TX 物理引脚
    output reg         tx_busy        // 模块忙碌标志（正在发送时为高）
);

    // 计算波特率分频计数值
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [15:0] baud_cnt;       // 波特率计数器
    reg [3:0]  bit_idx;        // 当前发送的比特位序号（0-9）
    reg [9:0]  tx_shift;       // 移位寄存器：{停止位(1), 数据位(8-bit), 起始位(0)}

    // -------------------------------------------------------------------------
    // 发送状态机与移位逻辑
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1;               // 串口空闲电平为高
            tx_busy <= 1'b0;
            baud_cnt <= 16'd0;
            bit_idx <= 4'd0;
            tx_shift <= 10'b1111111111;
        end else begin
            if (!tx_busy) begin
                tx <= 1'b1;           // 确保空闲时 TX 为高
                if (tx_start) begin
                    // 装载发送帧：起始位(0) + 数据(LSB First) + 停止位(1)
                    tx_shift <= {1'b1, tx_data, 1'b0};
                    tx_busy  <= 1'b1;
                    baud_cnt <= 16'd0;
                    bit_idx  <= 4'd0;
                end
            end else begin
                // 忙碌状态：按照波特率周期发送比特
                if (baud_cnt < BAUD_DIV - 1) begin
                    baud_cnt <= baud_cnt + 1'b1;
                end else begin
                    baud_cnt <= 16'd0;
                    tx <= tx_shift[0]; // 发送当前最低位
                    
                    if (bit_idx < 4'd9) begin
                        tx_shift <= {1'b1, tx_shift[9:1]}; // 右移，高位补1
                        bit_idx <= bit_idx + 1'b1;
                    end else begin
                        // 发送完第 10 位（停止位）后结束
                        tx_busy <= 1'b0;
                        bit_idx <= 4'd0;
                    end
                end
            end
        end
    end

endmodule