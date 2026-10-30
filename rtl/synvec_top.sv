`timescale 1ns/1ps

module synvec_top (
 input logic clk100,input logic btnC,input logic [15:0] sw,
 output logic [15:0] led,
 output logic [6:0] seg,output logic [3:0] an,
 input logic uart_rx_in,
 output logic dp,uart_tx_out,pwm_out
);
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic btn_meta=1'b0;
 (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) logic btn_sync=1'b0;
 always_ff @(posedge clk100) begin
   btn_meta<=btnC;
   btn_sync<=btn_meta;
 end
 logic [1:0] rst_pipe=2'b00;
 always_ff @(posedge clk100) begin
   if (btn_sync) rst_pipe<=2'b00;
   else rst_pipe<={rst_pipe[0],1'b1};
 end
 wire reset_n=rst_pipe[1];
 logic if_en,d_en,d_we,retire_valid,fault_valid;
 logic [31:0] if_addr,if_rdata,d_addr,d_wdata,d_rdata,disp;
 logic [3:0] d_be,fault_cause;
 logic [31:0] fault_pc,retire_pc,retire_insn,retire_rd_value;
 logic [4:0] retire_rd;
 logic [15:0] led_normal;
 rv32i_pipeline cpu(.clk(clk100),.reset_n(reset_n),.if_en(if_en),.if_addr(if_addr),
    .if_rdata(if_rdata),.d_en(d_en),.d_we(d_we),.d_addr(d_addr),.d_wdata(d_wdata),
    .d_be(d_be),.d_rdata(d_rdata),.fault_valid(fault_valid),.fault_cause(fault_cause),
    .fault_pc(fault_pc),.retire_valid(retire_valid),.retire_pc(retire_pc),
    .retire_insn(retire_insn),.retire_rd_value(retire_rd_value),.retire_rd(retire_rd));
 soc_memory mem(.clk(clk100),.reset_n(reset_n),.if_en(if_en),.if_addr(if_addr),.if_rdata(if_rdata),
    .d_en(d_en),.d_we(d_we),.d_addr(d_addr),.d_wdata(d_wdata),.d_rdata(d_rdata),
    .d_be(d_be),.retire_valid(retire_valid),.switches(sw),.leds(led_normal),
    .display_value(disp),.uart_in(uart_rx_in),.uart_out(uart_tx_out),.pwm_out(pwm_out));
 sevenseg display(.clk(clk100),.reset_n(reset_n),.value(disp),.fault(fault_valid),
    .cause(fault_cause),.seg(seg),.an(an));
 assign led=fault_valid?fault_pc[15:0]:led_normal;
 assign dp=1'b1;
endmodule
