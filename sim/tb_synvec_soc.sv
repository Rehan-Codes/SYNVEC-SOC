`timescale 1ns/1ps
`include "synvec_paths.svh"




module tb_synvec_soc;
  localparam integer BIT_CYCLES=868;
  localparam integer MAT_CASES=2;
  localparam integer EXPECT_RX=139;
  localparam integer EXPECT_TX=136;
  logic clk=0, reset_n=0, uart_in=1;
  always #5 clk=~clk;
  logic if_en,d_en,d_we,retire_valid,fault_valid;
  logic [31:0] if_addr,if_rdata,d_addr,d_wdata,d_rdata;
  logic [3:0] d_be,fault_cause;
  logic [31:0] fault_pc,retire_pc,retire_insn,retire_rd_value;
  logic [4:0] retire_rd;
  logic [15:0] leds;
  logic [31:0] display_value;
  logic uart_out,pwm_out;
  logic [15:0] operand_words [0:63];
  logic [31:0] expected_words [0:31];
  logic [7:0] expected_rx [0:EXPECT_RX-1];
  logic [7:0] expected_tx [0:EXPECT_TX-1];
  integer rx_index=0, tx_write_index=0, tx_frame_index=0;
  integer matrix_operand_writes=0, matrix_starts=0, matrix_result_reads=0;
  integer matrix_done_polls=0, led_writes=0, pwm_period_writes=0;
  integer pwm_high_writes=0, pwm_apply_writes=0, retirements=0;
  integer rx_fill=0,tx_fill=0;
  integer runid,i,r,c,k,b;
  longint signed acc,lhs,rhs;

  initial begin : setup_golden
    $readmemh(`SYNVEC_FIXTURE_PATH,operand_words);
    for(integer testcase=0;testcase<MAT_CASES;testcase=testcase+1) begin
      for(integer row=0;row<4;row=row+1) begin
        for(integer col=0;col<4;col=col+1) begin
          acc=0;
          for(integer inner=0;inner<4;inner=inner+1) begin
            lhs=$signed(operand_words[testcase*32+row*4+inner]);
            rhs=$signed(operand_words[testcase*32+16+inner*4+col]);
            acc=acc+(lhs*rhs);
          end
          expected_words[testcase*16+row*4+col]=acc[31:0];
        end
      end
      expected_rx[rx_fill]=8'h4d; rx_fill=rx_fill+1;
      for(integer n=0;n<32;n=n+1) begin
        expected_rx[rx_fill]=operand_words[testcase*32+n][7:0];rx_fill=rx_fill+1;
        expected_rx[rx_fill]=operand_words[testcase*32+n][15:8];rx_fill=rx_fill+1;
      end
      expected_tx[tx_fill]=8'h06;tx_fill=tx_fill+1;
      for(integer n=0;n<16;n=n+1) begin
        for(integer lane=0;lane<4;lane=lane+1) begin
          expected_tx[tx_fill]=(expected_words[testcase*16+n]>>(8*lane)) & 8'hff;
          tx_fill=tx_fill+1;
        end
      end
    end

    expected_rx[rx_fill]=8'h4c;rx_fill=rx_fill+1;
    expected_rx[rx_fill]=8'ha5;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'h06;tx_fill=tx_fill+1;
    expected_rx[rx_fill]=8'h52;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'ha5;tx_fill=tx_fill+1;
    expected_rx[rx_fill]=8'h49;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'h03;tx_fill=tx_fill+1;
    expected_rx[rx_fill]=8'h50;rx_fill=rx_fill+1;
    expected_rx[rx_fill]=8'h02;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'h06;tx_fill=tx_fill+1;
    expected_rx[rx_fill]=8'h50;rx_fill=rx_fill+1;
    expected_rx[rx_fill]=8'h00;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'h06;tx_fill=tx_fill+1;
    expected_rx[rx_fill]=8'h7f;rx_fill=rx_fill+1;
    expected_tx[tx_fill]=8'h15;tx_fill=tx_fill+1;
    if(rx_fill!=EXPECT_RX || tx_fill!=EXPECT_TX)
      $fatal(1,"SYNVEC TESTBENCH FIXTURE COUNT ERROR RX=%0d TX=%0d",rx_fill,tx_fill);
  end

  rv32i_pipeline cpu(.clk(clk),.reset_n(reset_n),.if_en(if_en),.if_addr(if_addr),
    .if_rdata(if_rdata),.d_en(d_en),.d_we(d_we),.d_addr(d_addr),
    .d_wdata(d_wdata),.d_be(d_be),.d_rdata(d_rdata),
    .fault_valid(fault_valid),.fault_cause(fault_cause),.fault_pc(fault_pc),
    .retire_valid(retire_valid),.retire_pc(retire_pc),
    .retire_insn(retire_insn),.retire_rd_value(retire_rd_value),.retire_rd(retire_rd));
  soc_memory #(.MEMFILE(`SYNVEC_ROM_PATH)) mem(.clk(clk),.reset_n(reset_n),
    .if_en(if_en),.if_addr(if_addr),.if_rdata(if_rdata),
    .d_en(d_en),.d_we(d_we),.d_addr(d_addr),.d_wdata(d_wdata),
    .d_rdata(d_rdata),.d_be(d_be),.retire_valid(retire_valid),
    .switches(16'b0),.leds(leds),.display_value(display_value),
    .uart_in(uart_in),.uart_out(uart_out),.pwm_out(pwm_out));

  always @(posedge clk) if(reset_n) begin
    if(retire_valid) retirements=retirements+1;
    if(fault_valid) $fatal(1,"SYNVEC CPU FAULT: pc=%h cause=%h",fault_pc,fault_cause);
    if(d_en && !d_we && d_addr==32'h40000008) begin
      if(rx_index>=EXPECT_RX || !mem.rx_valid || mem.rx_data!==expected_rx[rx_index])
        $fatal(1,"SYNVEC RX POP ERROR idx=%0d actual=%h",rx_index,mem.rx_data);
      rx_index=rx_index+1;
    end
    if(d_en && d_we) begin
      if(d_be!==4'b1111)
        $fatal(1,"SYNVEC BAD BYTE ENABLES: addr=%h be=%b",d_addr,d_be);
      if(d_addr==32'h40000000) begin
        if(tx_write_index>=EXPECT_TX || d_wdata[7:0]!==expected_tx[tx_write_index])
          $fatal(1,"SYNVEC UART TX BUS MISMATCH idx=%0d got=%h want=%h",tx_write_index,d_wdata[7:0],expected_tx[tx_write_index]);
        tx_write_index=tx_write_index+1;
      end else if(d_addr>=32'h40004020 && d_addr<=32'h4000409c) begin
        if(matrix_operand_writes>=64 || d_addr!==32'h40004020+4*(matrix_operand_writes%32) ||
            d_wdata[15:0]!==operand_words[matrix_operand_writes])
          $fatal(1,"SYNVEC MAT OPERAND WRITE MISMATCH idx=%0d addr=%h value=%h",matrix_operand_writes,d_addr,d_wdata);
        matrix_operand_writes=matrix_operand_writes+1;
      end else if(d_addr==32'h40004000) begin
        if(matrix_starts>=2 || d_wdata!==32'd3 || matrix_operand_writes!=(matrix_starts+1)*32)
          $fatal(1,"SYNVEC MATRIX START ERROR starts=%0d data=%h words=%0d",matrix_starts,d_wdata,matrix_operand_writes);
        matrix_starts=matrix_starts+1;
      end else if(d_addr==32'h40001004) begin
        if(led_writes!=0 || d_wdata!==32'h000000a5) $fatal(1,"SYNVEC LED write mismatch");
        led_writes=led_writes+1;
      end else if(d_addr==32'h40002000) begin
        if(pwm_period_writes!=0 || d_wdata!==32'd24999) $fatal(1,"SYNVEC PWM period mismatch");
        pwm_period_writes=pwm_period_writes+1;
      end else if(d_addr==32'h40002004) begin
        if(pwm_high_writes!=0 || d_wdata!==32'd12500) $fatal(1,"SYNVEC PWM high mismatch");
        pwm_high_writes=pwm_high_writes+1;
      end else if(d_addr==32'h40002008) begin
        if(pwm_apply_writes>=2 || d_wdata!==((pwm_apply_writes==0)?32'd3:32'd2))
          $fatal(1,"SYNVEC PWM apply mismatch %h",d_wdata);
        pwm_apply_writes=pwm_apply_writes+1;
      end else $fatal(1,"SYNVEC UNEXPECTED MMIO WRITE: addr=%h data=%h",d_addr,d_wdata);
    end
    if(d_en && !d_we && d_addr==32'h40004000) matrix_done_polls=matrix_done_polls+1;
    if(d_en && !d_we && d_addr>=32'h400040a0 && d_addr<=32'h400040dc) begin
      if(matrix_result_reads>=32 || d_addr!==32'h400040a0+4*(matrix_result_reads%16) ||
          mem.acc_rdata!==expected_words[matrix_result_reads])
        $fatal(1,"SYNVEC MAT C READ ERROR idx=%0d addr=%h got=%h expected=%h",matrix_result_reads,d_addr,mem.acc_rdata,expected_words[matrix_result_reads]);
      matrix_result_reads=matrix_result_reads+1;
    end
  end


  initial begin : uart_tx_pin_monitor
    logic [7:0] decoded;
    wait(reset_n);
    forever begin
      @(negedge uart_out);
      repeat(BIT_CYCLES/2) @(posedge clk);
      if(uart_out!==1'b0) $fatal(1,"SYNVEC UART TX START GLITCH");
      decoded=0;
      for(integer bitnum=0;bitnum<8;bitnum=bitnum+1) begin
        repeat(BIT_CYCLES) @(posedge clk);
        decoded[bitnum]=uart_out;
      end
      repeat(BIT_CYCLES) @(posedge clk);
      if(uart_out!==1'b1) $fatal(1,"SYNVEC UART TX STOP ERROR");
      if(tx_frame_index>=EXPECT_TX || decoded!==expected_tx[tx_frame_index])
        $fatal(1,"SYNVEC UART TX PIN ERROR idx=%0d actual=%h expected=%h",tx_frame_index,decoded,expected_tx[tx_frame_index]);
      tx_frame_index=tx_frame_index+1;
    end
  end

  task automatic send_byte(input logic [7:0] val);
    @(negedge clk);uart_in=0;
    repeat(BIT_CYCLES) @(negedge clk);
    for(integer bitnum=0;bitnum<8;bitnum=bitnum+1) begin
      uart_in=val[bitnum];
      repeat(BIT_CYCLES) @(negedge clk);
    end
    uart_in=1;
    repeat(BIT_CYCLES) @(negedge clk);
  endtask

  task automatic wait_frames(input integer target);
    integer elapsed;
    begin
      elapsed=0;
      while(tx_frame_index<target && elapsed<1000000) begin
        @(negedge clk);elapsed=elapsed+1;
      end
      if(tx_frame_index!=target)
        $fatal(1,"SYNVEC UART RESPONSE TIMEOUT wanted=%0d got=%0d",target,tx_frame_index);
      repeat(100) @(negedge clk);
    end
  endtask

  initial begin : scenario
    repeat(20) @(negedge clk);reset_n=1;
    repeat(120) @(negedge clk);
    for(integer case_no=0;case_no<MAT_CASES;case_no=case_no+1) begin
      send_byte(8'h4d);

      for(integer n=0;n<32;n=n+1) begin
        send_byte(operand_words[case_no*32+n][7:0]);
        send_byte(operand_words[case_no*32+n][15:8]);
      end
      wait_frames((case_no+1)*65);
      $display("SYNVEC MATRIX CASE PASS: case=%0d, 32 signed16 operands, 16 signed32 result words, UART pin byte order verified",case_no);
    end
    send_byte(8'h4c);send_byte(8'ha5);wait_frames(131);
    send_byte(8'h52);wait_frames(132);
    send_byte(8'h49);wait_frames(133);
    send_byte(8'h50);send_byte(8'h02);wait_frames(134);
    send_byte(8'h50);send_byte(8'h00);wait_frames(135);
    send_byte(8'h7f);wait_frames(136);
    repeat(30000) @(negedge clk);
    if(rx_index!=EXPECT_RX || tx_write_index!=EXPECT_TX || tx_frame_index!=EXPECT_TX ||
       matrix_operand_writes!=64 || matrix_starts!=2 || matrix_result_reads!=32 ||
       matrix_done_polls<2 || led_writes!=1 || pwm_period_writes!=1 ||
       pwm_high_writes!=1 || pwm_apply_writes!=2 || leds!==16'h00a5 ||
       mem.bus_error!==1'b0 || mem.rx_valid!==1'b0 ||
       mem.rx_overrun!==1'b0 || mem.rx_framing_error!==1'b0 ||
       mem.uart_overrun!==1'b0 || mem.matmul.error_sticky!==1'b0 ||
       fault_valid!==1'b0 || retirements<100)
      $fatal(1,"SYNVEC FINAL SCOREBOARD FAILED RX=%0d TX=%0d PIN=%0d OPERANDS=%0d START=%0d CREAD=%0d",rx_index,tx_write_index,tx_frame_index,matrix_operand_writes,matrix_starts,matrix_result_reads);
    $display("SYNVEC STAGE1 CPU MATRIX PASS: 2 matrices, 64 signed16 operand writes, 32 signed32 result reads, 136 independently checked UART TX pin bytes, 139 UART RX bytes, PWM/LED/ID regression, retirements=%0d, bus_errors=0",retirements);
    $finish;
  end
  initial begin #60000000; $fatal(1,"SYNVEC GLOBAL WATCHDOG TIMEOUT");end
endmodule
