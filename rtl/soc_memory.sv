`timescale 1ns/1ps
`include "synvec_paths.svh"


module soc_memory #(
 parameter MEMFILE=`SYNVEC_ROM_PATH
) (
 input logic clk,reset_n,
 input logic if_en,input logic [31:0] if_addr,output logic [31:0] if_rdata,
 input logic d_en,d_we,input logic [31:0] d_addr,d_wdata,input logic [3:0] d_be,
 output logic [31:0] d_rdata,
 input logic retire_valid,
 input logic [15:0] switches,
 output logic [15:0] leds,
 output logic [31:0] display_value,
 input logic uart_in,
 output logic uart_out,pwm_out
);

 (* ram_style="block" *) logic [31:0] imem [0:4095];


 (* ram_style="block" *) logic [7:0] dmem_b0 [0:4095];
 (* ram_style="block" *) logic [7:0] dmem_b1 [0:4095];
 (* ram_style="block" *) logic [7:0] dmem_b2 [0:4095];
 (* ram_style="block" *) logic [7:0] dmem_b3 [0:4095];
 integer idx;
 initial begin
   for(idx=0;idx<4096;idx=idx+1) begin
     imem[idx]=32'b0;
     dmem_b0[idx]=8'b0;
     dmem_b1[idx]=8'b0;
     dmem_b2[idx]=8'b0;
     dmem_b3[idx]=8'b0;
   end
   $readmemh(MEMFILE,imem);
 end


 logic [31:0] imem_b_rdata, dmem_rdata, mmio_rdata_q;
 logic [1:0] response_select;
 always_comb begin
   case(response_select)
     2'd1: d_rdata=imem_b_rdata;
     2'd2: d_rdata=dmem_rdata;
     2'd3: d_rdata=mmio_rdata_q;
     default: d_rdata=32'b0;
   endcase
 end
 logic [31:0] led_reg,disp_reg,cycle_ctr,instret_ctr,bus_error_addr;
 logic bus_error;
 logic [31:0] pwm_period,pwm_high;
 logic pwm_enable;
 logic pwm_pending,pwm_bad,pwm_running;
 logic uart_ready,uart_overrun;

 logic [7:0] rx_data;
 logic rx_valid,rx_overrun,rx_framing_error,rx_busy;
 logic rx_pop,rx_clear_flags;
 (* ASYNC_REG="TRUE" *) logic [15:0] sw_sync1, sw_sync2;
 logic [31:0] mmio_read;
 logic mmio_bad,uart_request,pwm_apply;
 logic in_i,in_d,in_m;
 logic [11:0] romidx,ramidx;
 assign romidx=if_addr[13:2];
 assign ramidx=d_addr[13:2];
 assign in_i=(d_addr[31:14]==18'h20000);
 assign in_d=(d_addr[31:14]==18'h20001);
 assign in_m=(d_addr[31:16]==16'h4000);


 logic acc_sel,acc_bad,acc_busy,acc_done;
 logic [31:0] acc_rdata;
 assign acc_sel=(d_addr[31:8]==24'h400040);
 matmul4x4_mmio matmul(.clk(clk),.reset_n(reset_n),
     .req_en(d_en&&acc_sel),.req_we(d_we),.req_addr(d_addr[7:0]),
     .req_wdata(d_wdata),.req_rdata(acc_rdata),.req_bad(acc_bad),
     .busy(acc_busy),.done(acc_done));

 assign rx_pop=d_en&&!d_we&&in_m&&d_addr==32'h40000008;
 assign rx_clear_flags=d_en&&d_we&&in_m&&d_addr==32'h4000000c&&d_wdata[1];
 uart_rx #(.DIVISOR(868)) rx(.clk(clk),.reset_n(reset_n),
    .rx_serial(uart_in),.pop(rx_pop),.clear_flags(rx_clear_flags),
    .data(rx_data),.valid(rx_valid),.overrun(rx_overrun),
    .framing_error(rx_framing_error),.busy(rx_busy));
 assign uart_request=d_en&&d_we&&d_addr==32'h40000000;
 assign pwm_apply=d_en&&d_we&&d_addr==32'h40002008&&d_wdata[1];
 assign leds=led_reg[15:0];
 assign display_value=disp_reg;
 uart_tx uart(.clk(clk),.reset_n(reset_n),.send(uart_request&&uart_ready),.data(d_wdata[7:0]),.tx(uart_out),.ready(uart_ready));
 pwm_unit pwm(.clk(clk),.reset_n(reset_n),.apply(pwm_apply),
    .staged_period(pwm_period),.staged_high(pwm_high),.staged_enable(d_wdata[0]),
    .pending(pwm_pending),.bad_cfg(pwm_bad),.running(pwm_running),.pwm_out(pwm_out));
 always_comb begin
   mmio_read=0;mmio_bad=0;
   if(acc_sel) begin


     mmio_read=acc_rdata;
     mmio_bad=acc_bad;
   end else begin
     case(d_addr)
       32'h40000000: mmio_bad=!d_we;
       32'h40000004:mmio_read={30'b0,uart_overrun,uart_ready};
       32'h40000008:mmio_read={24'd0,rx_data};
       32'h4000000c:mmio_read={28'd0,rx_busy,rx_framing_error,rx_overrun,rx_valid};
       32'h40001000:mmio_read=disp_reg;
       32'h40001004:mmio_read=led_reg;
       32'h40001008:mmio_read={16'd0,sw_sync2};
       32'h40002000:mmio_read=pwm_period;
       32'h40002004:mmio_read=pwm_high;
       32'h40002008:mmio_read={31'd0,pwm_enable};
       32'h4000200c:mmio_read={29'd0,pwm_running,pwm_bad,pwm_pending};
       32'h40003000:mmio_read=32'ha9e70003;
       32'h40003004:mmio_read=cycle_ctr;
       32'h40003008:mmio_read=instret_ctr;
       32'h4000300c:mmio_read={31'd0,bus_error};
       32'h40003010:mmio_read=bus_error_addr;
       default:mmio_bad=1;
     endcase
     if(d_we) begin
       case(d_addr)
         32'h40000000,32'h40000004,32'h4000000c,32'h40001000,32'h40001004,
         32'h40002000,32'h40002004,32'h40002008,32'h4000300c: mmio_bad=0;
         default: mmio_bad=1;
       endcase
     end else begin
       if(d_addr==32'h40000000) mmio_bad=1;
     end
   end
 end

 always_ff @(posedge clk) begin
   if(if_en) if_rdata<=imem[romidx];
   if(d_en && !d_we && in_i) imem_b_rdata<=imem[ramidx];
 end



 always_ff @(posedge clk) begin
   if(d_en && in_d) begin
     if(d_we) begin
       if(d_be[0]) dmem_b0[ramidx]<=d_wdata[7:0];
       if(d_be[1]) dmem_b1[ramidx]<=d_wdata[15:8];
       if(d_be[2]) dmem_b2[ramidx]<=d_wdata[23:16];
       if(d_be[3]) dmem_b3[ramidx]<=d_wdata[31:24];
     end else begin
       dmem_rdata<={dmem_b3[ramidx],dmem_b2[ramidx],
                     dmem_b1[ramidx],dmem_b0[ramidx]};
     end
   end
 end

 always_ff @(posedge clk) begin
   if(d_en) begin
     if(!d_we && in_i) response_select<=2'd1;
     else if(!d_we && in_d) response_select<=2'd2;
     else if(!d_we && in_m) response_select<=2'd3;
     else response_select<=2'd0;
     if(!d_we && in_m) mmio_rdata_q<=mmio_read;
   end
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin
     led_reg<=0;disp_reg<=0;cycle_ctr<=0;instret_ctr<=0;bus_error<=0;bus_error_addr<=0;
     pwm_period<=99999;pwm_high<=50000;pwm_enable<=0;uart_overrun<=0;
     sw_sync1<=0;sw_sync2<=0;
   end else begin
     cycle_ctr<=cycle_ctr+1;
     if(retire_valid) instret_ctr<=instret_ctr+1;
     sw_sync1<=switches;sw_sync2<=sw_sync1;
     if(d_en && d_we && in_m) begin
       case(d_addr)
         32'h40000000:if(!uart_ready) uart_overrun<=1;
         32'h40000004:if(d_wdata[1]) uart_overrun<=0;
         32'h40001000:disp_reg<=d_wdata;
         32'h40001004:led_reg<=d_wdata;
         32'h40002000:pwm_period<=d_wdata;
         32'h40002004:pwm_high<=d_wdata;
         32'h40002008:pwm_enable<=d_wdata[0];
         32'h4000300c:if(d_wdata[0])begin bus_error<=0;bus_error_addr<=0;end
         default:begin end
       endcase
     end
     if(d_en && in_m && mmio_bad) begin
       if(!bus_error) bus_error_addr<=d_addr;
       bus_error<=1;
     end
   end
 end
endmodule
