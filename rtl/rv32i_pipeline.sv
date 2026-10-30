`timescale 1ns/1ps







module rv32i_pipeline (
    input  logic clk, reset_n,
    output logic if_en,
    output logic [31:0] if_addr,
    input  logic [31:0] if_rdata,
    output logic d_en, d_we,
    output logic [31:0] d_addr, d_wdata,
    output logic [3:0] d_be,
    input  logic [31:0] d_rdata,
    output logic fault_valid,
    output logic [3:0] fault_cause,
    output logic [31:0] fault_pc,
    output logic retire_valid,
    output logic [31:0] retire_pc, retire_insn, retire_rd_value,
    output logic [4:0] retire_rd
);
    localparam logic [3:0] K_LUI=0, K_AUIPC=1, K_JAL=2, K_JALR=3,
      K_BRANCH=4, K_LOAD=5, K_STORE=6, K_ALUI=7, K_ALUR=8,
      K_FENCE=9, K_SYS=10;
    localparam logic [31:0] RESET_PC=32'h80000000;




    logic [31:0] fetch_pc, issue_pc, id_pc;
    logic id_valid, id_bad_fetch;
    logic [31:0] id_insn, id_imm;
    logic [3:0] id_kind;
    logic id_legal, id_use_rs1, id_use_rs2;
    logic [4:0] id_rs1, id_rs2;
    assign id_insn=if_rdata;
    assign id_rs1=id_insn[19:15];
    assign id_rs2=id_insn[24:20];
    rv32i_decode id_decoder(.insn(id_insn),.kind(id_kind),.imm(id_imm),
                            .legal(id_legal),.use_rs1(id_use_rs1),
                            .use_rs2(id_use_rs2));


    logic [31:0] rf [0:31];
    logic [31:0] id_a, id_b;


    logic ex_valid, ex_fetch_fault, ex_legal;
    logic [31:0] ex_pc, ex_insn, ex_imm, ex_a_q, ex_b_q;
    logic [3:0] ex_kind;
    logic [4:0] ex_rs1, ex_rs2, ex_rd;


    logic mem_valid;
    logic [31:0] mem_pc, mem_insn, mem_result, mem_addr, mem_store_data;
    logic [3:0] mem_kind, mem_be;
    logic [4:0] mem_rd;



    logic wb_valid;
    logic [31:0] wb_pc, wb_insn, wb_result, wb_addr;
    logic [3:0] wb_kind;
    logic [4:0] wb_rd;
    logic [31:0] wb_value, wb_shifted;
    logic wb_writes, mem_writes, wb_fast_writes;

    logic [31:0] ex_a, ex_b, ex_src_b, ex_alu, ex_result;
    logic [31:0] ex_addr, ex_target, ex_store_data;
    logic [3:0] ex_be;
    logic ex_branch_take, ex_redirect, ex_fault;
    logic [3:0] ex_fault_cause;
    logic ex_bad_align, ex_bad_access;
    logic stall_load_use, fetch_issue, bad_issue_pc;
    logic fault_pending;
    logic [3:0] pending_cause;
    logic [31:0] pending_pc;

    assign wb_writes = wb_valid && wb_rd!=0 &&
          (wb_kind==K_LUI || wb_kind==K_AUIPC || wb_kind==K_JAL ||
           wb_kind==K_JALR || wb_kind==K_ALUI || wb_kind==K_ALUR ||
           wb_kind==K_LOAD);
    assign mem_writes = mem_valid && mem_rd!=0 &&
          (mem_kind==K_LUI || mem_kind==K_AUIPC || mem_kind==K_JAL ||
           mem_kind==K_JALR || mem_kind==K_ALUI || mem_kind==K_ALUR);




    assign wb_fast_writes = wb_writes && wb_kind!=K_LOAD;

    always_comb begin
        wb_shifted = d_rdata >> (wb_addr[1:0]*8);
        case (wb_insn[14:12])
          3'd0: wb_value={{24{wb_shifted[7]}},wb_shifted[7:0]};
          3'd1: wb_value={{16{wb_shifted[15]}},wb_shifted[15:0]};
          3'd2: wb_value=wb_shifted;
          3'd4: wb_value={24'd0,wb_shifted[7:0]};
          3'd5: wb_value={16'd0,wb_shifted[15:0]};
          default: wb_value=0;
        endcase
        if (wb_kind!=K_LOAD) wb_value=wb_result;
    end


    assign id_a = id_rs1==0 ? 32'd0 :
                  (wb_writes && wb_rd==id_rs1) ? wb_value : rf[id_rs1];
    assign id_b = id_rs2==0 ? 32'd0 :
                  (wb_writes && wb_rd==id_rs2) ? wb_value : rf[id_rs2];





    always_comb begin
        ex_a=ex_a_q;
        ex_b=ex_b_q;
        if (ex_rs1==0) ex_a=0;
        else if (mem_writes && mem_rd==ex_rs1) ex_a=mem_result;
        else if (wb_fast_writes && wb_rd==ex_rs1) ex_a=wb_result;
        if (ex_rs2==0) ex_b=0;
        else if (mem_writes && mem_rd==ex_rs2) ex_b=mem_result;
        else if (wb_fast_writes && wb_rd==ex_rs2) ex_b=wb_result;
    end

    always_comb begin
        ex_src_b=(ex_kind==K_ALUI)?ex_imm:ex_b;
        ex_alu=0;
        case (ex_insn[14:12])
          3'd0: ex_alu=(ex_kind==K_ALUR && ex_insn[30]) ? ex_a-ex_b : ex_a+ex_src_b;
          3'd1: ex_alu=ex_a << ex_src_b[4:0];
          3'd2: ex_alu=($signed(ex_a)<$signed(ex_src_b))?32'd1:32'd0;
          3'd3: ex_alu=(ex_a<ex_src_b)?32'd1:32'd0;
          3'd4: ex_alu=ex_a^ex_src_b;
          3'd5: begin


              if (ex_insn[30]) ex_alu=$signed(ex_a) >>> ex_src_b[4:0];
              else ex_alu=ex_a >> ex_src_b[4:0];
          end
          3'd6: ex_alu=ex_a|ex_src_b;
          3'd7: ex_alu=ex_a&ex_src_b;
          default: ex_alu=0;
        endcase
    end
    always_comb begin
        ex_branch_take=0;
        case (ex_insn[14:12])
          3'd0: ex_branch_take=(ex_a==ex_b);
          3'd1: ex_branch_take=(ex_a!=ex_b);
          3'd4: ex_branch_take=($signed(ex_a)<$signed(ex_b));
          3'd5: ex_branch_take=($signed(ex_a)>=$signed(ex_b));
          3'd6: ex_branch_take=(ex_a<ex_b);
          3'd7: ex_branch_take=(ex_a>=ex_b);
          default: ex_branch_take=0;
        endcase
        ex_target = (ex_kind==K_JALR) ? ((ex_a+ex_imm)&32'hfffffffe)
                                         : (ex_pc+ex_imm);
        ex_result=0;
        case (ex_kind)
          K_LUI: ex_result=ex_imm;
          K_AUIPC: ex_result=ex_pc+ex_imm;
          K_ALUI,K_ALUR: ex_result=ex_alu;
          K_JAL,K_JALR: ex_result=ex_pc+4;
          default: ex_result=0;
        endcase
        ex_addr=ex_a+ex_imm;
        ex_be=4'b1111;
        case (ex_insn[14:12])
          3'd0: ex_be=4'b0001 << ex_addr[1:0];
          3'd1: ex_be=4'b0011 << ex_addr[1:0];
          default: ex_be=4'b1111;
        endcase
        ex_store_data=ex_b << (ex_addr[1:0]*8);
    end


    always_comb begin
        ex_bad_align=0;
        ex_bad_access=0;
        if (ex_kind==K_LOAD || ex_kind==K_STORE) begin
            ex_bad_align=((ex_insn[14:12]==3'd1 || ex_insn[14:12]==3'd5)
                          && ex_addr[0]) ||
                         (ex_insn[14:12]==3'd2 && ex_addr[1:0]!=0);
            if (ex_kind==K_LOAD)
                ex_bad_access=!(ex_addr[31:14]==18'h20000 ||
                                ex_addr[31:14]==18'h20001 ||
                                ex_addr[31:16]==16'h4000) ||
                                (ex_addr[31:16]==16'h4000 && ex_insn[14:12]!=3'd2);
            else
                ex_bad_access=!(ex_addr[31:14]==18'h20001 ||
                                ex_addr[31:16]==16'h4000) ||
                                (ex_addr[31:16]==16'h4000 && ex_insn[14:12]!=3'd2);
        end
        ex_fault=0;
        ex_fault_cause=0;
        if (ex_valid) begin
            if (ex_fetch_fault) begin
                ex_fault=1;
                ex_fault_cause=(ex_pc[1:0]!=0)?4'd0:4'd1;
            end else if (!ex_legal) begin
                ex_fault=1;ex_fault_cause=4'd2;
            end else if (ex_kind==K_SYS) begin
                ex_fault=1;
                ex_fault_cause=(ex_insn==32'h00100073)?4'd3:4'd11;
            end else if ((ex_kind==K_JAL || ex_kind==K_JALR ||
                          (ex_kind==K_BRANCH && ex_branch_take)) &&
                         ex_target[1:0]!=0) begin
                ex_fault=1;ex_fault_cause=4'd0;
            end else if ((ex_kind==K_LOAD || ex_kind==K_STORE) &&
                         (ex_bad_align || ex_bad_access)) begin
                ex_fault=1;
                if (ex_bad_align) ex_fault_cause=(ex_kind==K_LOAD)?4'd4:4'd6;
                else ex_fault_cause=(ex_kind==K_LOAD)?4'd5:4'd7;
            end
        end
    end




    assign ex_redirect=ex_valid && !ex_fetch_fault && ex_legal &&
            (ex_kind==K_JAL || ex_kind==K_JALR ||
             (ex_kind==K_BRANCH && ex_branch_take)) &&
            (ex_target[1:0]==2'b00);





    assign stall_load_use=id_valid && (
            (ex_valid && ex_kind==K_LOAD && ex_rd!=0 &&
             ((id_use_rs1 && id_rs1==ex_rd) ||
              (id_use_rs2 && id_rs2==ex_rd))) ||
            (mem_valid && mem_kind==K_LOAD && mem_rd!=0 &&
             ((id_use_rs1 && id_rs1==mem_rd) ||
              (id_use_rs2 && id_rs2==mem_rd)))
            );








    assign issue_pc=fetch_pc;
    assign bad_issue_pc=(issue_pc[1:0]!=0 || issue_pc[31:14]!=18'h20000);
    assign fetch_issue=reset_n && !fault_pending && !fault_valid &&
                       !stall_load_use;
    assign if_en=fetch_issue && !bad_issue_pc;
    assign if_addr=issue_pc;

    assign d_en=mem_valid && (mem_kind==K_LOAD || mem_kind==K_STORE) && reset_n;
    assign d_we=d_en && mem_kind==K_STORE;
    assign d_addr=mem_addr;
    assign d_wdata=mem_store_data;
    assign d_be=mem_be;

    integer r;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            fetch_pc<=RESET_PC;
            id_valid<=0;id_bad_fetch<=0;id_pc<=0;
            ex_valid<=0;ex_fetch_fault<=0;ex_legal<=0;
            ex_pc<=0;ex_insn<=0;ex_imm<=0;ex_kind<=0;
            ex_a_q<=0;ex_b_q<=0;ex_rs1<=0;ex_rs2<=0;ex_rd<=0;
            mem_valid<=0;mem_pc<=0;mem_insn<=0;mem_result<=0;
            mem_addr<=0;mem_store_data<=0;mem_be<=0;mem_kind<=0;mem_rd<=0;
            wb_valid<=0;wb_pc<=0;wb_insn<=0;wb_result<=0;
            wb_addr<=0;wb_kind<=0;wb_rd<=0;
            fault_pending<=0;pending_cause<=0;pending_pc<=0;
            fault_valid<=0;fault_cause<=0;fault_pc<=0;
            retire_valid<=0;retire_pc<=0;retire_insn<=0;
            retire_rd<=0;retire_rd_value<=0;
            for (r=0;r<32;r=r+1) rf[r]<=0;
        end else begin
            retire_valid<=wb_valid;
            if (wb_valid) begin
                retire_pc<=wb_pc;
                retire_insn<=wb_insn;
                retire_rd<=wb_rd;
                retire_rd_value<=wb_rd==0 ? 32'd0 : wb_value;
                if (wb_writes) rf[wb_rd]<=wb_value;
            end


            wb_valid<=mem_valid;
            wb_pc<=mem_pc;wb_insn<=mem_insn;wb_kind<=mem_kind;
            wb_result<=mem_result;wb_addr<=mem_addr;wb_rd<=mem_rd;

            mem_valid<=ex_valid && !ex_fault;
            mem_pc<=ex_pc;mem_insn<=ex_insn;mem_kind<=ex_kind;
            mem_rd<= (ex_kind==K_LUI || ex_kind==K_AUIPC ||
                     ex_kind==K_JAL || ex_kind==K_JALR ||
                     ex_kind==K_ALUI || ex_kind==K_ALUR ||
                     ex_kind==K_LOAD) ? ex_rd : 5'd0;
            mem_result<=ex_result;
            mem_addr<=ex_addr;mem_store_data<=ex_store_data;mem_be<=ex_be;





            ex_fetch_fault<=id_bad_fetch;
            ex_legal<=id_legal;
            ex_pc<=id_pc;ex_insn<=id_insn;
            ex_kind<=id_kind;ex_imm<=id_imm;
            ex_rs1<=id_rs1;ex_rs2<=id_rs2;ex_rd<=id_insn[11:7];
            ex_a_q<=id_a;ex_b_q<=id_b;

            if (ex_fault) begin
                ex_valid<=0;
                id_valid<=0;
                fault_pending<=1;
                pending_cause<=ex_fault_cause;
                pending_pc<=ex_pc;
            end else if (ex_redirect) begin
                ex_valid<=0;


                id_valid<=0;
                id_bad_fetch<=0;
                fetch_pc<=ex_target;
            end else if (stall_load_use) begin
                ex_valid<=0;
            end else begin
                ex_valid<=id_valid && !fault_pending && !fault_valid;
                id_valid<=fetch_issue;
                id_bad_fetch<=bad_issue_pc;
                id_pc<=issue_pc;
                if (fetch_issue) fetch_pc<=issue_pc+4;
            end

            if (fault_pending && !mem_valid && !wb_valid) begin
                fault_valid<=1;
                fault_cause<=pending_cause;
                fault_pc<=pending_pc;
            end
        end
    end
endmodule
