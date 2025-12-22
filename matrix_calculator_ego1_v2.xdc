##############################################################################
## XDC约束文件 - EGO1开发板 (xc7a35tcsg324-1)
## 项目: 基于FPGA的矩阵计算器
## 版本: v2.0 - 修正引脚分配
##############################################################################

##############################################################################
## 时钟信号 - 100MHz晶振 (Y18)
##############################################################################
set_property PACKAGE_PIN P17 [get_ports clk_100m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_100m]

##############################################################################
## 复位按键 - BTN0/S1 (Active Low)
## EGO1的按键默认高电平，按下为低电平
##############################################################################
set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

##############################################################################
## 拨码开关 SW[7:0]
## EGO1拨码开关 SW0-SW7 (Active High: ON=1, OFF=0)
##############################################################################
set_property PACKAGE_PIN P5  [get_ports {SW[0]}]
set_property PACKAGE_PIN P4  [get_ports {SW[1]}]
set_property PACKAGE_PIN P3  [get_ports {SW[2]}]
set_property PACKAGE_PIN P2  [get_ports {SW[3]}]
set_property PACKAGE_PIN R2  [get_ports {SW[4]}]
set_property PACKAGE_PIN M4  [get_ports {SW[5]}]
set_property PACKAGE_PIN N4  [get_ports {SW[6]}]
set_property PACKAGE_PIN R1  [get_ports {SW[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {SW[*]}]

##############################################################################
## 按键 KEY[4:0] - BTN1-BTN5/S2-S6
## EGO1按键：按下为低电平，释放为高电平（Active Low）
## 顶层模块中已添加取反逻辑：KEY_active = ~KEY
##############################################################################
set_property PACKAGE_PIN R15 [get_ports {KEY[0]}]
set_property PACKAGE_PIN R17 [get_ports {KEY[1]}]
set_property PACKAGE_PIN U4  [get_ports {KEY[2]}]
set_property PACKAGE_PIN R11 [get_ports {KEY[3]}]
set_property PACKAGE_PIN V1  [get_ports {KEY[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {KEY[*]}]

##############################################################################
## LED输出 LED[7:0]
## EGO1 LED0-LED7 (Active High: 高电平点亮)
##############################################################################
set_property PACKAGE_PIN F6  [get_ports {LED[0]}]
set_property PACKAGE_PIN G4  [get_ports {LED[1]}]
set_property PACKAGE_PIN G3  [get_ports {LED[2]}]
set_property PACKAGE_PIN J4  [get_ports {LED[3]}]
set_property PACKAGE_PIN H4  [get_ports {LED[4]}]
set_property PACKAGE_PIN J3  [get_ports {LED[5]}]
set_property PACKAGE_PIN J2  [get_ports {LED[6]}]
set_property PACKAGE_PIN K2  [get_ports {LED[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {LED[*]}]

##############################################################################
## UART接口 - USB-UART桥
##############################################################################
set_property PACKAGE_PIN N5  [get_ports uart_rxd]
set_property PACKAGE_PIN T4  [get_ports uart_txd]

set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

##############################################################################
## 数码管位选信号 seg_sel[7:0]
## EGO1使用8位数码管，共阳极（低电平选中）
## DN[7:0] 对应8个数码管的位选
##############################################################################
set_property PACKAGE_PIN G2  [get_ports {seg_sel[0]}]
set_property PACKAGE_PIN C2  [get_ports {seg_sel[1]}]
set_property PACKAGE_PIN C1  [get_ports {seg_sel[2]}]
set_property PACKAGE_PIN H1  [get_ports {seg_sel[3]}]
set_property PACKAGE_PIN G1  [get_ports {seg_sel[4]}]
set_property PACKAGE_PIN F1  [get_ports {seg_sel[5]}]
set_property PACKAGE_PIN E1  [get_ports {seg_sel[6]}]
set_property PACKAGE_PIN G6  [get_ports {seg_sel[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[*]}]

##############################################################################
## 数码管段选信号 seg_data[7:0]
## 共阳极数码管：低电平点亮
## 段选顺序: seg_data[7:0] = {DP, G, F, E, D, C, B, A}
##############################################################################
set_property PACKAGE_PIN B4  [get_ports {seg_data[0]}]
set_property PACKAGE_PIN A4  [get_ports {seg_data[1]}]
set_property PACKAGE_PIN A3  [get_ports {seg_data[2]}]
set_property PACKAGE_PIN B1  [get_ports {seg_data[3]}]
set_property PACKAGE_PIN A1  [get_ports {seg_data[4]}]
set_property PACKAGE_PIN B3  [get_ports {seg_data[5]}]
set_property PACKAGE_PIN B2  [get_ports {seg_data[6]}]
set_property PACKAGE_PIN D5  [get_ports {seg_data[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {seg_data[*]}]

##############################################################################
## 配置设置
##############################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

##############################################################################
## Bitstream配置选项
##############################################################################
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

##############################################################################
## 使用说明：
## 
## 1. 按键功能（按下有效）：
##    - rst_n (S1/P15): 系统复位
##    - KEY[0] (S2/R15): 确认
##    - KEY[1] (S3/R17): 继续当前模式
##    - KEY[2] (S4/U4):  返回上级菜单
##    - KEY[3] (S5/R11): 返回主菜单
##    - KEY[4] (S6/V1):  切换随机选择模式
##
## 2. 拨码开关功能（ON=1）：
##    - SW[7:5]: 主菜单模式选择
##               000=输入, 001=生成, 010=展示, 011=运算
##    - SW[4:3]: 维度选择/标量值高位
##    - SW[2:0]: 运算类型
##               000=转置, 001=加法, 010=标量乘, 011=矩阵乘
##
## 3. LED指示（点亮=1）：
##    - LED[0]: 主菜单状态
##    - LED[1]: 输入模式
##    - LED[2]: 生成模式
##    - LED[3]: 展示模式
##    - LED[4]: 运算模式
##    - LED[5:7]: 错误/倒计时指示
##
## 4. UART配置：
##    - 波特率: 115200
##    - 数据位: 8
##    - 停止位: 1
##    - 校验位: 无
##
##############################################################################
