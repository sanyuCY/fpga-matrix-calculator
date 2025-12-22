`timescale 1ns / 1ps

module matrix_display (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        display_start,
    input  wire [2:0]  row_num,
    input  wire [2:0]  col_num,
    input  wire [1:0]  matrix_id,
    input  wire        dim_error,

    output reg  [4:0]  read_addr,
    input  wire [7:0]  element_val,   // 0~99

    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy,

    output reg         display_busy
);

    // FSM states
    localparam IDLE       = 4'd0,
               SEND_HEAD  = 4'd1,
               SEND_PAD   = 4'd2, // ★ 对齐补空格
               SEND_TENS  = 4'd3,
               SEND_ONES  = 4'd4,
               SEND_SPACE = 4'd5,
               SEND_CR    = 4'd6,
               SEND_LF    = 4'd7,
               SEND_ERR   = 4'd8,
               WAIT_DONE  = 4'd9;

    reg [3:0] state, next_state;

    reg [4:0] element_cnt;
    reg [2:0] col_cnt;
    reg [3:0] char_idx;

    reg [3:0] tens, ones;
    reg        two_digit;

    //============================================================
    // 状态寄存器
    //============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    //============================================================
    // 状态跳转
    //============================================================
    always @(*) begin
        case (state)
            IDLE:
                if (dim_error) next_state = SEND_ERR;
                else if (display_start) next_state = SEND_HEAD;
                else next_state = IDLE;

            SEND_HEAD:
                if (!tx_busy && char_idx == 3) next_state = SEND_PAD;
                else next_state = SEND_HEAD;

            SEND_PAD:
                if (!tx_busy)
                    next_state = two_digit ? SEND_TENS : SEND_ONES;
                else
                    next_state = SEND_PAD;

            SEND_TENS:
                if (!tx_busy) next_state = SEND_ONES;
                else next_state = SEND_TENS;

            SEND_ONES:
                if (!tx_busy) next_state = WAIT_DONE;
                else next_state = SEND_ONES;

            WAIT_DONE:
                if (!tx_busy) begin
                    if (element_cnt == row_num * col_num)
                        next_state = IDLE;
                    else if (col_cnt + 1 == col_num)
                        next_state = SEND_CR;
                    else
                        next_state = SEND_SPACE;
                end else
                    next_state = WAIT_DONE;

            SEND_SPACE: next_state = SEND_PAD;
            SEND_CR:    next_state = SEND_LF;
            SEND_LF:    next_state = SEND_PAD;

            SEND_ERR:
                if (!tx_busy && char_idx == 7) next_state = IDLE;
                else next_state = SEND_ERR;

            default: next_state = IDLE;
        endcase
    end

    //============================================================
    // 输出与计数逻辑
    //============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start     <= 0;
            tx_data      <= 0;
            display_busy <= 0;
            element_cnt  <= 0;
            col_cnt      <= 0;
            char_idx     <= 0;
            read_addr    <= 0;
            tens         <= 0;
            ones         <= 0;
            two_digit    <= 0;
        end else begin
            tx_start <= 0;

            case (state)
                IDLE: begin
                    display_busy <= 0;
                    element_cnt  <= 0;
                    col_cnt      <= 0;
                    char_idx     <= 0;
                    read_addr    <= 0;
                end

                SEND_HEAD: begin
                    display_busy <= 1;
                    if (char_idx == 0) begin
                        element_cnt <= 0;
                        col_cnt     <= 0;
                        read_addr   <= 0;
                    end
                    if (!tx_busy) begin
                        tx_start <= 1;
                        case (char_idx)
                            0: tx_data <= "M";
                            1: tx_data <= "0" + matrix_id;
                            2: tx_data <= ":";
                            3: tx_data <= " ";
                        endcase
                        char_idx <= char_idx + 1;
                    end
                end

                SEND_PAD: begin
                    if (!tx_busy) begin
                        read_addr <= element_cnt;
                        tens      <= element_val / 10;
                        ones      <= element_val % 10;
                        two_digit <= (element_val >= 10);

                        // ★ 一位数补空格
                        tx_data  <= (element_val < 10) ? " " : ("0" + tens);
                        tx_start <= 1;
                    end
                end

                SEND_TENS: begin
                    if (!tx_busy) begin
                        tx_data  <= "0" + tens;
                        tx_start <= 1;
                    end
                end

                SEND_ONES: begin
                    if (!tx_busy) begin
                        tx_data  <= "0" + ones;
                        tx_start <= 1;
                        element_cnt <= element_cnt + 1;
                        col_cnt     <= col_cnt + 1;
                    end
                end

                SEND_SPACE: begin
                    if (!tx_busy) begin
                        tx_data  <= " ";
                        tx_start <= 1;
                    end
                end

                SEND_CR: begin
                    if (!tx_busy) begin
                        tx_data  <= 8'h0D;
                        tx_start <= 1;
                        col_cnt  <= 0;
                    end
                end

                SEND_LF: begin
                    if (!tx_busy) begin
                        tx_data  <= 8'h0A;
                        tx_start <= 1;
                    end
                end

                SEND_ERR: begin
                    display_busy <= 1;
                    if (!tx_busy) begin
                        tx_start <= 1;
                        case (char_idx)
                            0: tx_data <= "E";
                            1: tx_data <= "r";
                            2: tx_data <= "r";
                            3: tx_data <= "o";
                            4: tx_data <= "r";
                            5: tx_data <= 8'h0D;
                            6: tx_data <= 8'h0A;
                        endcase
                        char_idx <= char_idx + 1;
                    end
                end
            endcase
        end
    end

endmodule


// 成员 A 交付说明：
// 接口对接：

// read_addr 和 element_val 需要连接到你（或成员 B）定义的矩阵存储模块（RAM/Reg array）。

// tx_data, tx_start, tx_busy 直接连到你已有的 uart_tx 模块。

// 扩展性：

// 代码中 SEND_VAL 状态目前仅支持 0-9 的个位数。如果后续运算产生两位数（如 10-25），你需要增加一个“十位数判断逻辑”分别发送两个 ASCII 码。

// Bonus 建议：

// 如果要实现列对齐，可以在 SEND_SPACE 状态下添加一个计数器，根据 element_val 的宽度决定连续发送 1 个还是 2 个空格。

// 这套代码涵盖了你图片任务中所有的串口显示要求。建议先在 Vivado 中进行功能仿真，观察 tx_data 是否按预想的顺序变换。