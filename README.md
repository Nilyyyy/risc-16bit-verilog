# 16-bit RISC Processor — Verilog

A 16-bit RISC processor implementation with a 5-stage pipeline, designed and simulated using SystemVerilog.

## Pipeline Stages

```
IF → ID → EX → MEM → WB
```

| Stage | Description |
|-------|-------------|
| IF  | Instruction Fetch |
| ID  | Instruction Decode |
| EX  | Execute (ALU) |
| MEM | Memory Access |
| WB  | Write Back |

## Instruction Set

**R-Type:** `ADD`, `SUB`, `AND`, `OR`, `SLT`, `SLL`, `SRL`

**I-Type:** `ADDI`, `LW`, `SW`, `BEQ`, `BNE`

**J-Type:** `J`, `JAL`, `JR`

## Architecture

- 16-bit word-addressed instruction and data memory
- 8 general-purpose 16-bit registers
- ALU with signed/unsigned operations and shift support
- 6-bit sign-extended immediate values
- Branch and jump support

## Files

| File | Description |
|------|-------------|
| `design.sv` | Main processor design (ALU, Register File, Pipeline) |
| `testbench.sv` | Simulation testbench |
| `risc_pipeline.vcd` | Waveform output |
| `run.sh` | Simulation run script |

## How to Run

```bash
bash run.sh
```

## Technologies

- SystemVerilog
- EDA Playground / ModelSim
