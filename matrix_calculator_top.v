`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_calculator_top - 系统顶层模块
// 功能: 完整的FPGA矩阵计算器系统，集成所有子模块
// 接口: 适配Xilinx XC7A35T开发板
//////////////////////////////////////////////////////////////////////////////

module matrix_calculator_top (
    // 系统时钟和复位
    input wire clk_100m,            // 100MHz系统时钟
    input wire rst_n,               // 复位按键（低电平有效）
    
    // 用户输入
    input wire [7:0] SW,            // 8位拨码开关
    input wire [4:0] KEY,           // 5位按键
    
    // UART接口
    input wire uart_rxd,            // UART接收
    output wire uart_txd,           // UART发送
    
    // LED输出
    output wire [7:0] LED,          // 8位LED
    
    // 数码管输出
    output wire [7:0] seg_sel,      // 数码管位选
    output wire [7:0] seg_data      // 数码管段选
);

    //==========================================================================
    // 内部信号定义
    //==========================================================================
    
    // UART模块信号
    wire [7:0] uart_rx_data;
    wire rx_done;
    wire tx_busy;
    reg [7:0] uart_tx_data;
    reg tx_start;
    
    // 参数配置模块信号
    wire [3:0] max_mat_num;
    wire [7:0] val_min, val_max;
    wire config_done;
    wire [2:0] config_error;
    
    // 控制FSM信号
    wire [3:0] current_mode;
    wire [2:0] current_op;
    wire [7:0] led_out;
    wire [15:0] seg_code;
    wire [3:0] scalar;
    wire [1:0] operand_sel;
    wire [3:0] countdown_sec;
    wire op_start;
    wire [3:0] operand_id1, operand_id2;
    wire display_done;
    
    // 核心模块信号
    wire [39:0] stored_mat_m_flat;
    wire [39:0] stored_mat_n_flat;
    wire [39:0] stored_mat_id_flat;
    wire [1999:0] stored_mat_flat;
    wire [3:0] total_mat_count;
    wire [399:0] result_mat_flat;
    wire [3:0] result_m, result_n;
    wire input_done;
    wire op_done;
    wire [2:0] error_type;
    wire display_en;
    wire [1:0] display_type;
    wire [99:0] spec_count_flat;
    wire [31:0] cycle_cnt;
    
    //==========================================================================
    // LED输出
    //==========================================================================
    assign LED = led_out;
    
    //==========================================================================
    // 数码管驱动（简化版：仅使用2位数码管）
    //==========================================================================
    reg [15:0] seg_cnt;
    reg seg_toggle;
    
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            seg_cnt <= 16'd0;
            seg_toggle <= 1'b0;
        end
        else begin
            if (seg_cnt >= 16'd50000) begin  // 约500Hz刷新率
                seg_cnt <= 16'd0;
                seg_toggle <= ~seg_toggle;
            end
            else begin
                seg_cnt <= seg_cnt + 16'd1;
            end
        end
    end
    
    // 数码管位选（2位数码管）
    assign seg_sel = seg_toggle ? 8'b11111110 : 8'b11111101;
    
    // 数码管段选
    assign seg_data = seg_toggle ? seg_code[7:0] : seg_code[15:8];
    
    //==========================================================================
    // UART接收模块
    //==========================================================================
    uart_rx #(
        .CLK_FREQ(100000000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk(clk_100m),
        .rst_n(rst_n),
        .rxd(uart_rxd),
        .rx_data(uart_rx_data),
        .rx_done(rx_done)
    );
    
    //==========================================================================
    // UART发送模块
    //==========================================================================
    uart_tx #(
        .CLK_FREQ(100000000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk_100m),
        .rst_n(rst_n),
        .tx_data(uart_tx_data),
        .tx_start(tx_start),
        .txd(uart_txd),
        .tx_busy(tx_busy)
    );
    
    //==========================================================================
    // 参数配置模块
    //==========================================================================
    param_config u_param_config (
        .clk(clk_100m),
        .rst_n(rst_n),
        .uart_rx_data(uart_rx_data),
        .rx_done(rx_done),
        .max_mat_num(max_mat_num),
        .val_min(val_min),
        .val_max(val_max),
        .config_done(config_done),
        .error_type(config_error)
    );
    
    //==========================================================================
    // 控制FSM模块
    //==========================================================================
    control_fsm u_control_fsm (
        .clk(clk_100m),
        .rst_n(rst_n),
        .SW(SW),
        .KEY(KEY),
        .op_done(op_done),
        .input_done(input_done),
        .error_type(error_type),
        .uart_rx_data(uart_rx_data),
        .rx_done(rx_done),
        .config_done(config_done),
        .result_m(result_m),
        .result_n(result_n),
        .total_mat_count(total_mat_count),
        .current_mode(current_mode),
        .current_op(current_op),
        .LED(led_out),
        .seg_code(seg_code),
        .scalar(scalar),
        .operand_sel(operand_sel),
        .countdown_sec(countdown_sec),
        .op_start(op_start),
        .operand_id1(operand_id1),
        .operand_id2(operand_id2),
        .display_done(display_done)
    );
    
    //==========================================================================
    // 矩阵核心模块
    //==========================================================================
    matrix_core_top u_matrix_core (
        .clk(clk_100m),
        .rst_n(rst_n),
        .uart_rx_data(uart_rx_data),
        .rx_done(rx_done),
        .current_mode(current_mode),
        .current_op(current_op),
        .max_mat_num(max_mat_num),
        .val_min(val_min),
        .val_max(val_max),
        .operand_sel(operand_sel),
        .scalar(scalar),
        .operand_id1(operand_id1),
        .operand_id2(operand_id2),
        .op_start(op_start),
        .stored_mat_m_flat(stored_mat_m_flat),
        .stored_mat_n_flat(stored_mat_n_flat),
        .stored_mat_id_flat(stored_mat_id_flat),
        .stored_mat_flat(stored_mat_flat),
        .total_mat_count(total_mat_count),
        .result_mat_flat(result_mat_flat),
        .result_m(result_m),
        .result_n(result_n),
        .input_done(input_done),
        .op_done(op_done),
        .error_type(error_type),
        .display_en(display_en),
        .display_type(display_type),
        .spec_count_flat(spec_count_flat),
        .cycle_cnt(cycle_cnt)
    );
    
    //==========================================================================
    // UART输出控制（矩阵显示）
    //==========================================================================
    // 状态机用于发送矩阵数据到UART
    reg [3:0] uart_state;
    reg [4:0] uart_row, uart_col;
    reg [7:0] uart_delay;
    
    localparam UART_IDLE = 4'd0;
    localparam UART_SEND_RESULT = 4'd1;
    localparam UART_SEND_CHAR = 4'd2;
    localparam UART_WAIT = 4'd3;
    localparam UART_NEWLINE = 4'd4;
    localparam UART_DONE = 4'd5;
    
    wire [15:0] current_result_elem;
    wire [4:0] result_idx;
    
    assign result_idx = uart_row * result_n + uart_col;
    assign current_result_elem = result_mat_flat[result_idx*16 +: 16];
    
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            uart_state <= UART_IDLE;
            uart_row <= 5'd0;
            uart_col <= 5'd0;
            uart_delay <= 8'd0;
            uart_tx_data <= 8'd0;
            tx_start <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;
            
            case (uart_state)
                UART_IDLE: begin
                    if (display_en && display_type == 2'b01) begin
                        uart_state <= UART_SEND_RESULT;
                        uart_row <= 5'd0;
                        uart_col <= 5'd0;
                    end
                end
                
                UART_SEND_RESULT: begin
                    if (!tx_busy) begin
                        // 发送当前元素（简化：只发送低8位的ASCII）
                        if (current_result_elem < 16'd10) begin
                            uart_tx_data <= 8'h30 + current_result_elem[7:0];
                        end
                        else if (current_result_elem < 16'd100) begin
                            // 两位数：先发十位
                            uart_tx_data <= 8'h30 + (current_result_elem / 10);
                        end
                        else begin
                            // 三位数：发送百位
                            uart_tx_data <= 8'h30 + (current_result_elem / 100);
                        end
                        tx_start <= 1'b1;
                        uart_state <= UART_WAIT;
                        uart_delay <= 8'd0;
                    end
                end
                
                UART_WAIT: begin
                    if (uart_delay < 8'd100) begin
                        uart_delay <= uart_delay + 8'd1;
                    end
                    else if (!tx_busy) begin
                        // 发送空格
                        if (uart_col < result_n - 4'd1) begin
                            uart_tx_data <= 8'h20;  // 空格
                            tx_start <= 1'b1;
                            uart_col <= uart_col + 5'd1;
                            uart_state <= UART_SEND_RESULT;
                        end
                        else begin
                            uart_state <= UART_NEWLINE;
                        end
                    end
                end
                
                UART_NEWLINE: begin
                    if (!tx_busy) begin
                        uart_tx_data <= 8'h0D;  // 回车
                        tx_start <= 1'b1;
                        uart_col <= 5'd0;
                        
                        if (uart_row < result_m - 4'd1) begin
                            uart_row <= uart_row + 5'd1;
                            uart_state <= UART_SEND_RESULT;
                        end
                        else begin
                            uart_state <= UART_DONE;
                        end
                    end
                end
                
                UART_DONE: begin
                    uart_state <= UART_IDLE;
                end
                
                default: uart_state <= UART_IDLE;
            endcase
        end
    end

endmodule

//==========================================================================
// UART接收模块
//==========================================================================
module uart_rx #(
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire rxd,
    output reg [7:0] rx_data,
    output reg rx_done
);

    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1;
    localparam HALF_BAUD = BAUD_CNT_MAX / 2;
    
    reg [15:0] baud_cnt;
    reg [3:0] bit_cnt;
    reg [2:0] state;
    reg rxd_d0, rxd_d1, rxd_d2;
    wire rxd_negedge;
    
    localparam IDLE = 3'd0;
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam STOP = 3'd3;
    
    // 同步和边沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_d0 <= 1'b1;
            rxd_d1 <= 1'b1;
            rxd_d2 <= 1'b1;
        end
        else begin
            rxd_d0 <= rxd;
            rxd_d1 <= rxd_d0;
            rxd_d2 <= rxd_d1;
        end
    end
    
    assign rxd_negedge = rxd_d2 & (~rxd_d1);
    
    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            baud_cnt <= 16'd0;
            bit_cnt <= 4'd0;
            rx_data <= 8'd0;
            rx_done <= 1'b0;
        end
        else begin
            rx_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (rxd_negedge) begin
                        state <= START;
                        baud_cnt <= 16'd0;
                    end
                end
                
                START: begin
                    if (baud_cnt == HALF_BAUD) begin
                        if (!rxd_d1) begin
                            state <= DATA;
                            baud_cnt <= 16'd0;
                            bit_cnt <= 4'd0;
                        end
                        else begin
                            state <= IDLE;
                        end
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                DATA: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 16'd0;
                        rx_data[bit_cnt] <= rxd_d1;
                        
                        if (bit_cnt == 4'd7) begin
                            state <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                STOP: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        state <= IDLE;
                        rx_done <= 1'b1;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

//==========================================================================
// UART发送模块
//==========================================================================
module uart_tx #(
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire [7:0] tx_data,
    input wire tx_start,
    output reg txd,
    output reg tx_busy
);

    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1;
    
    reg [15:0] baud_cnt;
    reg [3:0] bit_cnt;
    reg [2:0] state;
    reg [7:0] tx_data_reg;
    
    localparam IDLE = 3'd0;
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam STOP = 3'd3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            baud_cnt <= 16'd0;
            bit_cnt <= 4'd0;
            txd <= 1'b1;
            tx_busy <= 1'b0;
            tx_data_reg <= 8'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    txd <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        state <= START;
                        tx_data_reg <= tx_data;
                        tx_busy <= 1'b1;
                        baud_cnt <= 16'd0;
                    end
                end
                
                START: begin
                    txd <= 1'b0;
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        state <= DATA;
                        baud_cnt <= 16'd0;
                        bit_cnt <= 4'd0;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                DATA: begin
                    txd <= tx_data_reg[bit_cnt];
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 16'd0;
                        if (bit_cnt == 4'd7) begin
                            state <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                STOP: begin
                    txd <= 1'b1;
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        state <= IDLE;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
