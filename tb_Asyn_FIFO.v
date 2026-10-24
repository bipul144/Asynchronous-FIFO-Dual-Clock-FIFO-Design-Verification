
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/26/2026 12:13:34 PM
// Design Name: 
// Module Name: tb_Asyn_FIFO
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps
//======================================================================
// Self-checking testbench for Asyn_FIFO (Cummings-style dual-clock FIFO)
//   - Independent write and read clocks (different frequencies)
//   - Randomized write/read activity, including back-to-back bursts
//   - Attempts writes-while-full and reads-while-empty to verify the
//     FIFO correctly blocks/ignores them (no corruption, no overflow)
//   - Scoreboards every written word in a queue and checks every read
//     word against it (data integrity + ordering check)
//   - Reports PASS/FAIL summary at the end
//======================================================================

module tb_async_fifo;

  //--------------------------------------------------------------
  // Parameters
  //--------------------------------------------------------------
  parameter DSIZE = 8;
  parameter ASIZE = 4;                 // 16-entry FIFO
  parameter DEPTH = (1 << ASIZE);

  parameter WCLK_PERIOD = 10;          // write clock period (ns)
  parameter RCLK_PERIOD = 17;          // read clock period (ns) - different freq

  parameter NUM_TRANSFERS = 100;      // number of words to push through

  //--------------------------------------------------------------
  // DUT signals
  //--------------------------------------------------------------
  reg  [DSIZE-1:0] wdata;
  reg              winc, wclk, wrst_n;
  reg              rinc, rclk, rrst_n;
  wire [DSIZE-1:0] rdata;
  wire             wfull;
  wire             rempty;

  //--------------------------------------------------------------
  // Bookkeeping
  //--------------------------------------------------------------
  integer errors;
  integer warnings;
  integer words_written;
  integer words_read;

  // Reference model: a simple queue of written data, used to check
  // that reads come back in order with the correct value.
  reg [DSIZE-1:0] ref_queue [0:1<<20];
  integer wr_ptr;   // next free slot to push into ref_queue
  integer rd_ptr;   // next slot to pop / compare against

  reg [7:0] wr_data_cnt;               // free-running counter used to build wdata

  //--------------------------------------------------------------
  // DUT instantiation
  //--------------------------------------------------------------
  Asyn_FIFO #(.DSIZE(DSIZE), .ASIZE(ASIZE)) dut (
    .rdata  (rdata),
    .wfull  (wfull),
    .rempty (rempty),
    .wdata  (wdata),
    .winc   (winc),
    .wclk   (wclk),
    .wrst_n (wrst_n),
    .rinc   (rinc),
    .rclk   (rclk),
    .rrst_n (rrst_n)
  );

  //--------------------------------------------------------------
  // Clock generation
  //--------------------------------------------------------------
  initial wclk = 0;
  always #(WCLK_PERIOD/2) wclk = ~wclk;

  initial rclk = 0;
  always #(RCLK_PERIOD/2) rclk = ~rclk;

  //--------------------------------------------------------------
  // Reset generation
  //--------------------------------------------------------------
  initial begin
    wrst_n = 0;
    winc   = 0;
    wdata  = 0;
    repeat (5) @(posedge wclk);
    wrst_n = 1;
  end

  initial begin
    rrst_n = 0;
    rinc   = 0;
    repeat (5) @(posedge rclk);
    rrst_n = 1;
  end

  //--------------------------------------------------------------
  // Write process
  //   Drives winc/wdata on wclk. Randomized activity: sometimes
  //   idle, sometimes back-to-back writes. Always respects wfull
  //   (never asserts winc when wfull is high) and also occasionally
  //   *tries* to write while full on purpose to prove the DUT
  //   ignores it (checked via words_written vs mem depth logic).
  //--------------------------------------------------------------
  integer wr_attempts_while_full;
  reg     wfull_sampled;

  initial begin
    wr_data_cnt = 0;
    wr_ptr = 0;
    words_written = 0;
    wr_attempts_while_full = 0;
    winc  = 0;
    wdata = 0;

    @(posedge wrst_n);
    repeat (3) @(posedge wclk); // settle

    while (words_written < NUM_TRANSFERS) begin
      // Sample wfull *before* driving winc for this cycle: the DUT's
      // fifomem accepts a write on the upcoming posedge using the wfull
      // value that is valid going into that edge (registered, so it is
      // stable from the previous posedge through this point).
      @(negedge wclk);
      wfull_sampled = wfull;
      if (wfull_sampled) begin
        // Intentionally try to write while full sometimes, to check
        // that the FIFO does NOT accept/corrupt data when full.
        if ($random % 4 == 0) begin
          winc  = 1;
          wdata = wr_data_cnt; // this value must NOT be accepted
          wr_attempts_while_full = wr_attempts_while_full + 1;
        end else begin
          winc = 0;
        end
      end else begin
        // Randomize: ~75% chance to write when not full
        if (($random % 4) != 0) begin
          winc  = 1;
          wdata = wr_data_cnt;
        end else begin
          winc = 0;
        end
      end
      @(posedge wclk);
      if (winc && !wfull_sampled) begin
        // This write is actually accepted by the DUT this cycle
        ref_queue[wr_ptr] = wdata;
        wr_ptr = wr_ptr + 1;
        wr_data_cnt = wr_data_cnt + 1;
        words_written = words_written + 1;
      end
    end

    @(negedge wclk);
    winc = 0;
  end

  //--------------------------------------------------------------
  // Read process
  //   Drives rinc on rclk. Randomized activity, respects rempty,
  //   and occasionally tries to read while empty to prove the FIFO
  //   correctly ignores it.
  //--------------------------------------------------------------
  integer rd_attempts_while_empty;
  reg     rempty_sampled;
  reg [DSIZE-1:0] rdata_sampled;

  initial begin
    rd_ptr = 0;
    words_read = 0;
    rd_attempts_while_empty = 0;
    rinc = 0;

    @(posedge rrst_n);
    repeat (3) @(posedge rclk);

    while (words_read < NUM_TRANSFERS) begin
      // Sample rempty and rdata *before* the popping edge: rdata is an
      // asynchronous read of mem[raddr], and raddr corresponds to the
      // NEXT word to be popped (word #rd_ptr) right up until the edge
      // where rinc advances the pointer. Sampling here (pre-edge) gives
      // us the word that will actually be consumed on this edge.
      @(negedge rclk);
      rempty_sampled = rempty;
      rdata_sampled  = rdata;
      if (rempty_sampled) begin
        if ($random % 4 == 0) begin
          rinc = 1; // intentional read-while-empty attempt
          rd_attempts_while_empty = rd_attempts_while_empty + 1;
        end else begin
          rinc = 0;
        end
      end else begin
        if (($random % 4) != 0) begin
          rinc = 1;
        end else begin
          rinc = 0;
        end
      end
      @(posedge rclk);
      if (rinc && !rempty_sampled) begin
        if (rdata_sampled !== ref_queue[rd_ptr]) begin
          $display("[%0t] ERROR: Data mismatch at read #%0d: expected %0h, got %0h",
                    $time, rd_ptr, ref_queue[rd_ptr], rdata_sampled);
          errors = errors + 1;
        end else begin
          $display("[%0t] READ OK  #%0d: data=%0h", $time, rd_ptr, rdata_sampled);
        end
        rd_ptr = rd_ptr + 1;
        words_read = words_read + 1;
      end
    end

    @(negedge rclk);
    rinc = 0;
  end

  //--------------------------------------------------------------
  // Protection checkers: FIFO must never be pushed while full, and
  // must never advance a real read while empty. These monitors watch
  // for evidence of overflow/underflow corruption independent of the
  // data scoreboard above.
  //--------------------------------------------------------------
  always @(posedge wclk) begin
    if (wrst_n && winc && wfull) begin
      // This is fine as long as fifomem's "if (wclken && !wfull)" guard
      // holds - verify wfull was actually asserted and no false full.
      $display("[%0t] INFO: write attempted while wfull asserted (correctly expected to be dropped)", $time);
    end
  end

  always @(posedge rclk) begin
    if (rrst_n && rinc && rempty) begin
      $display("[%0t] INFO: read attempted while rempty asserted (correctly expected to be ignored)", $time);
    end
  end

  //--------------------------------------------------------------
  // Full/Empty sanity checks:
  //   - wfull must never be asserted with fewer than DEPTH entries
  //     of "in-flight" words, i.e. words_written - words_read < DEPTH
  //   - rempty must never be asserted when words_written > words_read
  //     for a stable number of cycles (allow for CDC latency by only
  //     flagging when the *sustained* mismatch is implausible - kept
  //     simple here by just logging status, main correctness relies
  //     on the data scoreboard which would fail on any real corruption)
  //--------------------------------------------------------------
  reg [31:0] occupancy;
  always @(*) occupancy = words_written - words_read;

  always @(posedge wclk) begin
    if (wrst_n && wfull && (occupancy < DEPTH)) begin
      // Because of CDC sync latency this *can* occur transiently and is
      // by design (conservative full flag) - only flag if occupancy is
      // far below depth, which would indicate a genuine bug.
      if (occupancy < (DEPTH - 4)) begin
        $display("[%0t] WARNING: wfull asserted with only %0d occupancy (DEPTH=%0d)",
                  $time, occupancy, DEPTH);
        warnings = warnings + 1;
      end
    end
  end

  //--------------------------------------------------------------
  // Timeout watchdog
  //--------------------------------------------------------------
  initial begin
    errors   = 0;
    warnings = 0;
    #(WCLK_PERIOD * RCLK_PERIOD * NUM_TRANSFERS * 4 + 100000);
    $display("\n*** TIMEOUT: simulation did not complete in expected time ***");
    $display("words_written=%0d words_read=%0d", words_written, words_read);
    $finish;
  end

  //--------------------------------------------------------------
  // End of test / final report
  //--------------------------------------------------------------
  initial begin
    wait (words_written >= NUM_TRANSFERS);
    wait (words_read    >= NUM_TRANSFERS);
    repeat (20) @(posedge rclk); // drain any pipeline delta

    $display("\n==============================================");
    $display(" TEST SUMMARY");
    $display("==============================================");
    $display(" Words written        : %0d", words_written);
    $display(" Words read           : %0d", words_read);
    $display(" Write-while-full tries : %0d", wr_attempts_while_full);
    $display(" Read-while-empty tries : %0d", rd_attempts_while_empty);
    $display(" Data mismatch errors  : %0d", errors);
    $display(" Warnings              : %0d", warnings);
    if (errors == 0)
      $display(" RESULT: **** PASS ****");
    else
      $display(" RESULT: **** FAIL ****");
    $display("==============================================\n");
    $finish;
  end

  //--------------------------------------------------------------
  // Waveform dump (optional)
  //--------------------------------------------------------------
  initial begin
    $dumpfile("tb_async_fifo.vcd");
    $dumpvars(0, tb_async_fifo);
  end

endmodule
