//矩阵输入解析模块
// 模块功能：解析UART串口输入的矩阵数据，完成维度/元素合法性检测，输出结构化矩阵数据
// 适配Vivado 2017：将5×5二维数组拆分为25个独立4位信号，规避数组端口兼容问题
module matrix_input(
    input clk,
    input rst_n,// 低电平复位（0=复位，1=正常工作）
    //来自UART模块
    input [7:0] uart_rx_data, // UART接收的单字节数据（ASCII码，8位）
    input rx_done,      // UART单字节接收完成标志（高电平有效，持续1个时钟）
    // 来自FSM模块
    input [3:0] val_min,
    input [3:0] val_max,
    // 输出到存储/运算模块的矩阵维度
    output reg [3:0] mat_m,  // 矩阵行数（1~5）
    output reg [3:0] mat_n,  // 矩阵列数（1~5）
    // 核心修改：5×5矩阵拆分为25个独立4位信号（替代二维数组端口）
    output reg [3:0] mat_data_00, mat_data_01, mat_data_02, mat_data_03, mat_data_04,
    output reg [3:0] mat_data_10, mat_data_11, mat_data_12, mat_data_13, mat_data_14,
    output reg [3:0] mat_data_20, mat_data_21, mat_data_22, mat_data_23, mat_data_24,
    output reg [3:0] mat_data_30, mat_data_31, mat_data_32, mat_data_33, mat_data_34,
    output reg [3:0] mat_data_40, mat_data_41, mat_data_42, mat_data_43, mat_data_44,
    // 输出到FSM模块的状态/错误标志
    output reg input_done, // 解析完成标志（高电平有效，持续1个时钟）
    output reg [2:0] error_type  // 错误类型：000=无错，001=维度错，011=元素值错
);

// 状态机定义（和原始代码完全一致）
localparam S_WAIT = 3'b000;     // 等待UART数据输入
localparam S_PARSE_M = 3'b001;  // 解析矩阵行数m
localparam S_PARSE_N = 3'b010;  // 解析矩阵列数n
localparam S_PARSE_DATA= 3'b011;// 解析矩阵元素
localparam S_CHECK = 3'b100;    // 合法性检测
localparam S_DONE = 3'b101;     // 解析完成，输出结果

// 状态机寄存器（和原始代码完全一致）
reg [2:0] curr_state;  // 当前状态
reg [2:0] next_state;  // 下一状态（两段式状态机）

// 临时存储寄存器（内部仍用二维数组，不影响逻辑编写）
reg [3:0] m_temp;      // 行数临时缓存
reg [3:0] n_temp;      // 列数临时缓存
reg [3:0] data_temp [0:4][0:4]; // 元素临时缓存（5×5）
reg [4:0] data_cnt;    // 元素计数器（0~24）

// 循环变量声明（和原始代码一致）
integer i, j;

// 功能1：状态机当前状态更新（时钟沿触发）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        curr_state <= S_WAIT; // 复位后初始状态：等待
    end else begin
        curr_state <= next_state; // 非复位时更新为下一状态
    end
end

// 功能2：状态机下一状态计算（组合逻辑）
always @(*) begin
    next_state = curr_state; // 默认保持当前状态（避免锁存器）
    case(curr_state)
        S_WAIT: begin
            // 触发条件：UART收到第一个字节（行数m）
            if(rx_done) begin
                next_state = S_PARSE_M;
            end
        end
        S_PARSE_M: begin
            // 触发条件：UART收到第二个字节（列数n）
            if(rx_done) begin
                next_state = S_PARSE_N;
            end
        end
        S_PARSE_N: begin
            // 触发条件：UART收到第三个字节（第一个元素）
            if(rx_done) begin
                next_state = S_PARSE_DATA;
            end
        end
        S_PARSE_DATA: begin
            // 触发条件：元素解析完成（计数器达到m×n-1）且收到最后一个元素
            if(rx_done && (data_cnt == m_temp * n_temp - 1)) begin
                next_state = S_CHECK;
            end
        end
        S_CHECK: begin
            // 合法性检测完成后，进入完成状态
            next_state = S_DONE;
        end
        S_DONE: begin
            // 完成后回到等待状态，准备下一次解析
            next_state = S_WAIT;
        end
        default: begin
            // 异常状态回到等待，提高鲁棒性
            next_state = S_WAIT;
        end
    endcase
