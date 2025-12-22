`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_core_top - 完整集成版
// 功能: 集成所有子模块，提供完整的矩阵计算器功能
//////////////////////////////////////////////////////////////////////////////

module matrix_core_top (
    input wire clk,
    input wire rst_n,
    input wire [7:0] uart_rx_data,
    input wire rx_done,
    input wire [3:0] current_mode,
    input wire [2:0] current_op,
    input wire [3:0] max_mat_num,
    input wire [7:0] val_min,
    input wire [7:0] val_max,
    input wire [1:0] operand_sel,
    input wire [3:0] scalar,
    input wire [3:0] operand_id1,
    input wire [3:0] operand_id2,
    input wire op_start,
    
    output wire [39:0] stored_mat_m_flat,
    output wire [39:0] stored_mat_n_flat,
    output wire [39:0] stored_mat_id_flat,
    output wire [1999:0] stored_mat_flat,
    output wire [3:0] total_mat_count,
    output wire [399:0] result_mat_flat,
    output wire [3:0] result_m,
    output wire [3:0] result_n,
    output wire input_done,
    output wire op_done,
    output wire [2:0] error_type,
    output wire display_en,
    output wire [1:0] display_type,
    output wire [99:0] spec_count_flat,
    output wire [31:0] cycle_cnt
);

    // 状态参数
    localparam S_OP_PARAM = 4'b0101;
    localparam S_OP_EXEC  = 4'b0110;

    //==========================================================================
    // 输入模块连线
    //==========================================================================
    wire [3:0] input_mat_m, input_mat_n;
    wire [199:0] input_mat_data;
    wire input_store_en, input_module_done;
    wire [2:0] input_error;
    
    //==========================================================================
    // 生成模块连线
    //==========================================================================
    wire [3:0] gen_mat_m, gen_mat_n, gen_mat_count;
    wire [199:0] gen_mat_data;
    wire gen_store_en, gen_module_done, gen_batch_done;
    wire [2:0] gen_error;
    
    //==========================================================================
    // 存储模块连线
    //==========================================================================
    wire [3:0] read_out_m, read_out_n, read_out_id;
    wire [199:0] read_out_data;
    wire read_valid, read_done;
    wire [2:0] storage_error;
    
    //==========================================================================
    // 运算模块连线
    //==========================================================================
    wire [2:0] compute_error;
    
    //==========================================================================
    // 操作数加载控制
    //==========================================================================
    reg [3:0] read_idx_reg;
    reg read_en_reg;
    reg [3:0] op1_m, op1_n, op2_m, op2_n;
    reg [199:0] op1_data, op2_data;
    reg op1_valid, op2_valid;
    reg [2:0] load_state;
    
    localparam LOAD_IDLE = 3'd0;
    localparam LOAD_OP1 = 3'd1;
    localparam LOAD_WAIT1 = 3'd2;
    localparam LOAD_OP2 = 3'd3;
    localparam LOAD_WAIT2 = 3'd4;
    localparam LOAD_DONE = 3'd5;

    //==========================================================================
    // 周期计数器（用于卷积bonus）
    //==========================================================================
    reg [31:0] cycle_counter;
    reg counting;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 32'd0;
            counting <= 1'b0;
        end
        else begin
            if (current_mode == S_OP_EXEC && !op_done) begin
                if (!counting) begin
                    cycle_counter <= 32'd0;
                    counting <= 1'b1;
                end
                else begin
                    cycle_counter <= cycle_counter + 32'd1;
                end
            end
            else begin
                counting <= 1'b0;
            end
        end
    end
    
    assign cycle_cnt = cycle_counter;

    //==========================================================================
    // 信号合并
    //==========================================================================
    assign input_done = input_module_done | gen_batch_done;
    assign error_type = (input_error != 3'd0) ? input_error :
                        (gen_error != 3'd0) ? gen_error :
                        (storage_error != 3'd0) ? storage_error : compute_error;

    //==========================================================================
    // 输入模块实例化
    //==========================================================================
    matrix_input u_input (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_data(uart_rx_data),
        .rx_done(rx_done),
        .current_mode(current_mode),
        .val_min(val_min),
        .val_max(val_max),
        .mat_m(input_mat_m),
        .mat_n(input_mat_n),
        .mat_data_flat(input_mat_data),
        .store_en(input_store_en),
        .input_done(input_module_done),
        .error_type(input_error)
    );
    
    //==========================================================================
    // 生成模块实例化
    //==========================================================================
    matrix_generate u_generate (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_data(uart_rx_data),
        .rx_done(rx_done),
        .current_mode(current_mode),
        .max_mat_num(max_mat_num),
        .val_min(val_min),
        .val_max(val_max),
        .mat_m(gen_mat_m),
        .mat_n(gen_mat_n),
        .mat_data_flat(gen_mat_data),
        .mat_count(gen_mat_count),
        .store_en(gen_store_en),
        .gen_batch_done(gen_batch_done),
        .input_done(gen_module_done),
        .error_type(gen_error)
    );
    
    //==========================================================================
    // 存储模块实例化
    //==========================================================================
    matrix_storage u_storage (
        .clk(clk),
        .rst_n(rst_n),
        .max_mat_num(max_mat_num),
        .input_mat_m(input_mat_m),
        .input_mat_n(input_mat_n),
        .input_mat_data(input_mat_data),
        .input_store_en(input_store_en),
        .gen_mat_m(gen_mat_m),
        .gen_mat_n(gen_mat_n),
        .gen_mat_data(gen_mat_data),
        .gen_store_en(gen_store_en),
        .read_idx(read_idx_reg),
        .read_en(read_en_reg),
        .stored_mat_m_flat(stored_mat_m_flat),
        .stored_mat_n_flat(stored_mat_n_flat),
        .stored_mat_id_flat(stored_mat_id_flat),
        .stored_mat_flat(stored_mat_flat),
        .total_mat_count(total_mat_count),
        .read_out_m(read_out_m),
        .read_out_n(read_out_n),
        .read_out_data(read_out_data),
        .read_out_id(read_out_id),
        .read_valid(read_valid),
        .read_done(read_done),
        .spec_count_flat(spec_count_flat),
        .error_type(storage_error)
    );
    
    //==========================================================================
    // op_start边沿检测（用于加载操作数）
    //==========================================================================
    reg op_start_d;
    wire op_start_pulse;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            op_start_d <= 1'b0;
        else
            op_start_d <= op_start;
    end
    
    assign op_start_pulse = op_start & (~op_start_d);
    
    //==========================================================================
    // 运算数加载状态机
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_state <= LOAD_IDLE;
            read_en_reg <= 1'b0;
            read_idx_reg <= 4'd0;
            op1_valid <= 1'b0;
            op2_valid <= 1'b0;
            op1_m <= 4'd0;
            op1_n <= 4'd0;
            op1_data <= 200'd0;
            op2_m <= 4'd0;
            op2_n <= 4'd0;
            op2_data <= 200'd0;
        end
        else begin
            read_en_reg <= 1'b0;  // 默认不读取
            
            case (load_state)
                LOAD_IDLE: begin
                    if (current_mode == S_OP_PARAM && op_start_pulse) begin
                        load_state <= LOAD_OP1;
                        op1_valid <= 1'b0;
                        op2_valid <= 1'b0;
                    end
                end
                
                LOAD_OP1: begin
                    read_idx_reg <= operand_id1;
                    read_en_reg <= 1'b1;
                    load_state <= LOAD_WAIT1;
                end
                
                LOAD_WAIT1: begin
                    if (read_done) begin
                        op1_m <= read_out_m;
                        op1_n <= read_out_n;
                        op1_data <= read_out_data;
                        op1_valid <= read_valid;
                        
                        // 判断是否需要第二个操作数
                        // 加法和矩阵乘法需要两个操作数
                        if (current_op == 3'b001 || current_op == 3'b011)
                            load_state <= LOAD_OP2;
                        else
                            load_state <= LOAD_DONE;
                    end
                end
                
                LOAD_OP2: begin
                    read_idx_reg <= operand_id2;
                    read_en_reg <= 1'b1;
                    load_state <= LOAD_WAIT2;
                end
                
                LOAD_WAIT2: begin
                    if (read_done) begin
                        op2_m <= read_out_m;
                        op2_n <= read_out_n;
                        op2_data <= read_out_data;
                        op2_valid <= read_valid;
                        load_state <= LOAD_DONE;
                    end
                end
                
                LOAD_DONE: begin
                    // 等待状态切换后返回空闲
                    if (current_mode != S_OP_PARAM && current_mode != S_OP_EXEC)
                        load_state <= LOAD_IDLE;
                end
                
                default: load_state <= LOAD_IDLE;
            endcase
        end
    end
    
    //==========================================================================
    // 运算模块实例化
    //==========================================================================
    matrix_compute u_compute (
        .clk(clk),
        .rst_n(rst_n),
        .current_mode(current_mode),
        .current_op(current_op),
        .scalar(scalar),
        .operand_sel(operand_sel),
        .op_start(op_start),
        .operand1_m(op1_m),
        .operand1_n(op1_n),
        .operand1_data(op1_data),
        .operand1_valid(op1_valid),
        .operand2_m(op2_m),
        .operand2_n(op2_n),
        .operand2_data(op2_data),
        .operand2_valid(op2_valid),
        .result_m(result_m),
        .result_n(result_n),
        .result_mat_flat(result_mat_flat),
        .op_done(op_done),
        .error_type(compute_error),
        .display_en(display_en),
        .display_type(display_type)
    );

endmodule
