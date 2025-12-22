`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: control_fsm - 修复版
// 修复内容:
//   1. 将复位逻辑合并到主时钟块中（移除negedge rst_n的独立块）
//   2. 添加op_start、operand_id1、operand_id2输出信号
//   3. 按键边沿检测，防止重复触发
//   4. 修复倒计时逻辑，避免多驱动问题
//   5. 添加display_done生成逻辑
//////////////////////////////////////////////////////////////////////////////

module control_fsm(
    input clk,                      // 全局时钟（100MHz）
    input rst_n,                    // 全局复位（低电平有效）
    input [7:0] SW,                 // 8位拨码开关（SW0~SW7）
    input [4:0] KEY,                // 5位按键（S1~S5对应KEY[0]~KEY[4]）
    input op_done,                  // 运算完成标志（来自成员C）
    input input_done,               // 输入/生成完成标志（来自成员C）
    input [2:0] error_type,         // 错误类型（来自成员C：000=无错）
    input [7:0] uart_rx_data,       // 配置指令（来自成员A）
    input rx_done,                  // 配置指令接收完成（来自成员A）
    input config_done,              // 配置完成标志（来自param_config）
    input [3:0] result_m,           // 结果矩阵行数（来自成员C）
    input [3:0] result_n,           // 结果矩阵列数（来自成员C）
    input [3:0] total_mat_count,    // 存储的矩阵总数
    
    output reg [3:0] current_mode,  // 当前状态（输出给所有模块）
    output reg [2:0] current_op,    // 运算类型（输出给成员C）
    output reg [7:0] LED,           // LED控制（输出给开发板）
    output reg [15:0] seg_code,     // 数码管控制（16位：左4+右4）
    output reg [3:0] scalar,        // 标量值（输出给成员C）
    output reg [1:0] operand_sel,   // 运算数选择模式（00=手动，01=随机）
    output reg [3:0] countdown_sec, // 倒计时秒数（输出给成员A）
    output reg op_start,            // 运算开始信号
    output reg [3:0] operand_id1,   // 操作数1的存储索引
    output reg [3:0] operand_id2,   // 操作数2的存储索引
    output reg display_done         // 展示完成标志
);

// 1. 状态定义（9个核心状态）
localparam S_MENU      = 4'b0000;  // 主菜单
localparam S_INPUT     = 4'b0001;  // 矩阵输入模式
localparam S_GEN       = 4'b0010;  // 矩阵生成模式
localparam S_SHOW      = 4'b0011;  // 矩阵展示模式
localparam S_OP_SELECT = 4'b0100;  // 选择运算类型
localparam S_OP_PARAM  = 4'b0101;  // 选择运算数
localparam S_OP_EXEC   = 4'b0110;  // 执行运算
localparam S_RESULT    = 4'b0111;  // 展示结果
localparam S_RETURN    = 4'b1000;  // 等待返回

// 2. 运算类型编码（和SW0~SW2对应）
localparam OP_TRANS    = 3'b000;  // 转置 T
localparam OP_ADD      = 3'b001;  // 加法 A
localparam OP_SCALAR   = 3'b010;  // 标量乘 B
localparam OP_MUL      = 3'b011;  // 矩阵乘 C
localparam OP_CONV     = 3'b100;  // 卷积 J（bonus）

// 3. 数码管显示编码（共阴极，XC7A35T兼容）
localparam SEG_OFF     = 8'b11111111;  // 熄灭
localparam SEG_0       = 8'b00000011;  // 0
localparam SEG_1       = 8'b10011111;  // 1
localparam SEG_2       = 8'b00100101;  // 2
localparam SEG_3       = 8'b00001101;  // 3
localparam SEG_4       = 8'b10011001;  // 4
localparam SEG_5       = 8'b01001001;  // 5
localparam SEG_6       = 8'b01000001;  // 6
localparam SEG_7       = 8'b00011111;  // 7
localparam SEG_8       = 8'b00000001;  // 8
localparam SEG_9       = 8'b00001001;  // 9
localparam SEG_T       = 8'b11100001;  // T
localparam SEG_A       = 8'b00010001;  // A
localparam SEG_B       = 8'b11000001;  // B
localparam SEG_C       = 8'b01100011;  // C
localparam SEG_J       = 8'b00000111;  // J

// 4. 内部寄存器定义
reg [19:0] key_cnt;               // 按键消抖计数器（100MHz*10ms=1,000,000）
reg [4:0] key_sync, key_sync_d;   // 按键同步寄存器
reg [4:0] key_clean;              // 消抖后的按键信号
reg [4:0] key_clean_d;            // 消抖信号延迟（用于边沿检测）
wire [4:0] key_posedge;           // 按键上升沿

reg [19:0] sw_cnt;                // 拨码开关防抖计数器
reg [7:0] sw_sync, sw_sync_d;     // 拨码开关同步寄存器
reg [7:0] sw_clean;               // 防抖后的拨码开关信号

reg [31:0] countdown_cnt;         // 错误倒计时计数器（100MHz时钟）
reg countdown_en;                 // 倒计时使能信号
reg [3:0] countdown_cfg;          // 倒计时配置值（5~15秒，默认10秒）

// 操作数选择状态机
reg [2:0] param_state;
localparam PARAM_IDLE = 3'd0;
localparam PARAM_WAIT_M1 = 3'd1;
localparam PARAM_WAIT_N1 = 3'd2;
localparam PARAM_WAIT_ID1 = 3'd3;
localparam PARAM_WAIT_M2 = 3'd4;
localparam PARAM_WAIT_N2 = 3'd5;
localparam PARAM_WAIT_ID2 = 3'd6;
localparam PARAM_WAIT_SCALAR = 3'd7;

reg [3:0] sel_m1, sel_n1;         // 第一个操作数的维度
reg [3:0] sel_m2, sel_n2;         // 第二个操作数的维度

// 展示状态
reg [23:0] display_cnt;           // 展示计时器
localparam DISPLAY_DELAY = 24'd5000000; // 50ms展示延迟

// UART数据边沿检测
reg rx_done_d;
wire rx_done_pulse;
wire [3:0] rx_digit;
wire is_digit;

assign rx_done_pulse = rx_done & (~rx_done_d);
assign rx_digit = uart_rx_data[3:0];
assign is_digit = (uart_rx_data >= 8'h30) && (uart_rx_data <= 8'h39);

// 按键边沿检测
assign key_posedge = key_clean & (~key_clean_d);

// 5. 按键消抖逻辑（100MHz时钟：10ms=1,000,000个时钟周期）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_sync <= 5'b00000;
        key_sync_d <= 5'b00000;
        key_clean <= 5'b00000;
        key_clean_d <= 5'b00000;
        key_cnt <= 20'd0;
    end else begin
        // 两级同步
        key_sync_d <= KEY;
        key_sync <= key_sync_d;
        
        // 消抖计时
        if (key_sync != key_clean) begin
            key_cnt <= 20'd1000000;  // 100MHz * 10ms
        end else if (key_cnt > 20'd0) begin
            key_cnt <= key_cnt - 20'd1;
        end else begin
            key_clean <= key_sync;
        end
        
        // 保存上一拍值用于边沿检测
        key_clean_d <= key_clean;
    end
end

// 6. 拨码开关防抖逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sw_sync <= 8'b00000000;
        sw_sync_d <= 8'b00000000;
        sw_clean <= 8'b00000000;
        sw_cnt <= 20'd0;
    end else begin
        // 两级同步
        sw_sync_d <= SW;
        sw_sync <= sw_sync_d;
        
        // 防抖计时
        if (sw_sync != sw_clean) begin
            sw_cnt <= 20'd1000000;  // 10ms防抖
        end else if (sw_cnt > 20'd0) begin
            sw_cnt <= sw_cnt - 20'd1;
        end else begin
            sw_clean <= sw_sync;
        end
    end
end

// 7. UART接收边沿检测
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_done_d <= 1'b0;
    else
        rx_done_d <= rx_done;
end

// 8. 主状态机和倒计时逻辑（合并为单一时钟块）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        current_mode <= S_MENU;
        current_op <= OP_TRANS;
        scalar <= 4'd0;
        operand_sel <= 2'b00;
        countdown_cnt <= 32'd0;
        countdown_sec <= 4'd10;
        countdown_cfg <= 4'd10;
        countdown_en <= 1'b0;
        op_start <= 1'b0;
        operand_id1 <= 4'd0;
        operand_id2 <= 4'd0;
        display_done <= 1'b0;
        param_state <= PARAM_IDLE;
        sel_m1 <= 4'd0;
        sel_n1 <= 4'd0;
        sel_m2 <= 4'd0;
        sel_n2 <= 4'd0;
        display_cnt <= 24'd0;
    end else begin
        // 默认值
        op_start <= 1'b0;
        display_done <= 1'b0;
        
        // ========== 倒计时逻辑 ==========
        // 启动倒计时条件：有错误且在运算数选择状态，且倒计时未启动
        if (error_type != 3'b000 && current_mode == S_OP_PARAM && !countdown_en) begin
            countdown_en <= 1'b1;
            countdown_cnt <= {countdown_cfg, 28'd0}; // 近似 countdown_cfg * 2^28 ≈ N秒
            countdown_sec <= countdown_cfg;
        end
        
        // 倒计时期间：递减计数，实时更新剩余秒数
        if (countdown_en && countdown_cnt > 32'd0) begin
            countdown_cnt <= countdown_cnt - 32'd1;
            // 使用移位近似计算秒数 (100MHz时约26.8M周期/秒)
            countdown_sec <= countdown_cnt[31:27];
        end
        
        // 倒计时结束：重置
        if (countdown_en && countdown_cnt == 32'd0) begin
            countdown_en <= 1'b0;
            countdown_sec <= countdown_cfg;
            if (current_mode == S_OP_PARAM)
                param_state <= PARAM_IDLE; // 重新开始选择运算数
        end
        
        // 运算数合法或退出参数选择状态：关闭倒计时
        if (error_type == 3'b000 || current_mode != S_OP_PARAM) begin
            countdown_en <= 1'b0;
            countdown_sec <= countdown_cfg;
        end
        
        // ========== 展示计时逻辑 ==========
        if (current_mode == S_SHOW) begin
            if (display_cnt < DISPLAY_DELAY)
                display_cnt <= display_cnt + 24'd1;
            else
                display_done <= 1'b1;
        end else begin
            display_cnt <= 24'd0;
        end
        
        // ========== 主状态机 ==========
        if (countdown_en) begin
            // 倒计时期间，仅允许重新选择运算数或返回
            if (current_mode == S_OP_PARAM) begin
                if (key_posedge[0]) begin  // S1确认新运算数
                    op_start <= 1'b1;
                    current_mode <= S_OP_EXEC;
                    countdown_en <= 1'b0;
                end else if (key_posedge[2]) begin  // S3返回运算类型选择
                    current_mode <= S_OP_SELECT;
                    countdown_en <= 1'b0;
                    param_state <= PARAM_IDLE;
                end else if (key_posedge[3]) begin  // S4回主菜单
                    current_mode <= S_MENU;
                    countdown_en <= 1'b0;
                    param_state <= PARAM_IDLE;
                end
            end
        end else begin
            // 正常流程
            case (current_mode)
                // 主菜单：SW5~SW7选择+S1确认
                S_MENU: begin
                    param_state <= PARAM_IDLE;
                    if (key_posedge[0]) begin
                        case (sw_clean[7:5])
                            3'b000: current_mode <= S_INPUT;
                            3'b001: current_mode <= S_GEN;
                            3'b010: current_mode <= S_SHOW;
                            3'b011: current_mode <= S_OP_SELECT;
                            default: current_mode <= S_MENU;
                        endcase
                    end
                end

                // 输入模式：输入完成后，S1/S3返回主菜单，S2继续输入
                S_INPUT: begin
                    if (input_done) begin
                        if (key_posedge[0] || key_posedge[2]) begin
                            current_mode <= S_MENU;
                        end else if (key_posedge[1]) begin
                            current_mode <= S_INPUT; // 继续当前模式
                        end
                    end
                end

                // 生成模式：和输入模式逻辑一致
                S_GEN: begin
                    if (input_done) begin
                        if (key_posedge[0] || key_posedge[2]) begin
                            current_mode <= S_MENU;
                        end else if (key_posedge[1]) begin
                            current_mode <= S_GEN;
                        end
                    end
                end

                // 展示模式：展示完成后，S1返回主菜单，S2继续展示
                S_SHOW: begin
                    if (display_done) begin
                        if (key_posedge[0]) begin
                            current_mode <= S_MENU;
                        end else if (key_posedge[1]) begin
                            display_cnt <= 24'd0;
                            current_mode <= S_SHOW;
                        end
                    end
                end

                // 运算类型选择：S1确认，S3返回主菜单
                S_OP_SELECT: begin
                    if (key_posedge[0]) begin
                        current_op <= sw_clean[2:0];
                        current_mode <= S_OP_PARAM;
                        param_state <= PARAM_IDLE;
                    end else if (key_posedge[2]) begin
                        current_mode <= S_MENU;
                    end
                end

                // 选择运算数：处理UART输入和按键确认
                S_OP_PARAM: begin
                    // S5切换随机选择
                    if (key_posedge[4]) begin
                        operand_sel <= 2'b01;
                    end
                    
                    // S3返回运算类型选择
                    if (key_posedge[2]) begin
                        current_mode <= S_OP_SELECT;
                        param_state <= PARAM_IDLE;
                    end
                    
                    // 参数选择状态机
                    case (param_state)
                        PARAM_IDLE: begin
                            if (operand_sel == 2'b01) begin
                                // 随机选择模式：直接开始计算
                                if (key_posedge[0]) begin
                                    // 随机分配操作数（简化实现）
                                    operand_id1 <= 4'd0;
                                    operand_id2 <= 4'd1;
                                    if (current_op == OP_SCALAR)
                                        scalar <= sw_clean[7:4]; // SW4~SW7作为标量
                                    op_start <= 1'b1;
                                    current_mode <= S_OP_EXEC;
                                end
                            end else begin
                                // 手动选择模式
                                param_state <= PARAM_WAIT_M1;
                            end
                        end
                        
                        PARAM_WAIT_M1: begin
                            if (rx_done_pulse && is_digit) begin
                                sel_m1 <= rx_digit;
                                param_state <= PARAM_WAIT_N1;
                            end
                        end
                        
                        PARAM_WAIT_N1: begin
                            if (rx_done_pulse && is_digit) begin
                                sel_n1 <= rx_digit;
                                param_state <= PARAM_WAIT_ID1;
                            end
                        end
                        
                        PARAM_WAIT_ID1: begin
                            if (rx_done_pulse && is_digit) begin
                                operand_id1 <= rx_digit;
                                // 判断是否需要第二个操作数
                                if (current_op == OP_ADD || current_op == OP_MUL) begin
                                    param_state <= PARAM_WAIT_M2;
                                end else if (current_op == OP_SCALAR) begin
                                    param_state <= PARAM_WAIT_SCALAR;
                                end else begin
                                    // 转置或卷积只需要一个操作数
                                    if (key_posedge[0]) begin
                                        op_start <= 1'b1;
                                        current_mode <= S_OP_EXEC;
                                        param_state <= PARAM_IDLE;
                                    end
                                end
                            end
                            // 单操作数运算的确认
                            if ((current_op == OP_TRANS || current_op == OP_CONV) && key_posedge[0]) begin
                                op_start <= 1'b1;
                                current_mode <= S_OP_EXEC;
                                param_state <= PARAM_IDLE;
                            end
                        end
                        
                        PARAM_WAIT_M2: begin
                            if (rx_done_pulse && is_digit) begin
                                sel_m2 <= rx_digit;
                                param_state <= PARAM_WAIT_N2;
                            end
                        end
                        
                        PARAM_WAIT_N2: begin
                            if (rx_done_pulse && is_digit) begin
                                sel_n2 <= rx_digit;
                                param_state <= PARAM_WAIT_ID2;
                            end
                        end
                        
                        PARAM_WAIT_ID2: begin
                            if (rx_done_pulse && is_digit) begin
                                operand_id2 <= rx_digit;
                            end
                            // 双操作数运算的确认
                            if (key_posedge[0]) begin
                                op_start <= 1'b1;
                                current_mode <= S_OP_EXEC;
                                param_state <= PARAM_IDLE;
                            end
                        end
                        
                        PARAM_WAIT_SCALAR: begin
                            // 标量从拨码开关读取
                            scalar <= sw_clean[7:4];
                            if (key_posedge[0]) begin
                                op_start <= 1'b1;
                                current_mode <= S_OP_EXEC;
                                param_state <= PARAM_IDLE;
                            end
                        end
                        
                        default: param_state <= PARAM_IDLE;
                    endcase
                end

                // 执行运算：仅响应运算完成标志
                S_OP_EXEC: begin
                    if (op_done) begin
                        current_mode <= S_RESULT;
                    end
                end

                // 展示结果：S1/S4回主菜单，S2继续当前运算类型
                S_RESULT: begin
                    if (key_posedge[0] || key_posedge[3]) begin
                        current_mode <= S_MENU;
                    end else if (key_posedge[1]) begin
                        current_mode <= S_OP_PARAM;
                        param_state <= PARAM_IDLE;
                    end
                end

                S_RETURN: begin
                    current_mode <= S_MENU;
                end

                // 异常状态：复位关键寄存器并回主菜单
                default: begin
                    current_mode <= S_MENU;
                    countdown_en <= 1'b0;
                    operand_sel <= 2'b00;
                    current_op <= OP_TRANS;
                    param_state <= PARAM_IDLE;
                end
            endcase
        end
    end
end

// 9. LED控制逻辑（高电平点亮）
always @(*) begin
    LED = 8'b00000000;  // 默认全灭
    case (current_mode)
        S_MENU:      LED[0] = 1'b1;  // LED0=主菜单
        S_INPUT:     LED[1] = 1'b1;  // LED1=输入模式
        S_GEN:       LED[2] = 1'b1;  // LED2=生成模式
        S_SHOW:      LED[3] = 1'b1;  // LED3=展示模式
        S_OP_SELECT,
        S_OP_PARAM,
        S_OP_EXEC,
        S_RESULT:    LED[4] = 1'b1;  // LED4=运算模式
        default:     LED[0] = 1'b1;
    endcase
    // 有错误或倒计时期间，点亮LED5~LED7
    if (error_type != 3'b000 || countdown_en) begin
        LED[5] = 1'b1;
        LED[6] = 1'b1;
        LED[7] = 1'b1;
    end
end

// 10. 数码管控制逻辑
always @(*) begin
    seg_code = {SEG_OFF, SEG_OFF};  // 默认熄灭
    if (countdown_en) begin
        // 倒计时期间：显示剩余秒数
        case (countdown_sec)
            4'd0:  seg_code = {SEG_OFF, SEG_0};
            4'd1:  seg_code = {SEG_OFF, SEG_1};
            4'd2:  seg_code = {SEG_OFF, SEG_2};
            4'd3:  seg_code = {SEG_OFF, SEG_3};
            4'd4:  seg_code = {SEG_OFF, SEG_4};
            4'd5:  seg_code = {SEG_OFF, SEG_5};
            4'd6:  seg_code = {SEG_OFF, SEG_6};
            4'd7:  seg_code = {SEG_OFF, SEG_7};
            4'd8:  seg_code = {SEG_OFF, SEG_8};
            4'd9:  seg_code = {SEG_OFF, SEG_9};
            4'd10: seg_code = {SEG_1, SEG_0};
            4'd11: seg_code = {SEG_1, SEG_1};
            4'd12: seg_code = {SEG_1, SEG_2};
            4'd13: seg_code = {SEG_1, SEG_3};
            4'd14: seg_code = {SEG_1, SEG_4};
            4'd15: seg_code = {SEG_1, SEG_5};
            default: seg_code = {SEG_OFF, SEG_0};
        endcase
    end else begin
        case (current_mode)
            // 运算类型选择：显示运算类型
            S_OP_SELECT: begin
                case (sw_clean[2:0])
                    OP_TRANS:  seg_code[15:8] = SEG_T;
                    OP_ADD:    seg_code[15:8] = SEG_A;
                    OP_SCALAR: seg_code[15:8] = SEG_B;
                    OP_MUL:    seg_code[15:8] = SEG_C;
                    OP_CONV:   seg_code[15:8] = SEG_J;
                    default:   seg_code[15:8] = SEG_OFF;
                endcase
                seg_code[7:0] = SEG_OFF;
            end
            
            // 运算参数选择：显示当前运算类型
            S_OP_PARAM, S_OP_EXEC: begin
                case (current_op)
                    OP_TRANS:  seg_code[15:8] = SEG_T;
                    OP_ADD:    seg_code[15:8] = SEG_A;
                    OP_SCALAR: seg_code[15:8] = SEG_B;
                    OP_MUL:    seg_code[15:8] = SEG_C;
                    OP_CONV:   seg_code[15:8] = SEG_J;
                    default:   seg_code[15:8] = SEG_OFF;
                endcase
                seg_code[7:0] = SEG_OFF;
            end
            
            // 展示结果：显示结果矩阵维度
            S_RESULT: begin
                case (result_m)
                    4'd1: seg_code[15:8] = SEG_1;
                    4'd2: seg_code[15:8] = SEG_2;
                    4'd3: seg_code[15:8] = SEG_3;
                    4'd4: seg_code[15:8] = SEG_4;
                    4'd5: seg_code[15:8] = SEG_5;
                    default: seg_code[15:8] = SEG_OFF;
                endcase
                case (result_n)
                    4'd1: seg_code[7:0] = SEG_1;
                    4'd2: seg_code[7:0] = SEG_2;
                    4'd3: seg_code[7:0] = SEG_3;
                    4'd4: seg_code[7:0] = SEG_4;
                    4'd5: seg_code[7:0] = SEG_5;
                    default: seg_code[7:0] = SEG_OFF;
                endcase
            end
            
            // 主菜单：显示存储的矩阵数量
            S_MENU: begin
                case (total_mat_count)
                    4'd0: seg_code[7:0] = SEG_0;
                    4'd1: seg_code[7:0] = SEG_1;
                    4'd2: seg_code[7:0] = SEG_2;
                    4'd3: seg_code[7:0] = SEG_3;
                    4'd4: seg_code[7:0] = SEG_4;
                    4'd5: seg_code[7:0] = SEG_5;
                    4'd6: seg_code[7:0] = SEG_6;
                    4'd7: seg_code[7:0] = SEG_7;
                    4'd8: seg_code[7:0] = SEG_8;
                    4'd9: seg_code[7:0] = SEG_9;
                    default: seg_code[7:0] = SEG_OFF;
                endcase
                seg_code[15:8] = SEG_OFF;
            end
            
            default: seg_code = {SEG_OFF, SEG_OFF};
        endcase
    end
end

endmodule
