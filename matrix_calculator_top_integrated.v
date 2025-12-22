`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_calculator_top_integrated - 系统顶层模块（整合版）
// 功能: 完整的FPGA矩阵计算器系统，集成所有子模块
// 接口: 适配EGO1开发板 (xc7a35tcsg324-1)
// 整合: 使用独立的uart_rx, uart_tx, matrix_display模块
//////////////////////////////////////////////////////////////////////////////

module matrix_calculator_top (
    // 系统时钟和复位
    input wire clk_100m,            // 100MHz系统时钟 (P17)
    input wire rst_n,               // 复位按键（低电平有效）(P15)
    
    // 用户输入
    input wire [7:0] SW,            // 8位拨码开关
    input wire [4:0] KEY,           // 5位按键（Active Low on EGO1）
    
    // UART接口
    input wire uart_rxd,            // UART接收 (N5)
    output wire uart_txd,           // UART发送 (T4)
    
    // LED输出
    output wire [7:0] LED,          // 8位LED
    
    // 数码管输出
    output wire [7:0] seg_sel,      // 数码管位选
    output wire [7:0] seg_data      // 数码管段选
);

    //==========================================================================
    // 按键极性转换（EGO1按键按下为低电平，但代码期望高电平有效）
    //==========================================================================
    wire [4:0] KEY_active;
    assign KEY_active = ~KEY;  // 取反使按键按下时为高电平

    //==========================================================================
    // 内部信号定义
    //==========================================================================
    
    // UART模块信号
    wire [7:0] uart_rx_data;
    wire rx_done;
    wire tx_busy;
    wire [7:0] tx_data_to_uart;
    wire tx_start_to_uart;
    
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
    
    // Matrix Display模块信号
    wire [4:0] display_read_addr;
    wire [7:0] display_element_val;
    wire [7:0] display_tx_data;
    wire display_tx_start;
    wire display_busy;
    
    // 显示控制信号
    reg display_start_pulse;
    reg display_en_d;
    
    //==========================================================================
    // LED输出
    //==========================================================================
    assign LED = led_out;
    
    //==========================================================================
    // 数码管驱动（简化版：动态扫描）
    //==========================================================================
    reg [15:0] seg_cnt;
    reg [2:0] seg_digit;
    
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            seg_cnt <= 16'd0;
            seg_digit <= 3'd0;
        end
        else begin
            if (seg_cnt >= 16'd50000) begin  // 约500Hz刷新率
                seg_cnt <= 16'd0;
                seg_digit <= seg_digit + 3'd1;
            end
            else begin
                seg_cnt <= seg_cnt + 16'd1;
            end
        end
    end
    
    // 数码管位选（8位数码管，共阳极，低电平选中）
    reg [7:0] seg_sel_reg;
    always @(*) begin
        seg_sel_reg = 8'b11111111;
        case (seg_digit)
            3'd0: seg_sel_reg = 8'b11111110;
            3'd1: seg_sel_reg = 8'b11111101;
            3'd2: seg_sel_reg = 8'b11111011;
            3'd3: seg_sel_reg = 8'b11110111;
            3'd4: seg_sel_reg = 8'b11101111;
            3'd5: seg_sel_reg = 8'b11011111;
            3'd6: seg_sel_reg = 8'b10111111;
            3'd7: seg_sel_reg = 8'b01111111;
        endcase
    end
    assign seg_sel = seg_sel_reg;
    
    // 数码管段选（显示前两位数码管的内容）
    reg [7:0] seg_data_reg;
    always @(*) begin
        case (seg_digit)
            3'd0: seg_data_reg = seg_code[7:0];   // 右边第1位
            3'd1: seg_data_reg = seg_code[15:8];  // 右边第2位
            default: seg_data_reg = 8'b11111111; // 其他位熄灭
        endcase
    end
    assign seg_data = seg_data_reg;
    
    //==========================================================================
    // UART接收模块（使用新的uart_rx）
    //==========================================================================
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk(clk_100m),
        .rst_n(rst_n),
        .rx(uart_rxd),
        .rx_data(uart_rx_data),
        .rx_done(rx_done)
    );
    
    //==========================================================================
    // UART发送模块（使用新的uart_tx）
    //==========================================================================
    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk_100m),
        .rst_n(rst_n),
        .tx_start(tx_start_to_uart),
        .tx_data(tx_data_to_uart),
        .tx(uart_txd),
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
        .KEY(KEY_active),  // 使用极性转换后的按键
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
    // 显示触发逻辑
    //==========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            display_en_d <= 1'b0;
            display_start_pulse <= 1'b0;
        end
        else begin
            display_en_d <= display_en;
            display_start_pulse <= display_en & ~display_en_d;  // 上升沿检测
        end
    end
    
    //==========================================================================
    // 结果矩阵元素读取（从result_mat_flat提取）
    //==========================================================================
    wire [15:0] result_element_16bit;
    assign result_element_16bit = result_mat_flat[display_read_addr * 16 +: 16];
    assign display_element_val = result_element_16bit[7:0];  // 取低8位
    
    //==========================================================================
    // Matrix Display模块
    //==========================================================================
    matrix_display u_matrix_display (
        .clk(clk_100m),
        .rst_n(rst_n),
        .display_start(display_start_pulse),
        .row_num(result_m[2:0]),
        .col_num(result_n[2:0]),
        .matrix_id(2'd0),  // 结果矩阵ID为0
        .dim_error(error_type != 3'b000),
        .read_addr(display_read_addr),
        .element_val(display_element_val),
        .tx_data(display_tx_data),
        .tx_start(display_tx_start),
        .tx_busy(tx_busy),
        .display_busy(display_busy)
    );
    
    //==========================================================================
    // UART发送仲裁（优先显示模块）
    //==========================================================================
    assign tx_data_to_uart = display_tx_data;
    assign tx_start_to_uart = display_tx_start;

endmodule
