`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_storage - 完整版（Vivado 2017兼容）
// 功能：
//   1. 按矩阵规格(m*n)分类存储
//   2. 每种规格最多存储 max_mat_num 个矩阵
//   3. 同规格矩阵超出限制时，覆盖最旧的（轮转覆盖）
//   4. spec_count_flat 输出每种规格的矩阵数量统计
//////////////////////////////////////////////////////////////////////////////

module matrix_storage (
    input wire clk,
    input wire rst_n,
    input wire [3:0] max_mat_num,           // 每种规格最多存储的矩阵数（默认2）
    
    // 输入模块接口
    input wire [3:0] input_mat_m,
    input wire [3:0] input_mat_n,
    input wire [199:0] input_mat_data,
    input wire input_store_en,
    
    // 生成模块接口
    input wire [3:0] gen_mat_m,
    input wire [3:0] gen_mat_n,
    input wire [199:0] gen_mat_data,
    input wire gen_store_en,
    
    // 读取接口
    input wire [3:0] read_idx,
    input wire read_en,
    
    // 输出：所有存储矩阵的展平数据
    output wire [39:0] stored_mat_m_flat,
    output wire [39:0] stored_mat_n_flat,
    output wire [39:0] stored_mat_id_flat,
    output wire [1999:0] stored_mat_flat,
    output reg [3:0] total_mat_count,
    
    // 读取输出
    output reg [3:0] read_out_m,
    output reg [3:0] read_out_n,
    output reg [199:0] read_out_data,
    output reg [3:0] read_out_id,
    output reg read_valid,
    output reg read_done,
    
    // 规格统计：25种规格(1-5 * 1-5)，每种4bit计数
    output wire [99:0] spec_count_flat,
    
    output reg [2:0] error_type
);

    //==========================================================================
    // 存储结构：10个矩阵槽位（使用独立寄存器，Vivado 2017兼容）
    //==========================================================================
    reg [3:0] mat_m_0, mat_m_1, mat_m_2, mat_m_3, mat_m_4;
    reg [3:0] mat_m_5, mat_m_6, mat_m_7, mat_m_8, mat_m_9;
    reg [3:0] mat_n_0, mat_n_1, mat_n_2, mat_n_3, mat_n_4;
    reg [3:0] mat_n_5, mat_n_6, mat_n_7, mat_n_8, mat_n_9;
    reg [3:0] mat_id_0, mat_id_1, mat_id_2, mat_id_3, mat_id_4;
    reg [3:0] mat_id_5, mat_id_6, mat_id_7, mat_id_8, mat_id_9;
    reg [199:0] mat_data_0, mat_data_1, mat_data_2, mat_data_3, mat_data_4;
    reg [199:0] mat_data_5, mat_data_6, mat_data_7, mat_data_8, mat_data_9;
    reg mat_valid_0, mat_valid_1, mat_valid_2, mat_valid_3, mat_valid_4;
    reg mat_valid_5, mat_valid_6, mat_valid_7, mat_valid_8, mat_valid_9;
    
    reg [3:0] next_id;
    
    //==========================================================================
    // 每种规格(m,n)的计数器
    // 规格索引 = (m-1)*5 + (n-1)，范围0-24
    //==========================================================================
    reg [3:0] spec_count_0,  spec_count_1,  spec_count_2,  spec_count_3,  spec_count_4;
    reg [3:0] spec_count_5,  spec_count_6,  spec_count_7,  spec_count_8,  spec_count_9;
    reg [3:0] spec_count_10, spec_count_11, spec_count_12, spec_count_13, spec_count_14;
    reg [3:0] spec_count_15, spec_count_16, spec_count_17, spec_count_18, spec_count_19;
    reg [3:0] spec_count_20, spec_count_21, spec_count_22, spec_count_23, spec_count_24;
    
    //==========================================================================
    // 输出展平（兼容原接口）
    //==========================================================================
    assign stored_mat_m_flat = {mat_m_9, mat_m_8, mat_m_7, mat_m_6, mat_m_5,
                                mat_m_4, mat_m_3, mat_m_2, mat_m_1, mat_m_0};
    assign stored_mat_n_flat = {mat_n_9, mat_n_8, mat_n_7, mat_n_6, mat_n_5,
                                mat_n_4, mat_n_3, mat_n_2, mat_n_1, mat_n_0};
    assign stored_mat_id_flat = {mat_id_9, mat_id_8, mat_id_7, mat_id_6, mat_id_5,
                                 mat_id_4, mat_id_3, mat_id_2, mat_id_1, mat_id_0};
    assign stored_mat_flat = {mat_data_9, mat_data_8, mat_data_7, mat_data_6, mat_data_5,
                              mat_data_4, mat_data_3, mat_data_2, mat_data_1, mat_data_0};
    
    // 规格计数展平输出
    assign spec_count_flat = {spec_count_24, spec_count_23, spec_count_22, spec_count_21, spec_count_20,
                              spec_count_19, spec_count_18, spec_count_17, spec_count_16, spec_count_15,
                              spec_count_14, spec_count_13, spec_count_12, spec_count_11, spec_count_10,
                              spec_count_9,  spec_count_8,  spec_count_7,  spec_count_6,  spec_count_5,
                              spec_count_4,  spec_count_3,  spec_count_2,  spec_count_1,  spec_count_0};
    
    //==========================================================================
    // 内部信号
    //==========================================================================
    wire store_en;
    wire [3:0] store_m, store_n;
    wire [199:0] store_data;
    wire [4:0] spec_idx;                    // 规格索引 = (m-1)*5 + (n-1)
    
    assign store_en = input_store_en | gen_store_en;
    assign store_m = input_store_en ? input_mat_m : gen_mat_m;
    assign store_n = input_store_en ? input_mat_n : gen_mat_n;
    assign store_data = input_store_en ? input_mat_data : gen_mat_data;
    assign spec_idx = (store_m - 1) * 5 + (store_n - 1);
    
    //==========================================================================
    // 查找同规格矩阵的数量和最旧槽位
    //==========================================================================
    reg [3:0] match_count;
    reg [3:0] oldest_slot;
    reg [3:0] oldest_id;
    reg [3:0] empty_slot;
    reg found_empty;
    reg [3:0] target_slot;
    reg need_overwrite;
    reg [4:0] old_spec_idx;                 // 被覆盖槽位的原规格索引
    
    // 临时变量用于遍历
    wire match_0, match_1, match_2, match_3, match_4;
    wire match_5, match_6, match_7, match_8, match_9;
    
    assign match_0 = mat_valid_0 && (mat_m_0 == store_m) && (mat_n_0 == store_n);
    assign match_1 = mat_valid_1 && (mat_m_1 == store_m) && (mat_n_1 == store_n);
    assign match_2 = mat_valid_2 && (mat_m_2 == store_m) && (mat_n_2 == store_n);
    assign match_3 = mat_valid_3 && (mat_m_3 == store_m) && (mat_n_3 == store_n);
    assign match_4 = mat_valid_4 && (mat_m_4 == store_m) && (mat_n_4 == store_n);
    assign match_5 = mat_valid_5 && (mat_m_5 == store_m) && (mat_n_5 == store_n);
    assign match_6 = mat_valid_6 && (mat_m_6 == store_m) && (mat_n_6 == store_n);
    assign match_7 = mat_valid_7 && (mat_m_7 == store_m) && (mat_n_7 == store_n);
    assign match_8 = mat_valid_8 && (mat_m_8 == store_m) && (mat_n_8 == store_n);
    assign match_9 = mat_valid_9 && (mat_m_9 == store_m) && (mat_n_9 == store_n);
    
    // 组合逻辑：查找目标槽位
    always @(*) begin
        // 计算匹配数量
        match_count = {3'd0, match_0} + {3'd0, match_1} + {3'd0, match_2} + 
                      {3'd0, match_3} + {3'd0, match_4} + {3'd0, match_5} + 
                      {3'd0, match_6} + {3'd0, match_7} + {3'd0, match_8} + {3'd0, match_9};
        
        // 查找空槽位（优先选择索引小的）
        found_empty = 1'b0;
        empty_slot = 4'd0;
        if (!mat_valid_0) begin found_empty = 1'b1; empty_slot = 4'd0; end
        else if (!mat_valid_1) begin found_empty = 1'b1; empty_slot = 4'd1; end
        else if (!mat_valid_2) begin found_empty = 1'b1; empty_slot = 4'd2; end
        else if (!mat_valid_3) begin found_empty = 1'b1; empty_slot = 4'd3; end
        else if (!mat_valid_4) begin found_empty = 1'b1; empty_slot = 4'd4; end
        else if (!mat_valid_5) begin found_empty = 1'b1; empty_slot = 4'd5; end
        else if (!mat_valid_6) begin found_empty = 1'b1; empty_slot = 4'd6; end
        else if (!mat_valid_7) begin found_empty = 1'b1; empty_slot = 4'd7; end
        else if (!mat_valid_8) begin found_empty = 1'b1; empty_slot = 4'd8; end
        else if (!mat_valid_9) begin found_empty = 1'b1; empty_slot = 4'd9; end
        
        // 查找同规格中ID最小（最旧）的槽位
        oldest_slot = 4'd0;
        oldest_id = 4'd15;
        
        if (match_0 && mat_id_0 < oldest_id) begin oldest_id = mat_id_0; oldest_slot = 4'd0; end
        if (match_1 && mat_id_1 < oldest_id) begin oldest_id = mat_id_1; oldest_slot = 4'd1; end
        if (match_2 && mat_id_2 < oldest_id) begin oldest_id = mat_id_2; oldest_slot = 4'd2; end
        if (match_3 && mat_id_3 < oldest_id) begin oldest_id = mat_id_3; oldest_slot = 4'd3; end
        if (match_4 && mat_id_4 < oldest_id) begin oldest_id = mat_id_4; oldest_slot = 4'd4; end
        if (match_5 && mat_id_5 < oldest_id) begin oldest_id = mat_id_5; oldest_slot = 4'd5; end
        if (match_6 && mat_id_6 < oldest_id) begin oldest_id = mat_id_6; oldest_slot = 4'd6; end
        if (match_7 && mat_id_7 < oldest_id) begin oldest_id = mat_id_7; oldest_slot = 4'd7; end
        if (match_8 && mat_id_8 < oldest_id) begin oldest_id = mat_id_8; oldest_slot = 4'd8; end
        if (match_9 && mat_id_9 < oldest_id) begin oldest_id = mat_id_9; oldest_slot = 4'd9; end
        
        // 决定目标槽位
        if (match_count >= max_mat_num && match_count > 4'd0) begin
            // 同规格已达上限，需要覆盖最旧的同规格矩阵
            need_overwrite = 1'b1;
            target_slot = oldest_slot;
        end
        else if (found_empty) begin
            // 有空槽位，使用空槽位（新增）
            need_overwrite = 1'b0;
            target_slot = empty_slot;
        end
        else if (match_count > 4'd0) begin
            // 没有空槽位，但该规格有矩阵（即使未达上限）
            // 优先覆盖同规格最旧的矩阵
            need_overwrite = 1'b1;
            target_slot = oldest_slot;
        end
        else begin
            // 没有空槽位，且该规格没有任何矩阵
            // 需要覆盖其他规格的矩阵来腾出空间（全局最旧）
            need_overwrite = 1'b0;  // 这是新增操作（会增加spec_count）
            target_slot = 4'd0;
            oldest_id = 4'd15;
            
            // 找全局最旧的槽位
            if (mat_valid_0 && mat_id_0 < oldest_id) begin oldest_id = mat_id_0; target_slot = 4'd0; end
            if (mat_valid_1 && mat_id_1 < oldest_id) begin oldest_id = mat_id_1; target_slot = 4'd1; end
            if (mat_valid_2 && mat_id_2 < oldest_id) begin oldest_id = mat_id_2; target_slot = 4'd2; end
            if (mat_valid_3 && mat_id_3 < oldest_id) begin oldest_id = mat_id_3; target_slot = 4'd3; end
            if (mat_valid_4 && mat_id_4 < oldest_id) begin oldest_id = mat_id_4; target_slot = 4'd4; end
            if (mat_valid_5 && mat_id_5 < oldest_id) begin oldest_id = mat_id_5; target_slot = 4'd5; end
            if (mat_valid_6 && mat_id_6 < oldest_id) begin oldest_id = mat_id_6; target_slot = 4'd6; end
            if (mat_valid_7 && mat_id_7 < oldest_id) begin oldest_id = mat_id_7; target_slot = 4'd7; end
            if (mat_valid_8 && mat_id_8 < oldest_id) begin oldest_id = mat_id_8; target_slot = 4'd8; end
            if (mat_valid_9 && mat_id_9 < oldest_id) begin oldest_id = mat_id_9; target_slot = 4'd9; end
        end
        
        // 计算被覆盖槽位的原规格索引
        case (target_slot)
            4'd0: old_spec_idx = (mat_m_0 - 1) * 5 + (mat_n_0 - 1);
            4'd1: old_spec_idx = (mat_m_1 - 1) * 5 + (mat_n_1 - 1);
            4'd2: old_spec_idx = (mat_m_2 - 1) * 5 + (mat_n_2 - 1);
            4'd3: old_spec_idx = (mat_m_3 - 1) * 5 + (mat_n_3 - 1);
            4'd4: old_spec_idx = (mat_m_4 - 1) * 5 + (mat_n_4 - 1);
            4'd5: old_spec_idx = (mat_m_5 - 1) * 5 + (mat_n_5 - 1);
            4'd6: old_spec_idx = (mat_m_6 - 1) * 5 + (mat_n_6 - 1);
            4'd7: old_spec_idx = (mat_m_7 - 1) * 5 + (mat_n_7 - 1);
            4'd8: old_spec_idx = (mat_m_8 - 1) * 5 + (mat_n_8 - 1);
            4'd9: old_spec_idx = (mat_m_9 - 1) * 5 + (mat_n_9 - 1);
            default: old_spec_idx = 5'd0;
        endcase
    end
    
    //==========================================================================
    // 主存储逻辑
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位所有存储
            next_id <= 4'd1;
            total_mat_count <= 4'd0;
            error_type <= 3'd0;
            read_valid <= 1'b0;
            read_done <= 1'b0;
            read_out_m <= 4'd0;
            read_out_n <= 4'd0;
            read_out_id <= 4'd0;
            read_out_data <= 200'd0;
            
            // 矩阵槽位复位
            mat_m_0 <= 4'd0; mat_m_1 <= 4'd0; mat_m_2 <= 4'd0; mat_m_3 <= 4'd0; mat_m_4 <= 4'd0;
            mat_m_5 <= 4'd0; mat_m_6 <= 4'd0; mat_m_7 <= 4'd0; mat_m_8 <= 4'd0; mat_m_9 <= 4'd0;
            mat_n_0 <= 4'd0; mat_n_1 <= 4'd0; mat_n_2 <= 4'd0; mat_n_3 <= 4'd0; mat_n_4 <= 4'd0;
            mat_n_5 <= 4'd0; mat_n_6 <= 4'd0; mat_n_7 <= 4'd0; mat_n_8 <= 4'd0; mat_n_9 <= 4'd0;
            mat_id_0 <= 4'd0; mat_id_1 <= 4'd0; mat_id_2 <= 4'd0; mat_id_3 <= 4'd0; mat_id_4 <= 4'd0;
            mat_id_5 <= 4'd0; mat_id_6 <= 4'd0; mat_id_7 <= 4'd0; mat_id_8 <= 4'd0; mat_id_9 <= 4'd0;
            mat_data_0 <= 200'd0; mat_data_1 <= 200'd0; mat_data_2 <= 200'd0;
            mat_data_3 <= 200'd0; mat_data_4 <= 200'd0; mat_data_5 <= 200'd0;
            mat_data_6 <= 200'd0; mat_data_7 <= 200'd0; mat_data_8 <= 200'd0; mat_data_9 <= 200'd0;
            mat_valid_0 <= 1'b0; mat_valid_1 <= 1'b0; mat_valid_2 <= 1'b0;
            mat_valid_3 <= 1'b0; mat_valid_4 <= 1'b0; mat_valid_5 <= 1'b0;
            mat_valid_6 <= 1'b0; mat_valid_7 <= 1'b0; mat_valid_8 <= 1'b0; mat_valid_9 <= 1'b0;
            
            // 规格计数复位
            spec_count_0  <= 4'd0; spec_count_1  <= 4'd0; spec_count_2  <= 4'd0;
            spec_count_3  <= 4'd0; spec_count_4  <= 4'd0; spec_count_5  <= 4'd0;
            spec_count_6  <= 4'd0; spec_count_7  <= 4'd0; spec_count_8  <= 4'd0;
            spec_count_9  <= 4'd0; spec_count_10 <= 4'd0; spec_count_11 <= 4'd0;
            spec_count_12 <= 4'd0; spec_count_13 <= 4'd0; spec_count_14 <= 4'd0;
            spec_count_15 <= 4'd0; spec_count_16 <= 4'd0; spec_count_17 <= 4'd0;
            spec_count_18 <= 4'd0; spec_count_19 <= 4'd0; spec_count_20 <= 4'd0;
            spec_count_21 <= 4'd0; spec_count_22 <= 4'd0; spec_count_23 <= 4'd0;
            spec_count_24 <= 4'd0;
        end
        else begin
            read_done <= 1'b0;
            error_type <= 3'd0;
            
            //==================================================================
            // 存储请求处理
            //==================================================================
            if (store_en) begin
                // 写入目标槽位
                case (target_slot)
                    4'd0: begin
                        mat_m_0 <= store_m; mat_n_0 <= store_n;
                        mat_data_0 <= store_data; mat_id_0 <= next_id;
                        mat_valid_0 <= 1'b1;
                    end
                    4'd1: begin
                        mat_m_1 <= store_m; mat_n_1 <= store_n;
                        mat_data_1 <= store_data; mat_id_1 <= next_id;
                        mat_valid_1 <= 1'b1;
                    end
                    4'd2: begin
                        mat_m_2 <= store_m; mat_n_2 <= store_n;
                        mat_data_2 <= store_data; mat_id_2 <= next_id;
                        mat_valid_2 <= 1'b1;
                    end
                    4'd3: begin
                        mat_m_3 <= store_m; mat_n_3 <= store_n;
                        mat_data_3 <= store_data; mat_id_3 <= next_id;
                        mat_valid_3 <= 1'b1;
                    end
                    4'd4: begin
                        mat_m_4 <= store_m; mat_n_4 <= store_n;
                        mat_data_4 <= store_data; mat_id_4 <= next_id;
                        mat_valid_4 <= 1'b1;
                    end
                    4'd5: begin
                        mat_m_5 <= store_m; mat_n_5 <= store_n;
                        mat_data_5 <= store_data; mat_id_5 <= next_id;
                        mat_valid_5 <= 1'b1;
                    end
                    4'd6: begin
                        mat_m_6 <= store_m; mat_n_6 <= store_n;
                        mat_data_6 <= store_data; mat_id_6 <= next_id;
                        mat_valid_6 <= 1'b1;
                    end
                    4'd7: begin
                        mat_m_7 <= store_m; mat_n_7 <= store_n;
                        mat_data_7 <= store_data; mat_id_7 <= next_id;
                        mat_valid_7 <= 1'b1;
                    end
                    4'd8: begin
                        mat_m_8 <= store_m; mat_n_8 <= store_n;
                        mat_data_8 <= store_data; mat_id_8 <= next_id;
                        mat_valid_8 <= 1'b1;
                    end
                    4'd9: begin
                        mat_m_9 <= store_m; mat_n_9 <= store_n;
                        mat_data_9 <= store_data; mat_id_9 <= next_id;
                        mat_valid_9 <= 1'b1;
                    end
                    default: ;
                endcase
                
                // 更新ID
                next_id <= next_id + 4'd1;
                
                // 更新总数和规格计数
                if (!need_overwrite && found_empty) begin
                    // 情况1：使用空槽位新增，总数+1，新规格计数+1
                    total_mat_count <= total_mat_count + 4'd1;
                    
                    case (spec_idx)
                        5'd0:  spec_count_0  <= spec_count_0  + 4'd1;
                        5'd1:  spec_count_1  <= spec_count_1  + 4'd1;
                        5'd2:  spec_count_2  <= spec_count_2  + 4'd1;
                        5'd3:  spec_count_3  <= spec_count_3  + 4'd1;
                        5'd4:  spec_count_4  <= spec_count_4  + 4'd1;
                        5'd5:  spec_count_5  <= spec_count_5  + 4'd1;
                        5'd6:  spec_count_6  <= spec_count_6  + 4'd1;
                        5'd7:  spec_count_7  <= spec_count_7  + 4'd1;
                        5'd8:  spec_count_8  <= spec_count_8  + 4'd1;
                        5'd9:  spec_count_9  <= spec_count_9  + 4'd1;
                        5'd10: spec_count_10 <= spec_count_10 + 4'd1;
                        5'd11: spec_count_11 <= spec_count_11 + 4'd1;
                        5'd12: spec_count_12 <= spec_count_12 + 4'd1;
                        5'd13: spec_count_13 <= spec_count_13 + 4'd1;
                        5'd14: spec_count_14 <= spec_count_14 + 4'd1;
                        5'd15: spec_count_15 <= spec_count_15 + 4'd1;
                        5'd16: spec_count_16 <= spec_count_16 + 4'd1;
                        5'd17: spec_count_17 <= spec_count_17 + 4'd1;
                        5'd18: spec_count_18 <= spec_count_18 + 4'd1;
                        5'd19: spec_count_19 <= spec_count_19 + 4'd1;
                        5'd20: spec_count_20 <= spec_count_20 + 4'd1;
                        5'd21: spec_count_21 <= spec_count_21 + 4'd1;
                        5'd22: spec_count_22 <= spec_count_22 + 4'd1;
                        5'd23: spec_count_23 <= spec_count_23 + 4'd1;
                        5'd24: spec_count_24 <= spec_count_24 + 4'd1;
                        default: ;
                    endcase
                end
                else if (!need_overwrite && !found_empty) begin
                    // 情况2：覆盖其他规格（need_overwrite=0但没有空槽位）
                    // 总数不变，新规格计数+1，被覆盖规格计数-1
                    
                    // 新规格计数+1
                    case (spec_idx)
                        5'd0:  spec_count_0  <= spec_count_0  + 4'd1;
                        5'd1:  spec_count_1  <= spec_count_1  + 4'd1;
                        5'd2:  spec_count_2  <= spec_count_2  + 4'd1;
                        5'd3:  spec_count_3  <= spec_count_3  + 4'd1;
                        5'd4:  spec_count_4  <= spec_count_4  + 4'd1;
                        5'd5:  spec_count_5  <= spec_count_5  + 4'd1;
                        5'd6:  spec_count_6  <= spec_count_6  + 4'd1;
                        5'd7:  spec_count_7  <= spec_count_7  + 4'd1;
                        5'd8:  spec_count_8  <= spec_count_8  + 4'd1;
                        5'd9:  spec_count_9  <= spec_count_9  + 4'd1;
                        5'd10: spec_count_10 <= spec_count_10 + 4'd1;
                        5'd11: spec_count_11 <= spec_count_11 + 4'd1;
                        5'd12: spec_count_12 <= spec_count_12 + 4'd1;
                        5'd13: spec_count_13 <= spec_count_13 + 4'd1;
                        5'd14: spec_count_14 <= spec_count_14 + 4'd1;
                        5'd15: spec_count_15 <= spec_count_15 + 4'd1;
                        5'd16: spec_count_16 <= spec_count_16 + 4'd1;
                        5'd17: spec_count_17 <= spec_count_17 + 4'd1;
                        5'd18: spec_count_18 <= spec_count_18 + 4'd1;
                        5'd19: spec_count_19 <= spec_count_19 + 4'd1;
                        5'd20: spec_count_20 <= spec_count_20 + 4'd1;
                        5'd21: spec_count_21 <= spec_count_21 + 4'd1;
                        5'd22: spec_count_22 <= spec_count_22 + 4'd1;
                        5'd23: spec_count_23 <= spec_count_23 + 4'd1;
                        5'd24: spec_count_24 <= spec_count_24 + 4'd1;
                        default: ;
                    endcase
                    
                    // 被覆盖规格计数-1
                    case (old_spec_idx)
                        5'd0:  spec_count_0  <= spec_count_0  - 4'd1;
                        5'd1:  spec_count_1  <= spec_count_1  - 4'd1;
                        5'd2:  spec_count_2  <= spec_count_2  - 4'd1;
                        5'd3:  spec_count_3  <= spec_count_3  - 4'd1;
                        5'd4:  spec_count_4  <= spec_count_4  - 4'd1;
                        5'd5:  spec_count_5  <= spec_count_5  - 4'd1;
                        5'd6:  spec_count_6  <= spec_count_6  - 4'd1;
                        5'd7:  spec_count_7  <= spec_count_7  - 4'd1;
                        5'd8:  spec_count_8  <= spec_count_8  - 4'd1;
                        5'd9:  spec_count_9  <= spec_count_9  - 4'd1;
                        5'd10: spec_count_10 <= spec_count_10 - 4'd1;
                        5'd11: spec_count_11 <= spec_count_11 - 4'd1;
                        5'd12: spec_count_12 <= spec_count_12 - 4'd1;
                        5'd13: spec_count_13 <= spec_count_13 - 4'd1;
                        5'd14: spec_count_14 <= spec_count_14 - 4'd1;
                        5'd15: spec_count_15 <= spec_count_15 - 4'd1;
                        5'd16: spec_count_16 <= spec_count_16 - 4'd1;
                        5'd17: spec_count_17 <= spec_count_17 - 4'd1;
                        5'd18: spec_count_18 <= spec_count_18 - 4'd1;
                        5'd19: spec_count_19 <= spec_count_19 - 4'd1;
                        5'd20: spec_count_20 <= spec_count_20 - 4'd1;
                        5'd21: spec_count_21 <= spec_count_21 - 4'd1;
                        5'd22: spec_count_22 <= spec_count_22 - 4'd1;
                        5'd23: spec_count_23 <= spec_count_23 - 4'd1;
                        5'd24: spec_count_24 <= spec_count_24 - 4'd1;
                        default: ;
                    endcase
                end
                // 情况3：覆盖同规格（need_overwrite=1），不改变任何计数
            end
            
            //==================================================================
            // 读取请求处理
            //==================================================================
            if (read_en) begin
                read_done <= 1'b1;
                
                case (read_idx)
                    4'd0: begin
                        read_out_m <= mat_m_0; read_out_n <= mat_n_0;
                        read_out_data <= mat_data_0; read_out_id <= mat_id_0;
                        read_valid <= mat_valid_0;
                    end
                    4'd1: begin
                        read_out_m <= mat_m_1; read_out_n <= mat_n_1;
                        read_out_data <= mat_data_1; read_out_id <= mat_id_1;
                        read_valid <= mat_valid_1;
                    end
                    4'd2: begin
                        read_out_m <= mat_m_2; read_out_n <= mat_n_2;
                        read_out_data <= mat_data_2; read_out_id <= mat_id_2;
                        read_valid <= mat_valid_2;
                    end
                    4'd3: begin
                        read_out_m <= mat_m_3; read_out_n <= mat_n_3;
                        read_out_data <= mat_data_3; read_out_id <= mat_id_3;
                        read_valid <= mat_valid_3;
                    end
                    4'd4: begin
                        read_out_m <= mat_m_4; read_out_n <= mat_n_4;
                        read_out_data <= mat_data_4; read_out_id <= mat_id_4;
                        read_valid <= mat_valid_4;
                    end
                    4'd5: begin
                        read_out_m <= mat_m_5; read_out_n <= mat_n_5;
                        read_out_data <= mat_data_5; read_out_id <= mat_id_5;
                        read_valid <= mat_valid_5;
                    end
                    4'd6: begin
                        read_out_m <= mat_m_6; read_out_n <= mat_n_6;
                        read_out_data <= mat_data_6; read_out_id <= mat_id_6;
                        read_valid <= mat_valid_6;
                    end
                    4'd7: begin
                        read_out_m <= mat_m_7; read_out_n <= mat_n_7;
                        read_out_data <= mat_data_7; read_out_id <= mat_id_7;
                        read_valid <= mat_valid_7;
                    end
                    4'd8: begin
                        read_out_m <= mat_m_8; read_out_n <= mat_n_8;
                        read_out_data <= mat_data_8; read_out_id <= mat_id_8;
                        read_valid <= mat_valid_8;
                    end
                    4'd9: begin
                        read_out_m <= mat_m_9; read_out_n <= mat_n_9;
                        read_out_data <= mat_data_9; read_out_id <= mat_id_9;
                        read_valid <= mat_valid_9;
                    end
                    default: begin
                        read_out_m <= 4'd0; read_out_n <= 4'd0;
                        read_out_data <= 200'd0; read_out_id <= 4'd0;
                        read_valid <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule