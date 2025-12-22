//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/11 00:05:01
// Design Name: 
// Module Name: uart_rx
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
// Module Name: uart_rx
// 功能：串口接收模块，支持参数化波特率，采用中点采样法，具备抗亚稳态设计
//////////////////////////////////////////////////////////////////////////////////

module uart_rx #(
    parameter CLK_FREQ = 100_000_000, // 开发板时钟频率，默认100MHz
    parameter BAUD_RATE = 115200      // 串口波特率
)(
    input  wire        clk,           // 系统时钟
    input  wire        rst_n,         // 低电平复位
    input  wire        rx,            // UART RX 物理引脚
    output reg  [7:0]  rx_data,       // 接收到的 8-bit 数据
    output reg         rx_done        // 接收完成脉冲标志（高电平持续一个时钟周期）
);

    // 计算波特率分频计数值
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    // 内部寄存器
    reg [15:0] baud_cnt;       // 波特率计数器
    reg [3:0]  bit_idx;        // 当前接收的比特位序号
    reg [7:0]  rx_shift;       // 移位寄存器，暂存数据位
    reg        rx_busy;        // 接收状态标志
    reg        rx_d1, rx_d2;   // 打拍寄存器，用于异步信号同步及下降沿检测

    // -------------------------------------------------------------------------
    // 1. 异步信号同步化：二级同步器，消除亚稳态并用于捕捉起始位下降沿
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end

    // 起始位检测：rx_d2由高变低
    wire start_bit = (rx_d2 == 1'b0 && rx_d1 == 1'b1);

    // -------------------------------------------------------------------------
    // 2. 接收控制逻辑（有限状态机控制）
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 16'd0;
            bit_idx  <= 4'd0;
            rx_busy  <= 1'b0;
            rx_done  <= 1'b0;
            rx_data  <= 8'd0;
            rx_shift <= 8'd0;
        end else begin
            rx_done <= 1'b0; // 默认拉低完成标志

            if (!rx_busy) begin
                // 空闲状态：等待起始位下降沿
                if (rx_d2 == 1'b0) begin 
                    rx_busy  <= 1'b1;
                    baud_cnt <= BAUD_DIV / 2; // 关键：初始化计数器为半个周期，实现中点采样
                    bit_idx  <= 4'd0;
                end
            end else begin
                // 忙碌状态：正在采样比特位
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 16'd0;
                    
                    case (bit_idx)
                        4'd0: begin // 起始位采样确认
                            if (rx_d2 == 1'b0)
                                bit_idx <= bit_idx + 1'b1;
                            else
                                rx_busy <= 1'b0; // 假起始位，回归空闲
                        end
                        
                        4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin
                            // 数据位采样 (LSB First: 先收低位)
                            rx_shift[bit_idx-1] <= rx_d2;
                            bit_idx <= bit_idx + 1'b1;
                        end
                        
                        4'd9: begin // 停止位采样
                            rx_busy <= 1'b0;
                            bit_idx <= 4'd0;
                            if (rx_d2 == 1'b1) begin // 校验停止位是否为高
                                rx_data <= rx_shift;
                                rx_done <= 1'b1;      // 触发完成脉冲
                            end
                        end
                        
                        default: rx_busy <= 1'b0;
                    endcase
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end
        end
    end

endmodule