`timescale 1ns/1ps

module rv32i_decode (
    input  logic [31:0] insn,
    output logic [3:0] kind,
    output logic [31:0] imm,
    output logic legal,
    output logic use_rs1, use_rs2
);
    localparam logic [3:0]
        K_LUI=0, K_AUIPC=1, K_JAL=2, K_JALR=3,
        K_BRANCH=4, K_LOAD=5, K_STORE=6, K_ALUI=7,
        K_ALUR=8, K_FENCE=9, K_SYS=10, K_BAD=15;
    logic [6:0] opc, f7;
    logic [2:0] f3;
    assign opc=insn[6:0];
    assign f3=insn[14:12];
    assign f7=insn[31:25];
    always_comb begin
        kind=K_BAD; legal=1'b0; use_rs1=1'b0; use_rs2=1'b0;
        imm=32'b0;
        if (insn[1:0]==2'b11) begin
            case (opc)
                7'h37: begin kind=K_LUI;legal=1;imm={insn[31:12],12'b0}; end
                7'h17: begin kind=K_AUIPC;legal=1;imm={insn[31:12],12'b0}; end
                7'h6f: begin
                    kind=K_JAL;legal=1;
                    imm={{11{insn[31]}}, insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
                end
                7'h67: begin
                    kind=K_JALR; legal=(f3==0);use_rs1=legal;
                    imm={{20{insn[31]}},insn[31:20]};
                end
                7'h63: begin
                    kind=K_BRANCH;legal=(f3==0||f3==1||f3==4||f3==5||f3==6||f3==7);
                    use_rs1=legal;use_rs2=legal;
                    imm={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
                end
                7'h03: begin
                    kind=K_LOAD;legal=(f3==0||f3==1||f3==2||f3==4||f3==5);
                    use_rs1=legal;imm={{20{insn[31]}},insn[31:20]};
                end
                7'h23: begin
                    kind=K_STORE;legal=(f3==0||f3==1||f3==2);use_rs1=legal;use_rs2=legal;
                    imm={{20{insn[31]}},insn[31:25],insn[11:7]};
                end
                7'h13: begin
                    kind=K_ALUI;use_rs1=1;
                    imm={{20{insn[31]}},insn[31:20]};
                    case(f3)
                        0,2,3,4,6,7: legal=1;
                        1: legal=(f7==0);
                        5: legal=(f7==0 || f7==7'h20);
                        default: legal=0;
                    endcase
                    use_rs1=legal;
                end
                7'h33: begin
                    kind=K_ALUR;use_rs1=1;use_rs2=1;
                    case(f3)
                        0,5: legal=(f7==0 || f7==7'h20);
                        1,2,3,4,6,7: legal=(f7==0);
                        default: legal=0;
                    endcase
                    use_rs1=legal;use_rs2=legal;
                end
                7'h0f: begin kind=K_FENCE;legal=(f3==0); end
                7'h73: begin kind=K_SYS;legal=(insn==32'h00000073 || insn==32'h00100073); end
                default: begin end
            endcase
        end
        if (!legal) begin kind=K_BAD;use_rs1=0;use_rs2=0;end
    end
endmodule