end

// 功能3：UART数据锁存到临时寄存器（和原始代码完全一致）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位：清空所有临时寄存器和计数器
        m_temp <= 4'd0;
        n_temp <= 4'd0;
        data_cnt <= 5'd0;
        // 临时数组逐元素复位（和原始代码一致）
        data_temp[0][0] <= 4'd0;
        data_temp[0][1] <= 4'd0;
        data_temp[0][2] <= 4'd0;
        data_temp[0][3] <= 4'd0;
        data_temp[0][4] <= 4'd0;
        data_temp[1][0] <= 4'd0;
        data_temp[1][1] <= 4'd0;
        data_temp[1][2] <= 4'd0;
        data_temp[1][3] <= 4'd0;
        data_temp[1][4] <= 4'd0;
        data_temp[2][0] <= 4'd0;
        data_temp[2][1] <= 4'd0;
        data_temp[2][2] <= 4'd0;
        data_temp[2][3] <= 4'd0;
        data_temp[2][4] <= 4'd0;
        data_temp[3][0] <= 4'd0;
        data_temp[3][1] <= 4'd0;
        data_temp[3][2] <= 4'd0;
        data_temp[3][3] <= 4'd0;
        data_temp[3][4] <= 4'd0;
        data_temp[4][0] <= 4'd0;
        data_temp[4][1] <= 4'd0;
        data_temp[4][2] <= 4'd0;
        data_temp[4][3] <= 4'd0;
        data_temp[4][4] <= 4'd0;
    end else begin
        case(curr_state)
            S_PARSE_M: begin
                // ASCII转数字：取低4位（0~9）
                if(rx_done) begin
                    m_temp <= uart_rx_data[3:0];
                end
            end
            S_PARSE_N: begin
                // 解析列数n：和行数逻辑一致
                if(rx_done) begin
                    n_temp <= uart_rx_data[3:0];
                end
            end
            S_PARSE_DATA: begin
                // 解析元素：按行列索引存储到临时数组
                if(rx_done) begin
                    data_temp[data_cnt / n_temp][data_cnt % n_temp] <= uart_rx_data[3:0];
                    data_cnt <= data_cnt + 1'b1; // 计数器自增
                end
            end
            S_DONE: begin
                // 解析完成后，重置计数器
                data_cnt <= 5'd0;
            end
            default: begin
                // 其他状态保持临时寄存器不变
                m_temp <= m_temp;
                n_temp <= n_temp;
                data_cnt <= data_cnt;
            end
        endcase
    end
end

