# 矩阵计算器项目整合说明

## 文件清单

### 新生成的文件（需要添加到Vivado项目）

| 文件名 | 说明 |
|--------|------|
| `matrix_calculator_top_integrated.v` | **新顶层模块** - 替换原来的 matrix_calculator_top.v |
| `uart_rx.v` | UART接收模块（独立文件） |
| `uart_tx.v` | UART发送模块（独立文件） |
| `matrix_display.v` | 矩阵显示模块 |
| `matrix_calculator_ego1_v2.xdc` | EGO1开发板约束文件 |
| `tb_matrix_calculator_fast.v` | 快速仿真测试平台 |

### 原有文件（保持不变）

| 文件名 | 说明 |
|--------|------|
| `control_fsm.v` | 控制状态机 |
| `matrix_core_top.v` | 矩阵核心模块顶层 |
| `matrix_input.v` | 矩阵输入模块 |
| `matrix_generate.v` | 矩阵生成模块 |
| `matrix_storage.v` | 矩阵存储模块 |
| `matrix_compute.v` | 矩阵运算模块 |
| `param_config.v` | 参数配置模块 |

## 主要修改内容

### 1. 顶层模块整合 (`matrix_calculator_top_integrated.v`)

- **移除内嵌的UART模块**：原顶层文件包含内嵌的`uart_rx`和`uart_tx`模块定义，现在改为使用独立的模块文件
- **添加按键极性转换**：EGO1按键按下为低电平，代码期望高电平有效，添加了`KEY_active = ~KEY`
- **集成matrix_display模块**：用于通过UART输出矩阵内容
- **修正数码管驱动**：适配EGO1的8位共阳极数码管

### 2. UART模块差异

新的`uart_rx.v`和`uart_tx.v`与原来内嵌版本的主要差异：

| 特性 | 新模块 | 原内嵌模块 |
|------|--------|------------|
| 端口名称 | `rx`/`tx` | `rxd`/`txd` |
| 参数化 | 完整支持 | 完整支持 |
| 同步设计 | 二级同步器 | 三级同步器 |

顶层模块已适配新端口名称。

### 3. XDC约束文件修改

针对EGO1开发板（xc7a35tcsg324-1）的引脚分配：

```
时钟:     P17 (100MHz)
复位:     P15 (S1按键)
UART RX:  N5
UART TX:  T4
LED[7:0]: F6, G4, G3, J4, H4, J3, J2, K2
按键:     R15, R17, U4, R11, V1 (S2-S6)
拨码开关: P5, P4, P3, P2, R2, M4, N4, R1 (SW0-SW7)
数码管位选: G2, C2, C1, H1, G1, F1, E1, G6
数码管段选: B4, A4, A3, B1, A1, B3, B2, D5
```

## Vivado操作步骤

### 1. 更新设计源文件

1. 删除原来的 `matrix_calculator_top.v`（如果包含内嵌UART模块）
2. 添加以下文件作为设计源：
   - `matrix_calculator_top_integrated.v`
   - `uart_rx.v`
   - `uart_tx.v`
   - `matrix_display.v`
   - 其他原有的 `.v` 文件

### 2. 更新约束文件

1. 删除原来的 `.xdc` 文件
2. 添加 `matrix_calculator_ego1_v2.xdc`

### 3. 更新器件设置

1. 确认目标器件为：`xc7a35tcsg324-1`
2. 确认封装为：`csg324`

### 4. 添加仿真源

1. 添加 `tb_matrix_calculator_fast.v` 作为仿真源
2. 设置为仿真顶层模块

### 5. 运行流程

```
Run Synthesis → Run Implementation → Generate Bitstream
```

## 仿真说明

测试平台 `tb_matrix_calculator_fast.v` 包含以下测试：

1. **初始状态检查** - 验证系统复位后进入主菜单
2. **参数配置** - 通过UART发送"x=3"命令
3. **输入模式** - 进入矩阵输入模式
4. **矩阵数据输入** - 发送2x2矩阵数据
5. **返回主菜单** - 测试按键功能
6. **运算模式** - 进入转置运算模式
7. **数码管显示** - 验证显示输出
8. **内部状态** - 检查模块内部信号

### 运行仿真

在Vivado中：
1. 设置 `tb_matrix_calculator_fast` 为仿真顶层
2. Run Simulation → Run Behavioral Simulation
3. 观察波形和控制台输出

仿真超时设置为50ms，足够完成基本功能验证。

## 注意事项

1. **按键极性**：EGO1按键按下为低电平，顶层模块已添加取反逻辑

2. **数码管类型**：EGO1使用共阳极数码管
   - 位选：低电平选中
   - 段选：低电平点亮

3. **UART配置**：
   - 波特率：115200
   - 数据位：8
   - 停止位：1
   - 无校验

4. **模块层次**：
   ```
   matrix_calculator_top
   ├── uart_rx              (独立模块)
   ├── uart_tx              (独立模块)
   ├── param_config
   ├── control_fsm
   ├── matrix_core_top
   │   ├── matrix_input
   │   ├── matrix_generate
   │   ├── matrix_storage
   │   └── matrix_compute
   └── matrix_display       (新增)
   ```

## 常见问题

### Q: 生成Bitstream时出现DRC错误
A: 确保XDC文件中的所有引脚都是有效的EGO1引脚名称。检查是否选择了正确的器件型号。

### Q: 按键没有响应
A: EGO1按键是低电平有效，确认顶层模块中有 `KEY_active = ~KEY` 的取反逻辑。

### Q: 数码管显示不正确
A: EGO1使用共阳极数码管，确认段码是低电平点亮的编码方式。

### Q: UART通信失败
A: 检查波特率设置（115200），确认RX/TX引脚没有接反。
