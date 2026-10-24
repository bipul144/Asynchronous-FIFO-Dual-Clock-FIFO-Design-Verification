# Asynchronous FIFO (Dual-Clock FIFO) — Design & Verification
 
A parameterizable, dual-clock asynchronous FIFO implemented in Verilog, verified with a self-checking randomized testbench, and carried through synthesis and implementation in Xilinx Vivado.
 
**Tools used:** Verilog, Xilinx Vivado (xsim, synthesis, implementation)
 
---
 
## Overview
 
This project implements the classic Cummings-style asynchronous FIFO: a circular buffer that safely transfers data between two independent, unrelated clock domains (a write clock and a read clock) without data corruption, using Gray-coded pointers and two-stage flip-flop synchronizers to avoid metastability issues inherent to clock-domain crossing (CDC).
 
The design is split into clean, single-responsibility modules and paired with a testbench that stresses it with randomized, independently-clocked read/write traffic and a scoreboard that checks every single word for correctness and ordering.
 
## Features
 
- **Configurable depth and width** via `DSIZE` (data width) and `ASIZE` (address width) parameters — default: 16-deep, 8-bit wide.
- **Gray-code pointer synchronization** between write and read clock domains, avoiding multi-bit synchronization hazards.
- **Two-stage (2-flop) synchronizers** on both the read-to-write and write-to-read paths, the standard mitigation for metastability in CDC designs.
- **Combinational full/empty flag generation**, registered for glitch-free operation, derived by comparing the local pointer against the synchronized remote pointer.
- **Self-checking, randomized testbench** with independent write and read clocks running at different frequencies, exercising realistic asynchronous behavior rather than a single shared clock.
## Architecture
 
```
Asyn_FIFO
 ├── fifomem        -- dual-port memory array (write-clock domain)
 ├── sync_r2w        -- synchronizes the read pointer into the write clock domain
 ├── sync_w2r        -- synchronizes the write pointer into the read clock domain
 ├── rptr_empty      -- read-pointer logic, Gray-code generation, empty-flag generation
 └── wptr_full       -- write-pointer logic, Gray-code generation, full-flag generation
```
 
## Repository Structure
 
```
.
├── Asyn_FIFO.v           # FIFO design (top module + submodules)
├── tb_async_fifo.v        # Self-checking randomized testbench
├── run_sim.tcl             # Vivado batch-mode simulation script
└── README.md
```
 
## Verification Approach
 
The testbench (`tb_async_fifo.v`) drives the design with:
 
- **Independent clocks** — a 10 ns write clock and a 17 ns read clock, so the two domains genuinely drift in phase relative to each other (not derived from a shared source).
- **Randomized write/read activity**, including idle cycles and back-to-back bursts.
- **Deliberate full/empty boundary stimulus** — the testbench intentionally attempts writes while the FIFO is full and reads while it is empty, to confirm the design correctly rejects/ignores these without corrupting data.
- **A queue-based scoreboard** — every word accepted by the write side is pushed into a reference model; every word popped by the read side is checked against that model, in order, flagging any mismatch immediately.
### Results
 
Across a 2000-transaction randomized run:
 
```
Words written          : 2000
Words read              : 2000
Write-while-full tries  : 365
Read-while-empty tries  : 0
Data mismatch errors    : 0
RESULT: **** PASS ****
```
 
Zero data mismatches confirms correct cross-domain data integrity and ordering under randomized, asynchronous stimulus, including correct rejection of writes while full.
 
## Running the Simulation
 
**In the Vivado GUI:**
1. Open the project and add `Asyn_FIFO.v` and `tb_async_fifo.v` to the simulation sources.
2. Set `tb_async_fifo` as the simulation top module.
3. Run behavioral simulation (`Run All`).
**In batch mode (scripted):**
```bash
vivado -mode batch -source run_sim.tcl -log run_output.log
```
 
## Next Steps
 
- Add SystemVerilog assertions (SVA) for live, cycle-accurate checks (e.g. `wfull` and `rempty` never asserted simultaneously).
- Hardware validation on an FPGA board using the Integrated Logic Analyzer (ILA) to observe real clock-domain-crossing behavior, since simulation cannot reproduce metastability.
- Functional coverage instrumentation to confirm corner cases (simultaneous reset + full/empty, maximum-rate bursts) are exercised.
## License
 
MIT — feel free to use or adapt this design for learning purposes.
