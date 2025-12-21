`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_storage - 完整修复版
//////////////////////////////////////////////////////////////////////////////

module matrix_storage (
    input wire clk,
    input wire rst_n,
    input wire [3:0] max_mat_num,
    input wire [3:0] input_mat_m,
    input wire [3:0] input_mat_n,
    input wire [199:0] input_mat_data,
    input wire input_store_en,
    input wire [3:0] gen_mat_m,
    input wire [3:0] gen_mat_n,
    input wire [199:0] gen_mat_data,
    input wire gen_store_en,
    input wire [3:0] read_idx,
    input wire read_en,
    
    output wire [39:0] stored_mat_m_flat,
    output wire [39:0] stored_mat_n_flat,
    output wire [39:0] stored_mat_id_flat,
    output wire [1999:0] stored_mat_flat,
    output reg [3:0] total_mat_count,
    output reg [3:0] read_out_m,
    output reg [3:0] read_out_n,
    output reg [199:0] read_out_data,
    output reg [3:0] read_out_id,
    output reg read_valid,
    output reg read_done,
    output wire [99:0] spec_count_flat,
    output reg [2:0] error_type
);

    // 存储10个矩阵
    reg [3:0] mat_m_0, mat_m_1, mat_m_2, mat_m_3, mat_m_4;
    reg [3:0] mat_m_5, mat_m_6, mat_m_7, mat_m_8, mat_m_9;
    reg [3:0] mat_n_0, mat_n_1, mat_n_2, mat_n_3, mat_n_4;
    reg [3:0] mat_n_5, mat_n_6, mat_n_7, mat_n_8, mat_n_9;
    reg [3:0] mat_id_0, mat_id_1, mat_id_2, mat_id_3, mat_id_4;
    reg [3:0] mat_id_5, mat_id_6, mat_id_7, mat_id_8, mat_id_9;
    reg [199:0] mat_data_0, mat_data_1, mat_data_2, mat_data_3, mat_data_4;
    reg [199:0] mat_data_5, mat_data_6, mat_data_7, mat_data_8, mat_data_9;
    
    reg [3:0] next_id;

    // 输出展平
    assign stored_mat_m_flat = {mat_m_9, mat_m_8, mat_m_7, mat_m_6, mat_m_5,
                                 mat_m_4, mat_m_3, mat_m_2, mat_m_1, mat_m_0};
    assign stored_mat_n_flat = {mat_n_9, mat_n_8, mat_n_7, mat_n_6, mat_n_5,
                                 mat_n_4, mat_n_3, mat_n_2, mat_n_1, mat_n_0};
    assign stored_mat_id_flat = {mat_id_9, mat_id_8, mat_id_7, mat_id_6, mat_id_5,
                                  mat_id_4, mat_id_3, mat_id_2, mat_id_1, mat_id_0};
    assign stored_mat_flat = {mat_data_9, mat_data_8, mat_data_7, mat_data_6, mat_data_5,
                               mat_data_4, mat_data_3, mat_data_2, mat_data_1, mat_data_0};
    assign spec_count_flat = 100'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_id <= 4'd1;
            total_mat_count <= 4'd0;
            error_type <= 3'd0;
            read_valid <= 1'b0;
            read_done <= 1'b0;
            read_out_m <= 4'd0; read_out_n <= 4'd0; read_out_id <= 4'd0;
            read_out_data <= 200'd0;
            
            mat_m_0 <= 4'd0; mat_m_1 <= 4'd0; mat_m_2 <= 4'd0; mat_m_3 <= 4'd0; mat_m_4 <= 4'd0;
            mat_m_5 <= 4'd0; mat_m_6 <= 4'd0; mat_m_7 <= 4'd0; mat_m_8 <= 4'd0; mat_m_9 <= 4'd0;
            mat_n_0 <= 4'd0; mat_n_1 <= 4'd0; mat_n_2 <= 4'd0; mat_n_3 <= 4'd0; mat_n_4 <= 4'd0;
            mat_n_5 <= 4'd0; mat_n_6 <= 4'd0; mat_n_7 <= 4'd0; mat_n_8 <= 4'd0; mat_n_9 <= 4'd0;
            mat_id_0 <= 4'd0; mat_id_1 <= 4'd0; mat_id_2 <= 4'd0; mat_id_3 <= 4'd0; mat_id_4 <= 4'd0;
            mat_id_5 <= 4'd0; mat_id_6 <= 4'd0; mat_id_7 <= 4'd0; mat_id_8 <= 4'd0; mat_id_9 <= 4'd0;
            mat_data_0 <= 200'd0; mat_data_1 <= 200'd0; mat_data_2 <= 200'd0; mat_data_3 <= 200'd0; mat_data_4 <= 200'd0;
            mat_data_5 <= 200'd0; mat_data_6 <= 200'd0; mat_data_7 <= 200'd0; mat_data_8 <= 200'd0; mat_data_9 <= 200'd0;
        end
        else begin
            read_done <= 1'b0;
            error_type <= 3'd0;
            
            // 存储请求
            if (input_store_en || gen_store_en) begin
                if (total_mat_count < 4'd10) begin
                    case (total_mat_count)
                        4'd0: begin
                            mat_m_0 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_0 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_0 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_0 <= next_id;
                        end
                        4'd1: begin
                            mat_m_1 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_1 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_1 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_1 <= next_id;
                        end
                        4'd2: begin
                            mat_m_2 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_2 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_2 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_2 <= next_id;
                        end
                        4'd3: begin
                            mat_m_3 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_3 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_3 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_3 <= next_id;
                        end
                        4'd4: begin
                            mat_m_4 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_4 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_4 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_4 <= next_id;
                        end
                        4'd5: begin
                            mat_m_5 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_5 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_5 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_5 <= next_id;
                        end
                        4'd6: begin
                            mat_m_6 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_6 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_6 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_6 <= next_id;
                        end
                        4'd7: begin
                            mat_m_7 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_7 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_7 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_7 <= next_id;
                        end
                        4'd8: begin
                            mat_m_8 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_8 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_8 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_8 <= next_id;
                        end
                        4'd9: begin
                            mat_m_9 <= input_store_en ? input_mat_m : gen_mat_m;
                            mat_n_9 <= input_store_en ? input_mat_n : gen_mat_n;
                            mat_data_9 <= input_store_en ? input_mat_data : gen_mat_data;
                            mat_id_9 <= next_id;
                        end
                        default: ;
                    endcase
                    next_id <= next_id + 4'd1;
                    total_mat_count <= total_mat_count + 4'd1;
                end
            end
            
            // 读取请求
            if (read_en) begin
                read_valid <= (read_idx < total_mat_count);
                read_done <= 1'b1;
                
                case (read_idx)
                    4'd0: begin read_out_m <= mat_m_0; read_out_n <= mat_n_0; read_out_data <= mat_data_0; read_out_id <= mat_id_0; end
                    4'd1: begin read_out_m <= mat_m_1; read_out_n <= mat_n_1; read_out_data <= mat_data_1; read_out_id <= mat_id_1; end
                    4'd2: begin read_out_m <= mat_m_2; read_out_n <= mat_n_2; read_out_data <= mat_data_2; read_out_id <= mat_id_2; end
                    4'd3: begin read_out_m <= mat_m_3; read_out_n <= mat_n_3; read_out_data <= mat_data_3; read_out_id <= mat_id_3; end
                    4'd4: begin read_out_m <= mat_m_4; read_out_n <= mat_n_4; read_out_data <= mat_data_4; read_out_id <= mat_id_4; end
                    4'd5: begin read_out_m <= mat_m_5; read_out_n <= mat_n_5; read_out_data <= mat_data_5; read_out_id <= mat_id_5; end
                    4'd6: begin read_out_m <= mat_m_6; read_out_n <= mat_n_6; read_out_data <= mat_data_6; read_out_id <= mat_id_6; end
                    4'd7: begin read_out_m <= mat_m_7; read_out_n <= mat_n_7; read_out_data <= mat_data_7; read_out_id <= mat_id_7; end
                    4'd8: begin read_out_m <= mat_m_8; read_out_n <= mat_n_8; read_out_data <= mat_data_8; read_out_id <= mat_id_8; end
                    4'd9: begin read_out_m <= mat_m_9; read_out_n <= mat_n_9; read_out_data <= mat_data_9; read_out_id <= mat_id_9; end
                    default: begin read_out_m <= 4'd0; read_out_n <= 4'd0; read_out_data <= 200'd0; read_out_id <= 4'd0; end
                endcase
            end
        end
    end

endmodule