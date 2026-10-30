`timescale 1ns/1ps




module matmul4x4_mmio (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        req_en,
    input  logic        req_we,
    input  logic [7:0]  req_addr,
    input  logic [31:0] req_wdata,
    output logic [31:0] req_rdata,
    output logic        req_bad,
    output logic        busy,
    output logic        done
);


    logic signed [15:0] a [0:15];
    logic signed [15:0] b [0:15];
    logic [31:0] c [0:15];
    logic error_sticky;
    logic [1:0] row, col, inner;
    logic [31:0] accumulator;
    logic signed [31:0] product;
    logic [31:0] sum;
    logic [3:0] operand_a_index, operand_b_index, result_index;
    logic [3:0] word_index;
    logic a_addr, b_addr, c_addr, status_addr, id_addr;

    assign operand_a_index = {row,inner};
    assign operand_b_index = {inner,col};
    assign result_index = {row,col};
    assign product = $signed(a[operand_a_index]) * $signed(b[operand_b_index]);
    assign sum = accumulator + $unsigned(product);

    always_comb begin
        status_addr=(req_addr==8'h00);
        id_addr=(req_addr==8'h04);
        a_addr=(req_addr>=8'h20 && req_addr<=8'h5c && req_addr[1:0]==2'b00);
        b_addr=(req_addr>=8'h60 && req_addr<=8'h9c && req_addr[1:0]==2'b00);
        c_addr=(req_addr>=8'ha0 && req_addr<=8'hdc && req_addr[1:0]==2'b00);
        word_index=4'd0;
        req_rdata=32'd0;
        req_bad=1'b0;
        if(status_addr) begin
            req_rdata={29'd0,error_sticky,done,busy};
            if(req_we && busy && req_wdata[0]) req_bad=1'b1;
        end else if(id_addr) begin
            req_rdata=32'h0001_0040;
            if(req_we) req_bad=1'b1;
        end else if(a_addr) begin
            word_index=(req_addr-8'h20)>>2;
            req_rdata={{16{a[word_index][15]}},a[word_index]};
            if(req_we && busy) req_bad=1'b1;
        end else if(b_addr) begin
            word_index=(req_addr-8'h60)>>2;
            req_rdata={{16{b[word_index][15]}},b[word_index]};
            if(req_we && busy) req_bad=1'b1;
        end else if(c_addr) begin
            word_index=(req_addr-8'ha0)>>2;
            req_rdata=c[word_index];
            if(req_we) req_bad=1'b1;
        end else begin
            req_bad=1'b1;
        end
    end

    integer i;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy<=1'b0;
            done<=1'b0;
            error_sticky<=1'b0;
            row<=2'd0;
            col<=2'd0;
            inner<=2'd0;
            accumulator<=32'd0;
            for (i=0;i<16;i=i+1) begin
                a[i]<=16'sd0;
                b[i]<=16'sd0;
                c[i]<=32'd0;
            end
        end else begin

            if (busy) begin
                if (inner==2'd3) begin
                    c[result_index]<=sum;
                    accumulator<=32'd0;
                    inner<=2'd0;
                    if(col==2'd3) begin
                        col<=2'd0;
                        if(row==2'd3) begin
                            busy<=1'b0;
                            done<=1'b1;
                        end else row<=row+2'd1;
                    end else col<=col+2'd1;
                end else begin
                    accumulator<=sum;
                    inner<=inner+2'd1;
                end
            end
            if(req_en && req_we) begin
                if(req_bad) begin
                    error_sticky<=1'b1;
                end else if(status_addr) begin

                    if (req_wdata[1]) begin
                        done<=1'b0;
                        error_sticky<=1'b0;
                    end

                    if (req_wdata[0]) begin
                        busy<=1'b1;
                        done<=1'b0;
                        row<=2'd0;
                        col<=2'd0;
                        inner<=2'd0;
                        accumulator<=32'd0;
                        for(i=0;i<16;i=i+1) c[i]<=32'd0;
                    end
                end else if(a_addr) begin
                    a[word_index]<=req_wdata[15:0];
                end else if(b_addr) begin
                    b[word_index]<=req_wdata[15:0];
                end
            end
        end
    end
endmodule
