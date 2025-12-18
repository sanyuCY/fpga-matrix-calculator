//矩阵输入解析模块
// 模块功能：解析UART串口输入的矩阵数据，完成维度/元素合法性检测，输出结构化矩阵数据
module matrix_input(
    input clk,
    input rst_n,// 低电平复位（0=复位，1=正常工作）
    //来自UART模块
    input [7:0] uart_rx_data, // UART接收的单字节数据（ASCII码，8位）
    input rx_done,      // UART单字节接收完成标志（高电平有效，持续1个时钟）
    // 来自FSM模块
    input [3:0] val_min,
    input [3:0]  val_max,
    //设计四位以便覆盖到15
    // 输出到存储/运算模块的矩阵数据
    output reg [3:0] mat_m,
    output reg [3:0] mat_n, // 便于对接
    output reg [3:0] mat_data [0:4][0:4], // 5×5二维数组
    // 输出到FSM模块的状态or错误标志
    output reg input_done, // 输入解析完成标志（高电平有效，持续1个时钟）
    output reg [2:0] error_type  // 错误类型（3位，和接口手册一致：000=无错，001=维度错，011=元素值错）
);
// 1. 状态机定义（有限状态机FSM，控制解析流程）
// localprarm提高代码可读性同时降低维护成本
localparam S_WAIT = 3'b000; // 等待UART数据输入
localparam S_PARSE_M = 3'b001; // 解析矩阵行数m
localparam S_PARSE_N = 3'b010; // 解析矩阵列数n
localparam S_PARSE_DATA= 3'b011; // 解析矩阵元素
localparam S_CHECK = 3'b100; // 合法性检测
localparam S_DONE = 3'b101; // 解析完成，输出结果
// 2. 状态机寄存器（存储当前状态）
reg [2:0] curr_state;  // 当前状态
reg [2:0] next_state;  // 下一状态（两段式状态机，提高稳定性）
// 3. 临时存储寄存器（避免直接覆盖输出寄存器）
reg [3:0] m_temp;      // 行数临时缓存（解析完成后再赋值给mat_m）
reg [3:0] n_temp;      // 列数临时缓存
reg [3:0] data_temp [0:4][0:4]; // 元素临时缓存（避免解析中输出无效数据）
// 4. 计数寄存器（统计已解析的元素个数）
reg [4:0]  data_cnt;    // 元素计数器（0~24，5×5=25个元素）
// 功能：在时钟上升沿更新当前状态（复位时回到等待状态）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        curr_state <= S_WAIT; // 复位后初始状态：等待
    end else begin
        curr_state <= next_state; // 非复位时，更新为下一状态
    end
end
// 功能：根据当前状态+输入条件，计算下一状态（无时序，纯逻辑判断）
always @(*) begin
    next_state = curr_state; // 默认保持当前状态（避免锁存器生成）
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
            // 合法性检测完成后，直接进入完成状态
            next_state = S_DONE;
        end
        S_DONE: begin
            // 完成后回到等待状态，准备下一次解析
            next_state = S_WAIT;
        end
        default: begin
            next_state = S_WAIT; // 异常状态回到等待，提高鲁棒性
        end
    endcase
