`timescale 1ns/1ps


module sevenseg (
 input logic clk,reset_n,
 input logic [31:0] value,
 input logic fault,
 input logic [3:0] cause,
 output logic [6:0] seg,
 output logic [3:0] an
);
 logic [31:0] seen;
 logic [13:0] shiftmag;
 logic [15:0] bcd,bcd_done;
 logic [3:0] step;
 logic working,negative,valid_number;
 logic [16:0] refresh;
 logic [1:0] digit;
 logic [3:0] shown;
 logic [15:0] bcd_temp;
 integer k;
 always_comb begin
   bcd_temp=bcd;
   for(integer n=0;n<4;n=n+1) begin
     if(bcd_temp[n*4 +:4]>=5) bcd_temp[n*4 +:4]=bcd_temp[n*4 +:4]+4'd3;
   end
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin
     seen<=0;shiftmag<=0;bcd<=0;bcd_done<=0;step<=0;working<=0;
     negative<=0;valid_number<=1;refresh<=0;digit<=0;
   end else begin
     if(refresh==17'd99999) begin refresh<=0;digit<=digit+1;end
     else refresh<=refresh+1;
     if(value!=seen && !working) begin
       seen<=value;bcd<=0;step<=0;
       negative<=($signed(value)<0);
       valid_number<=($signed(value)>=-999 && $signed(value)<=9999);
       if($signed(value)<0) shiftmag<=-value[13:0];
       else shiftmag<=value[13:0];
       working<=1;
     end else if(working) begin
       bcd <= {bcd_temp[14:0],shiftmag[13]};
       shiftmag<=shiftmag<<1;
       if(step==13) begin
         bcd_done<={bcd_temp[14:0],shiftmag[13]};
         working<=0;
       end else step<=step+1;
     end
   end
 end
 always_comb begin
   an=~(4'b0001<<digit);
   shown=4'hf;
   if(fault) begin
     if(digit==3) shown=4'he;
     else if(digit==0) shown=cause;
   end else if(!valid_number) shown=4'hd;
   else if(negative && digit==3) shown=4'hd;
   else if(negative && digit==2 && bcd_done[11:8]==0) shown=4'hf;
   else if(!negative && digit==3 && bcd_done[15:12]==0) shown=4'hf;
   else if(digit==2 && bcd_done[11:8]==0 && bcd_done[15:12]==0 && !negative) shown=4'hf;
   else if(digit==1 && bcd_done[7:4]==0 && bcd_done[11:8]==0 && bcd_done[15:12]==0 && !negative) shown=4'hf;
   else shown=bcd_done[4*digit +:4];
   case(shown)
     0:seg=7'b1000000;1:seg=7'b1111001;2:seg=7'b0100100;3:seg=7'b0110000;
     4:seg=7'b0011001;5:seg=7'b0010010;6:seg=7'b0000010;7:seg=7'b1111000;
     8:seg=7'b0000000;9:seg=7'b0010000;
     4'he:seg=7'b0000110;
     4'hd:seg=7'b0111111;
     default:seg=7'b1111111;
   endcase
 end
endmodule