// 功能4：合法性检测 + 输出结果赋值（核心修改：独立信号赋值）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位：清空所有输出寄存器和标志
        mat_m <= 4'd0;
        mat_n <= 4'd0;
        input_done <= 1'b0;
        error_type <= 3'b000;
        // 独立信号逐位复位（和原始代码数组复位逻辑一致）
        mat_data_00 <= 4'd0; mat_data_01 <= 4'd0; mat_data_02 <= 4'd0; mat_data_03 <= 4'd0; mat_data_04 <= 4'd0;
        mat_data_10 <= 4'd0; mat_data_11 <= 4'd0; mat_data_12 <= 4'd0; mat_data_13 <= 4'd0; mat_data_14 <= 4'd0;
        mat_data_20 <= 4'd0; mat_data_21 <= 4'd0; mat_data_22 <= 4'd0; mat_data_23 <= 4'd0; mat_data_24 <= 4'd0;
        mat_data_30 <= 4'd0; mat_data_31 <= 4'd0; mat_data_32 <= 4'd0; mat_data_33 <= 4'd0; mat_data_34 <= 4'd0;
        mat_data_40 <= 4'd0; mat_data_41 <= 4'd0; mat_data_42 <= 4'd0; mat_data_43 <= 4'd0; mat_data_44 <= 4'd0;
    end else begin
        case(curr_state)
            S_CHECK: begin
                // 初始化错误类型为无错
                error_type <= 3'b000;
                
                // 第一步：检测维度合法性（1~5）
                if(m_temp < 4'd1 || m_temp > 4'd5 || n_temp < 4'd1 || n_temp > 4'd5) begin
                    error_type <= 3'b001; // 维度错误
                end else begin
                    // 第二步：检测元素值合法性（val_min~val_max）
                    for(i=0; i<m_temp; i=i+1) begin 
                        for(j=0; j<n_temp; j=j+1) begin 
                            if(data_temp[i][j] < val_min || data_temp[i][j] > val_max) begin
                                error_type <= 3'b011; // 元素值错误
                            end
                        end
                    end
                end
            end
            S_DONE: begin
                // 置位完成标志（告诉FSM模块解析完成）
                input_done <= 1'b1;
                
                if(error_type == 3'b000) begin
                    // 无错误：输出矩阵维度 + 独立信号赋值（和原始数组一一对应）
                    mat_m <= m_temp;
                    mat_n <= n_temp;
                    // 逐元素赋值：临时数组 → 独立输出信号
                    mat_data_00 <= data_temp[0][0]; mat_data_01 <= data_temp[0][1]; mat_data_02 <= data_temp[0][2]; mat_data_03 <= data_temp[0][3]; mat_data_04 <= data_temp[0][4];
                    mat_data_10 <= data_temp[1][0]; mat_data_11 <= data_temp[1][1]; mat_data_12 <= data_temp[1][2]; mat_data_13 <= data_temp[1][3]; mat_data_14 <= data_temp[1][4];
                    mat_data_20 <= data_temp[2][0]; mat_data_21 <= data_temp[2][1]; mat_data_22 <= data_temp[2][2]; mat_data_23 <= data_temp[2][3]; mat_data_24 <= data_temp[2][4];
                    mat_data_30 <= data_temp[3][0]; mat_data_31 <= data_temp[3][1]; mat_data_32 <= data_temp[3][2]; mat_data_33 <= data_temp[3][3]; mat_data_34 <= data_temp[3][4];
                    mat_data_40 <= data_temp[4][0]; mat_data_41 <= data_temp[4][1]; mat_data_42 <= data_temp[4][2]; mat_data_43 <= data_temp[4][3]; mat_data_44 <= data_temp[4][4];
                end else begin
                    // 有错误：清空所有输出（避免输出无效数据）
                    mat_m <= 4'd0;
                    mat_n <= 4'd0;
                    mat_data_00 <= 4'd0; mat_data_01 <= 4'd0; mat_data_02 <= 4'd0; mat_data_03 <= 4'd0; mat_data_04 <= 4'd0;
                    mat_data_10 <= 4'd0; mat_data_11 <= 4'd0; mat_data_12 <= 4'd0; mat_data_13 <= 4'd0; mat_data_14 <= 4'd0;
                    mat_data_20 <= 4'd0; mat_data_21 <= 4'd0; mat_data_22 <= 4'd0; mat_data_23 <= 4'd0; mat_data_24 <= 4'd0;
                    mat_data_30 <= 4'd0; mat_data_31 <= 4'd0; mat_data_32 <= 4'd0; mat_data_33 <= 4'd0; mat_data_34 <= 4'd0;
                    mat_data_40 <= 4'd0; mat_data_41 <= 4'd0; mat_data_42 <= 4'd0; mat_data_43 <= 4'd0; mat_data_44 <= 4'd0;
                end
            end
            default: begin
                // 其他状态：清空完成标志，保持错误类型
                input_done <= 1'b0;
                error_type <= error_type;
            end
        endcase
    end
end

endmodule