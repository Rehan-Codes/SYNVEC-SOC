`timescale 1ns/1ps
module pwm_unit (
 input logic clk,reset_n,
 input logic apply,
 input logic [31:0] staged_period,staged_high,
 input logic staged_enable,
 output logic pending,bad_cfg,running,
 output logic pwm_out
);
 logic [31:0] active_period,active_high,shadow_period,shadow_high,cnt;
 logic active_enable,shadow_enable;
 logic config_ok;
 assign config_ok = staged_period>=1 && ({1'b0,staged_high} <= ({1'b0,staged_period}+33'd1));
 assign running=active_enable;
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin
     active_period<=99999;active_high<=50000;active_enable<=0;
     shadow_period<=99999;shadow_high<=50000;shadow_enable<=0;
     cnt<=0;pwm_out<=0;pending<=0;bad_cfg<=0;
   end else begin
     pwm_out<=active_enable && (cnt<active_high);
     if(active_enable) begin
       if(cnt>=active_period) cnt<=0;
       else cnt<=cnt+1;
     end else cnt<=0;
     if(pending && (!active_enable || cnt>=active_period)) begin
        active_period<=shadow_period;active_high<=shadow_high;active_enable<=shadow_enable;
        cnt<=0;pending<=0;
     end
     if(apply) begin
       bad_cfg<=!config_ok;
       if(config_ok) begin
         shadow_period<=staged_period;shadow_high<=staged_high;shadow_enable<=staged_enable;
         pending<=1;
       end
     end
   end
 end
endmodule
