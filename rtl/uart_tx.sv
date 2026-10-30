`timescale 1ns/1ps
module uart_tx #(parameter integer DIVISOR=868) (
 input logic clk, reset_n, send,
 input logic [7:0] data,
 output logic tx, ready
);
 logic [15:0] timer;
 logic [3:0] bit_idx;
 logic [9:0] frame;
 logic busy;
 assign ready=~busy;
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin tx<=1;busy<=0;timer<=0;bit_idx<=0;frame<=10'h3ff;end
   else begin
     if(!busy) begin
       tx<=1;
       if(send) begin
         busy<=1;frame<={1'b1,data,1'b0};timer<=DIVISOR-1;bit_idx<=0;tx<=0;
       end
     end else if(timer==0) begin
       if(bit_idx==9) begin busy<=0;tx<=1;end
       else begin
         bit_idx<=bit_idx+1;tx<=frame[bit_idx+1];timer<=DIVISOR-1;
       end
     end else timer<=timer-1;
   end
 end
endmodule
