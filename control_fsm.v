`timescale 1ns / 1ps




module control_fsm(
    input clk,                  // 全局时钟（100MHz）
    input rst_n,                // 全局复位（低电平有效）
    input [7:0] SW,             // 8位拨码开关（SW0~SW7）
    input [4:0] KEY,            // 5位按键（S1~S5对应KEY[0]~KEY[4]）
    input op_done,              // 运算完成标志（来自成员C）
    input input_done,           // 输入/生成完成标志（来自成员C）
    input display_done,         // 展示完成标志（来自成员A）
    input [2:0] error_type,     // 错误类型（来自成员C：000=无错）
    input [7:0] uart_rx_data,   // 配置指令（来自成员A）
    input rx_done,              // 配置指令接收完成（来自成员A）
    input [3:0] max_mat_num,    // 矩阵最大存储个数（来自param_config）
    input [7:0] val_min,        // 元素最小值（来自param_config）
    input [7:0] val_max,        // 元素最大值（来自param_config）
    input config_done,          // 配置完成标志（来自param_config）
    input [3:0] result_m,       // 结果矩阵行数（来自成员C）
    input [3:0] result_n,       // 结果矩阵列数（来自成员C）
    output reg [3:0] current_mode,  // 当前状态（输出给所有模块）
    output reg [2:0] current_op,    // 运算类型（输出给成员C）
    output reg [7:0] LED,           // LED控制（输出给开发板）
    output reg [15:0] seg_code,     // 数码管控制（16位：左4+右4）
    output reg [3:0] scalar,        // 标量值（输出给成员C）
    output reg [1:0] operand_sel,   // 运算数选择模式（00=手动，01=随机）
    output reg [3:0] countdown_sec  // 倒计时秒数（输出给成员A）
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
localparam SEG_2       = 8'b01001001;  // 2
localparam SEG_3       = 8'b01001101;  // 3
localparam SEG_4       = 8'b00100111;  // 4
localparam SEG_5       = 8'b00101101;  // 5
localparam SEG_6       = 8'b00111101;  // 6
localparam SEG_7       = 8'b01000011;  // 7
localparam SEG_8       = 8'b00000001;  // 8
localparam SEG_9       = 8'b00000101;  // 9
localparam SEG_T       = 8'b01010001;  // T
localparam SEG_A       = 8'b00010001;  // A
localparam SEG_B       = 8'b00110001;  // B
localparam SEG_C       = 8'b01000101;  // C
localparam SEG_J       = 8'b01011001;  // J

// 4. 防误操作相关定义（100MHz时钟适配）
reg [23:0] key_cnt;           // 按键消抖计数器（100MHz*10ms=1,000,000）
reg [4:0] key_sync;           // 按键同步寄存器
reg [4:0] key_clean;          // 消抖后的按键信号（高电平有效）
reg [23:0] sw_cnt;            // 拨码开关防抖计数器
reg [7:0] sw_sync;            // 拨码开关同步寄存器
reg [7:0] sw_clean;           // 防抖后的拨码开关信号
reg [31:0] countdown_cnt;     // 错误倒计时计数器（100MHz时钟）
reg countdown_en;             // 倒计时使能信号
reg [3:0] countdown_cfg;      // 倒计时配置值（5~15秒，默认10秒）

// 5. 复位初始化（低电平有效）
always @(negedge rst_n) begin
    current_mode <= S_MENU;       // 复位后回到主菜单
    current_op <= OP_TRANS;       // 默认运算类型：转置
    LED <= 8'b00000000;           // 所有LED熄灭
    seg_code <= {SEG_OFF, SEG_OFF};// 数码管熄灭
    scalar <= 4'd0;               // 标量默认0
    operand_sel <= 2'b00;         // 默认手动选择运算数
    key_cnt <= 24'd0;
    key_sync <= 5'b00000;
    key_clean <= 5'b00000;
    sw_cnt <= 24'd0;
    sw_sync <= 8'b00000000;
    sw_clean <= 8'b00000000;
    countdown_cnt <= 32'd0;
    countdown_sec <= 4'd10;       // 默认倒计时10秒
    countdown_cfg <= 4'd10;       // 默认配置10秒
    countdown_en <= 1'b0;
end

// 6. 按键消抖逻辑（100MHz时钟：10ms=1,000,000个时钟周期）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_sync <= 5'b00000;
        key_clean <= 5'b00000;
        key_cnt <= 24'd0;
    end else begin
        // 第一步：同步按键信号（消除亚稳态）
        key_sync <= KEY;
        // 第二步：消抖计时
        if (key_sync != key_clean) begin
            key_cnt <= 24'd1000000;  // 100MHz * 10ms = 1e6
        end else if (key_cnt > 24'd0) begin
            key_cnt <= key_cnt - 24'd1;
        end else begin
            key_clean <= key_sync;  // 计时结束，更新消抖后的按键信号
        end
    end
end

// 7. 拨码开关防抖逻辑（同按键消抖）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sw_sync <= 8'b00000000;
        sw_clean <= 8'b00000000;
        sw_cnt <= 24'd0;
    end else begin
        // 第一步：同步拨码开关信号
        sw_sync <= SW;
        // 第二步：防抖计时
        if (sw_sync != sw_clean) begin
            sw_cnt <= 24'd1000000;  // 10ms防抖
        end else if (sw_cnt > 24'd0) begin
            sw_cnt <= sw_cnt - 24'd1;
        end else begin
            sw_clean <= sw_sync;  // 计时结束，更新防抖后的开关信号
        end
    end
end

// 8. 错误倒计时逻辑（100MHz时钟：1秒=1e8个时钟周期）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        countdown_cnt <= 32'd0;
        countdown_sec <= 4'd10;
        countdown_cfg <= 4'd10;
        countdown_en <= 1'b0;
    end else begin
        // 有错误且在运算数选择状态，启动倒计时（仅首次触发）
        if (error_type != 3'b000 && current_mode == S_OP_PARAM && !countdown_en) begin
            countdown_en <= 1'b1;
            countdown_cnt <= 32'd100000000 * countdown_cfg;  // 100MHz * N秒
            countdown_sec <= countdown_cfg;  // 初始剩余秒数=配置值
        end
        // 倒计时期间：递减计数，实时更新剩余秒数
        if (countdown_en && countdown_cnt > 32'd0) begin
            countdown_cnt <= countdown_cnt - 32'd1;
            countdown_sec <= countdown_cnt / 32'd100000000;  // 剩余秒数=当前计数/1e8
        end
        // 倒计时结束：重置
        else if (countdown_en && countdown_cnt == 32'd0) begin
            countdown_en <= 1'b0;
            countdown_sec <= countdown_cfg;
            current_mode <= S_OP_PARAM;  // 回到运算数选择起始阶段
        end
        // 运算数合法或退出参数选择状态：立即关闭倒计时
        if (error_type == 3'b000 || current_mode != S_OP_PARAM) begin
            countdown_en <= 1'b0;
            countdown_sec <= countdown_cfg;
        end
    end
end

// 9. 状态跳转逻辑（完整支持"继续当前模式"）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_mode <= S_MENU;
    end else begin
        // 倒计时期间，仅允许重新选择运算数或返回
        if (countdown_en) begin
            case (current_mode)
                S_OP_PARAM: begin
                    if (key_clean[0] == 1'b1) begin  // 按S1确认新运算数
                        current_mode <= S_OP_EXEC;
                    end else if (key_clean[2] == 1'b1) begin  // 按S3返回运算类型选择
                        current_mode <= S_OP_SELECT;
                        countdown_en <= 1'b0;
                    end else if (key_clean[3] == 1'b1) begin  // 按S4回主菜单
                        current_mode <= S_MENU;
                        countdown_en <= 1'b0;
                    end
                end
                default: current_mode <= current_mode;  // 其他状态锁死
            endcase
        end else begin
            // 正常流程：支持"继续当前模式"或"返回主菜单"
            case (current_mode)
                // 主菜单：SW5~SW7选择+S1确认
                S_MENU: begin
                    if (key_clean[0] == 1'b1) begin
                        case (sw_clean[7:5])
                            3'b000: current_mode <= S_INPUT;
                            3'b001: current_mode <= S_GEN;
                            3'b010: current_mode <= S_SHOW;
                            3'b011: current_mode <= S_OP_SELECT;
                            default: current_mode <= S_MENU;
                        endcase
                    end else if (key_clean[3] == 1'b1) begin
                        current_mode <= S_MENU;
                    end
                end

                // 输入模式：输入完成后，S1/S3返回主菜单，S2继续输入
                S_INPUT: begin
                    if (input_done == 1'b1) begin
                        if (key_clean[0] == 1'b1 || key_clean[2] == 1'b1) begin
                            current_mode <= S_MENU;
                        end else if (key_clean[1] == 1'b1) begin  // 继续当前模式
                            current_mode <= S_INPUT;
                        end
                    end
                end

                // 生成模式：和输入模式逻辑一致
                S_GEN: begin
                    if (input_done == 1'b1) begin
                        if (key_clean[0] == 1'b1 || key_clean[2] == 1'b1) begin
                            current_mode <= S_MENU;
                        end else if (key_clean[1] == 1'b1) begin  // 继续当前模式
                            current_mode <= S_GEN;
                        end
                    end
                end

                // 展示模式：展示完成后，S1返回主菜单，S2继续展示
                S_SHOW: begin
                    if (display_done == 1'b1) begin
                        if (key_clean[0] == 1'b1) begin
                            current_mode <= S_MENU;
                        end else if (key_clean[1] == 1'b1) begin  // 继续当前模式
                            current_mode <= S_SHOW;
                        end
                    end
                end

                // 运算类型选择：S1确认，S3返回主菜单
                S_OP_SELECT: begin
                    if (key_clean[0] == 1'b1) begin
                        current_op <= sw_clean[2:0];
                        current_mode <= S_OP_PARAM;
                    end else if (key_clean[2] == 1'b1) begin
                        current_mode <= S_MENU;
                    end
                end

                // 选择运算数：S1确认，S3返回，S5切换随机选择
                S_OP_PARAM: begin
                    if (key_clean[0] == 1'b1) begin
                        if (current_op == OP_SCALAR) begin
                            scalar <= {2'b00, sw_clean[4:3]};  // SW3~SW4选择标量（0~3）
                        end
                        current_mode <= S_OP_EXEC;
                    end else if (key_clean[2] == 1'b1) begin
                        current_mode <= S_OP_SELECT;
                    end else if (key_clean[4] == 1'b1) begin
                        operand_sel <= 2'b01;  // 切换为系统随机选择
                    end
                end

                // 执行运算：仅响应运算完成标志
                S_OP_EXEC: begin
                    if (op_done == 1'b1) begin
                        current_mode <= S_RESULT;
                    end
                end

                // 展示结果：S1/S4回主菜单，S2继续当前运算类型
                S_RESULT: begin
                    if (key_clean[0] == 1'b1 || key_clean[3] == 1'b1) begin
                        current_mode <= S_MENU;
                    end else if (key_clean[1] == 1'b1) begin  // 继续当前运算
                        current_mode <= S_OP_PARAM;
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
                end
            endcase
        end
    end
end

// 10. LED控制逻辑（高电平点亮，匹配约束文件引脚）
always @(*) begin
    LED = 8'b00000000;  // 默认全灭
    case (current_mode)
        S_MENU:      LED[0] = 1'b1;  // LED0=主菜单（K3引脚）
        S_INPUT:     LED[1] = 1'b1;  // LED1=输入模式（M1引脚）
        S_GEN:       LED[2] = 1'b1;  // LED2=生成模式（L1引脚）
        S_SHOW:      LED[3] = 1'b1;  // LED3=展示模式（K6引脚）
        S_OP_SELECT,
        S_OP_PARAM,
        S_OP_EXEC,
        S_RESULT:    LED[4] = 1'b1;  // LED4=运算模式（J5引脚）
    endcase
    // 有错误或倒计时期间，点亮LED5~LED7（H5、H6、K1引脚）
    if (error_type != 3'b000 || countdown_en) begin
        LED[5] = 1'b1;
        LED[6] = 1'b1;
        LED[7] = 1'b1;
    end
end

// 11. 数码管控制逻辑（16位，匹配约束文件引脚）
always @(*) begin
    seg_code = {SEG_OFF, SEG_OFF};  // 默认熄灭
    if (countdown_en) begin
        // 倒计时期间：左4位=十位，右4位=个位
        case (countdown_sec / 4'd10)  // 十位（seg_code[15:8]）
            4'd0: seg_code[15:8] = SEG_OFF;
            4'd1: seg_code[15:8] = SEG_1;
            default: seg_code[15:8] = SEG_OFF;
        endcase
        case (countdown_sec % 4'd10)  // 个位（seg_code[7:0]）
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
            default: seg_code[7:0] = SEG_0;
        endcase
    end else begin
        case (current_mode)
            // 运算类型选择：左4位显示运算类型，右4位熄灭
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
            // 输入/生成模式：右4位显示维度（SW3~SW4）
            S_INPUT, S_GEN: begin
                case (sw_clean[4:3])
                    2'b00: seg_code[7:0] = SEG_1;  // 1行/列
                    2'b01: seg_code[7:0] = SEG_2;  // 2行/列
                    2'b10: seg_code[7:0] = SEG_3;  // 3行/列
                    2'b11: seg_code[7:0] = SEG_4;  // 4行/列
                    default: seg_code[7:0] = SEG_1;
                endcase
                seg_code[15:8] = SEG_OFF;
            end
            // 展示结果：左4位显示行数，右4位显示列数
            S_RESULT: begin
                // 行数显示（result_m=1~5）
                case (result_m)
                    4'd1: seg_code[15:8] = SEG_1;
                    4'd2: seg_code[15:8] = SEG_2;
                    4'd3: seg_code[15:8] = SEG_3;
                    4'd4: seg_code[15:8] = SEG_4;
                    4'd5: seg_code[15:8] = SEG_5;
                    default: seg_code[15:8] = SEG_OFF;
                endcase
                // 列数显示（result_n=1~5）
                case (result_n)
                    4'd1: seg_code[7:0] = SEG_1;
                    4'd2: seg_code[7:0] = SEG_2;
                    4'd3: seg_code[7:0] = SEG_3;
                    4'd4: seg_code[7:0] = SEG_4;
                    4'd5: seg_code[7:0] = SEG_5;
                    default: seg_code[7:0] = SEG_OFF;
                endcase
            end
        endcase
    end
end

endmodule