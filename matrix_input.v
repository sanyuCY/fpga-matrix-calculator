module matrix_input(
    input clk,
    input rst_n,
    input [7:0] uart_rx_data,
    input rx_done,
    input [3:0] val_min,
    input [3:0] val_max,
    output reg [3:0] mat_m,
    output reg [3:0] mat_n,
    output reg [3:0] mat_data_00, mat_data_01,
    output reg input_done,
    output reg [2:0] error_type
);

// 仅保留核心信号，去掉无关的mat_data_xx，减少干扰
reg [1:0] step;       // 接收步骤：0=待收m，1=待收n，2=待收元素，3=完成
reg [3:0] m_cache;    // 锁存m
reg [3:0] n_cache;    // 锁存n
reg [3:0] elem1;      // 锁存第一个元素（0,0）
reg [3:0] elem2;      // 锁存第二个元素（0,1）
reg [1:0] elem_cnt;   // 元素计数

// 步骤1：分阶段接收m/n/元素（无除零，无计数器错误）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        step <= 2'd0;
        m_cache <= 4'd0;
        n_cache <= 4'd0;
        elem1 <= 4'd0;
        elem2 <= 4'd0;
        elem_cnt <= 2'd0;
    end else begin
        if(rx_done) begin
            case(step)
                2'd0: begin // 接收m
                    m_cache <= uart_rx_data[3:0];
                    step <= 2'd1;
                end
                2'd1: begin // 接收n
                    n_cache <= uart_rx_data[3:0];
                    step <= 2'd2;
                end
                2'd2: begin // 接收元素（仅2x2）
                    if(elem_cnt == 2'd0) begin
                        elem1 <= uart_rx_data[3:0]; // 第一个元素
                        elem_cnt <= 2'd1;
                    end else if(elem_cnt == 2'd1) begin
                        elem2 <= uart_rx_data[3:0]; // 第二个元素
                        step <= 2'd3; // 接收完成
                    end
                end
            endcase
        end
    end
end

// 步骤2：直接赋值输出（无复杂条件，强制生效）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mat_m <= 4'd0;
        mat_n <= 4'd0;
        mat_data_00 <= 4'd0;
        mat_data_01 <= 4'd0;
        input_done <= 1'b0;
        error_type <= 3'b000;
    end else begin
        // 默认值
        input_done <= 1'b0;
        error_type <= 3'b000;

        // 步骤3=完成，开始赋值
        if(step == 2'd3) begin
            input_done <= 1'b1;
            // 维度检测
            if(m_cache < 1 || m_cache > 5 || n_cache < 1 || n_cache > 5) begin
                error_type <= 3'b001;
                mat_m <= 4'd0;
                mat_n <= 4'd0;
                mat_data_00 <= 4'd0;
                mat_data_01 <= 4'd0;
            end else begin
                // 元素检测
                if(elem1 < val_min || elem1 > val_max || elem2 < val_min || elem2 > val_max) begin
                    error_type <= 3'b011;
                    mat_m <= 4'd0;
                    mat_n <= 4'd0;
                    mat_data_00 <= 4'd0;
                    mat_data_01 <= 4'd0;
                end else begin
                    // 强制赋值，100%生效
                    mat_m <= m_cache;
                    mat_n <= n_cache;
                    mat_data_00 <= elem1;
                    mat_data_01 <= elem2;
                end
            end
        end
    end
end

endmodule