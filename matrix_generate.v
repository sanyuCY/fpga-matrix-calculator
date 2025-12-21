`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Module: matrix_generate - ÕÍ’˚–ﬁ∏¥∞Ê
//////////////////////////////////////////////////////////////////////////////

module matrix_generate (
    input wire clk,
    input wire rst_n,
    input wire [7:0] uart_rx_data,
    input wire rx_done,
    input wire [3:0] current_mode,
    input wire [3:0] max_mat_num,
    input wire [7:0] val_min,
    input wire [7:0] val_max,
    output reg [3:0] mat_m,
    output reg [3:0] mat_n,
    output reg [199:0] mat_data_flat,
    output reg [3:0] mat_count,
    output reg store_en,
    output reg gen_batch_done,
    output reg input_done,
    output reg [2:0] error_type
);

    localparam S_GEN = 4'b0010;
    localparam GEN_IDLE = 3'd0, GEN_WAIT_M = 3'd1, GEN_WAIT_N = 3'd2;
    localparam GEN_WAIT_CNT = 3'd3, GEN_GENERATE = 3'd4;
    localparam GEN_STORE = 3'd5, GEN_NEXT = 3'd6, GEN_DONE = 3'd7;
    localparam ERR_NONE = 3'b000, ERR_DIM = 3'b001;

    reg [2:0] state;
    reg [3:0] temp_m, temp_n;
    reg [3:0] gen_count, target_count;
    reg [4:0] elem_idx;
    reg [4:0] total_elem;
    reg [15:0] lfsr;
    reg just_finished;
    
    // ±ﬂ—ÿºÏ≤‚
    reg rx_done_d;
    wire rx_done_pulse;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_done_d <= 1'b0;
        else
            rx_done_d <= rx_done;
    end
    
    assign rx_done_pulse = rx_done & (~rx_done_d);

    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    wire [7:0] range = (val_max >= val_min) ? (val_max - val_min + 1) : 8'd10;
    wire [7:0] rand_val = val_min + (lfsr[7:0] % range);
    wire [3:0] rx_digit = uart_rx_data[3:0];
    wire is_digit = (uart_rx_data >= 8'h30) && (uart_rx_data <= 8'h39);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= GEN_IDLE;
            lfsr <= 16'hACE1;
            mat_m <= 4'd0; mat_n <= 4'd0;
            mat_data_flat <= 200'd0;
            temp_m <= 4'd0; temp_n <= 4'd0;
            mat_count <= 4'd0; gen_count <= 4'd0; target_count <= 4'd0;
            elem_idx <= 5'd0; total_elem <= 5'd0;
            store_en <= 1'b0; input_done <= 1'b0; gen_batch_done <= 1'b0;
            error_type <= ERR_NONE;
            just_finished <= 1'b0;
        end
        else begin
            lfsr <= {lfsr[14:0], lfsr_fb};
            store_en <= 1'b0;
            input_done <= 1'b0;
            gen_batch_done <= 1'b0;
            
            if (current_mode != S_GEN) begin
                just_finished <= 1'b0;
            end
            
            case (state)
                GEN_IDLE: begin
                    if (current_mode == S_GEN && !just_finished) begin
                        state <= GEN_WAIT_M;
                        gen_count <= 4'd0;
                        error_type <= ERR_NONE;
                    end
                end
                
                GEN_WAIT_M: begin
                    if (current_mode != S_GEN) state <= GEN_IDLE;
                    else if (rx_done_pulse && is_digit) begin
                        if (rx_digit < 4'd1 || rx_digit > 4'd5) begin
                            error_type <= ERR_DIM;
                            state <= GEN_IDLE;
                        end
                        else begin
                            temp_m <= rx_digit;
                            state <= GEN_WAIT_N;
                        end
                    end
                end
                
                GEN_WAIT_N: begin
                    if (current_mode != S_GEN) state <= GEN_IDLE;
                    else if (rx_done_pulse && is_digit) begin
                        if (rx_digit < 4'd1 || rx_digit > 4'd5) begin
                            error_type <= ERR_DIM;
                            state <= GEN_IDLE;
                        end
                        else begin
                            temp_n <= rx_digit;
                            state <= GEN_WAIT_CNT;
                        end
                    end
                end
                
                GEN_WAIT_CNT: begin
                    if (current_mode != S_GEN) state <= GEN_IDLE;
                    else if (rx_done_pulse && is_digit) begin
                        target_count <= (rx_digit > max_mat_num) ? max_mat_num :
                                       (rx_digit == 4'd0) ? 4'd1 : rx_digit;
                        mat_m <= temp_m;
                        mat_n <= temp_n;
                        mat_count <= rx_digit;
                        total_elem <= temp_m * temp_n;
                        elem_idx <= 5'd0;
                        mat_data_flat <= 200'd0;
                        state <= GEN_GENERATE;
                    end
                end
                
                GEN_GENERATE: begin
                    if (current_mode != S_GEN) state <= GEN_IDLE;
                    else begin
                        mat_data_flat[elem_idx*8 +: 8] <= rand_val;
                        
                        if (elem_idx >= total_elem - 1) begin
                            state <= GEN_STORE;
                        end
                        else begin
                            elem_idx <= elem_idx + 5'd1;
                        end
                    end
                end
                
                GEN_STORE: begin
                    store_en <= 1'b1;
                    input_done <= 1'b1;
                    gen_count <= gen_count + 4'd1;
                    state <= GEN_NEXT;
                end
                
                GEN_NEXT: begin
                    if (gen_count >= target_count) state <= GEN_DONE;
                    else begin
                        elem_idx <= 5'd0;
                        mat_data_flat <= 200'd0;
                        state <= GEN_GENERATE;
                    end
                end
                
                GEN_DONE: begin
                    gen_batch_done <= 1'b1;
                    just_finished <= 1'b1;
                    state <= GEN_IDLE;
                end
                
                default: state <= GEN_IDLE;
            endcase
        end
    end

endmodule