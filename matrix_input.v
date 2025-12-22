`timescale 1ns / 1ps

module matrix_input (
    input wire clk,
    input wire rst_n,
    input wire [7:0] uart_rx_data,
    input wire rx_done,
    input wire [3:0] current_mode,
    input wire [7:0] val_min,
    input wire [7:0] val_max,
    output reg [3:0] mat_m,
    output reg [3:0] mat_n,
    output reg [199:0] mat_data_flat,
    output reg store_en,
    output reg input_done,
    output reg [2:0] error_type
);

    localparam S_INPUT = 4'b0001;
    localparam INPUT_IDLE = 3'd0;
    localparam INPUT_WAIT_M = 3'd1;
    localparam INPUT_WAIT_N = 3'd2;
    localparam INPUT_WAIT_DATA = 3'd3;
    localparam INPUT_DONE = 3'd4;
    localparam ERR_NONE = 3'b000;
    localparam ERR_DIM = 3'b001;

    reg [2:0] state;
    reg [4:0] elem_cnt;
    reg [4:0] total_elem;
    reg [3:0] temp_m;
    reg just_finished;
    
    reg [3:0] current_mode_d;
    reg rx_done_d;
    
    wire mode_enter_input;
    wire rx_done_pulse;
    wire [3:0] rx_digit;
    wire is_digit;
    
    assign mode_enter_input = (current_mode == S_INPUT) && (current_mode_d != S_INPUT);
    assign rx_done_pulse = rx_done && (!rx_done_d);
    assign rx_digit = uart_rx_data[3:0];
    assign is_digit = (uart_rx_data >= 8'h30) && (uart_rx_data <= 8'h39);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_mode_d <= 4'd0;
            rx_done_d <= 1'b0;
        end
        else begin
            current_mode_d <= current_mode;
            rx_done_d <= rx_done;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= INPUT_IDLE;
            mat_m <= 4'd0;
            mat_n <= 4'd0;
            mat_data_flat <= 200'd0;
            temp_m <= 4'd0;
            elem_cnt <= 5'd0;
            total_elem <= 5'd0;
            store_en <= 1'b0;
            input_done <= 1'b0;
            error_type <= ERR_NONE;
            just_finished <= 1'b0;
        end
        else begin
            store_en <= 1'b0;
            input_done <= 1'b0;
            
            if (mode_enter_input) begin
                just_finished <= 1'b0;
            end
            
            case (state)
                INPUT_IDLE: begin
                    if (current_mode == S_INPUT && !just_finished) begin
                        state <= INPUT_WAIT_M;
                        elem_cnt <= 5'd0;
                        mat_data_flat <= 200'd0;
                        error_type <= ERR_NONE;
                    end
                end
                
                INPUT_WAIT_M: begin
                    if (current_mode != S_INPUT) begin
                        state <= INPUT_IDLE;
                    end
                    else if (rx_done_pulse && is_digit) begin
                        if (rx_digit < 4'd1 || rx_digit > 4'd5) begin
                            error_type <= ERR_DIM;
                            state <= INPUT_IDLE;
                        end
                        else begin
                            temp_m <= rx_digit;
                            state <= INPUT_WAIT_N;
                        end
                    end
                end
                
                INPUT_WAIT_N: begin
                    if (current_mode != S_INPUT) begin
                        state <= INPUT_IDLE;
                    end
                    else if (rx_done_pulse && is_digit) begin
                        if (rx_digit < 4'd1 || rx_digit > 4'd5) begin
                            error_type <= ERR_DIM;
                            state <= INPUT_IDLE;
                        end
                        else begin
                            mat_m <= temp_m;
                            mat_n <= rx_digit;
                            total_elem <= temp_m * rx_digit;
                            elem_cnt <= 5'd0;
                            state <= INPUT_WAIT_DATA;
                        end
                    end
                end
                
                INPUT_WAIT_DATA: begin
                    if (current_mode != S_INPUT) begin
                        state <= INPUT_IDLE;
                    end
                    else if (rx_done_pulse && is_digit) begin
                        mat_data_flat[elem_cnt*8 +: 8] <= {4'd0, rx_digit};
                        
                        if (elem_cnt >= total_elem - 1) begin
                            state <= INPUT_DONE;
                        end
                        else begin
                            elem_cnt <= elem_cnt + 5'd1;
                        end
                    end
                end
                
                INPUT_DONE: begin
                    store_en <= 1'b1;
                    input_done <= 1'b1;
                    just_finished <= 1'b1;
                    state <= INPUT_IDLE;
                end
                
                default: state <= INPUT_IDLE;
            endcase
        end
    end

endmodule