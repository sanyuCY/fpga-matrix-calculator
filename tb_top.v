`timescale 1ns / 1ps

module tb_top();

    // 信号定义
    reg clk;
    reg [7:0] key;
    reg uart_rx;
    reg uart_tx_rst_n;
    reg uart_rx_rst_n;
    reg send_one;
    
    wire uart_tx;
    wire [7:0] led;
    wire uart_tx_work;
    wire uart_rx_work;

    // 波特率参数：115200bps，在100MHz时钟下，每个bit约为 8680ns
    localparam BIT_PERIOD = 8680; 

    // 1. 实例化顶层模块 (UUT: Unit Under Test)
    top uut (
        .clk(clk),
        .key(key),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .uart_tx_rst_n(uart_tx_rst_n),
        .uart_rx_rst_n(uart_rx_rst_n),
        .send_one(send_one),
        .uart_tx_work(uart_tx_work),
        .uart_rx_work(uart_rx_work)
    );

    // 2. 产生 100MHz 时钟 (10ns 周期)
    always #5 clk = ~clk;

    // 3. 定义发送一个字节的任务 (模拟电脑发给FPGA)
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx = 0; // 起始位
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i]; // 数据位 (LSB First)
                #(BIT_PERIOD);
            end
            uart_rx = 1; // 停止位
            #(BIT_PERIOD);
        end
    endtask

    // 4. 激励过程
    initial begin
        // 初始化信号
        clk = 0;
        uart_rx = 1;
        key = 8'b0;
        uart_tx_rst_n = 0;
        uart_rx_rst_n = 0;
        send_one = 0;

        // 复位过程
        #100;
        uart_tx_rst_n = 1;
        uart_rx_rst_n = 1;
        #100;

        // --- 模拟接收过程：存入 3 个数据 ---
        $display("Starting UART RX Simulation...");
        uart_send_byte(8'h01); // 存入数字 1
        uart_send_byte(8'h02); // 存入数字 2
        uart_send_byte(8'h03); // 存入数字 3
        #5000;

        // --- 模拟展示过程：按下 R11 按键 ---
        $display("Triggering Matrix Display...");
        send_one = 1;
        #100;
        send_one = 0;

        // 等待一段时间观察串口 TX 的输出波形
        #500000; 
        
        $display("Simulation Finished.");
        $stop;
    end

endmodule