end
// 功能：在不同状态下，锁存UART数据到临时寄存器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位：清空所有临时寄存器和计数器
        m_temp <= 4'd0;
        n_temp <= 4'd0;
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
        data_cnt <= 5'd0;
    end else begin
        case(curr_state)
            S_PARSE_M: begin
                // ASCII0-9均满足后四位为数字本身
                if(rx_done) begin
                    m_temp <= uart_rx_data[3:0]; // 8'h32的低4位是2，完成ASCII→数字转换
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
                    // 元素索引，找到第几行第几列
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
integer i, j;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位：清空输出寄存器和标志
        mat_m <= 4'd0;
        mat_n <= 4'd0;
        mat_data[0][0] <= 4'd0;
        mat_data[0][1] <= 4'd0;
        mat_data[0][2] <= 4'd0;
        mat_data[0][3] <= 4'd0;
        mat_data[0][4] <= 4'd0;
        mat_data[1][0] <= 4'd0;
        mat_data[1][1] <= 4'd0;
        mat_data[1][2] <= 4'd0;
        mat_data[1][3] <= 4'd0;
        mat_data[1][4] <= 4'd0;
        mat_data[2][0] <= 4'd0;
        mat_data[2][1] <= 4'd0;
        mat_data[2][2] <= 4'd0;
        mat_data[2][3] <= 4'd0;
        mat_data[2][4] <= 4'd0;
        mat_data[3][0] <= 4'd0;
        mat_data[3][1] <= 4'd0;
        mat_data[3][2] <= 4'd0;
        mat_data[3][3] <= 4'd0;
        mat_data[3][4] <= 4'd0;
        mat_data[4][0] <= 4'd0;
        mat_data[4][1] <= 4'd0;
        mat_data[4][2] <= 4'd0;
        mat_data[4][3] <= 4'd0;
        mat_data[4][4] <= 4'd0;
        input_done <= 1'b0;
        error_type <= 3'b000;
    end else begin
        case(curr_state)
            S_CHECK: begin
                // 初始化错误类型为无错
                error_type <= 3'b000;
                
                // 检测维度合法性（1~5）
                if(m_temp < 4'd1 || m_temp > 4'd5 || n_temp < 4'd1 || n_temp > 4'd5) begin
                    error_type <= 3'b001; // 维度错误001
                end else begin
                    // 第二步：检测元素值合法性（val_min~val_max）
                    for(i=0; i<m_temp; i=i+1) begin 
                        for(j=0; j<n_temp; j=j+1) begin 
                            if(data_temp[i][j] < val_min || data_temp[i][j] > val_max) begin
                                error_type <= 3'b011; // 元素值错误011
                            end
                        end
                    end
                end
            end
            S_DONE: begin
                // 无错误时，将临时数据赋值给输出寄存器
                if(error_type == 3'b000) begin
                    mat_m <= m_temp;
                    mat_n <= n_temp;
                    for(i=0; i<m_temp; i=i+1) begin
                        for(j=0; j<n_temp; j=j+1) begin
                            mat_data[i][j] <= data_temp[i][j];
                        end
                    end
                end else begin
                    // 有错误时，清空输出（避免输出非法数据）
                    mat_m <= 4'd0;
                    mat_n <= 4'd0;
                    mat_data[0][0] <= 4'd0;
                    mat_data[0][1] <= 4'd0;
                    mat_data[0][2] <= 4'd0;
                    mat_data[0][3] <= 4'd0;
                    mat_data[0][4] <= 4'd0;
                    mat_data[1][0] <= 4'd0;
                    mat_data[1][1] <= 4'd0;
                    mat_data[1][2] <= 4'd0;
                    mat_data[1][3] <= 4'd0;
                    mat_data[1][4] <= 4'd0;
                    mat_data[2][0] <= 4'd0;
                    mat_data[2][1] <= 4'd0;
                    mat_data[2][2] <= 4'd0;
                    mat_data[2][3] <= 4'd0;
                    mat_data[2][4] <= 4'd0;
                    mat_data[3][0] <= 4'd0;
                    mat_data[3][1] <= 4'd0;
                    mat_data[3][2] <= 4'd0;
                    mat_data[3][3] <= 4'd0;
                    mat_data[3][4] <= 4'd0;
                    mat_data[4][0] <= 4'd0;
                    mat_data[4][1] <= 4'd0;
                    mat_data[4][2] <= 4'd0;
                    mat_data[4][3] <= 4'd0;
                    mat_data[4][4] <= 4'd0;
                end
                // 置位完成标志（告诉FSM模块解析完成）
                input_done <= 1'b1;
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