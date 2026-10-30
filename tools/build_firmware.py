from pathlib import Path
import argparse
from rv32i_assembler import (Program, lui, addi, andi, lw, sw, beq, jal)

BASE_PC=0x80000000

def rr(rd,rs1,rs2,f3):
    assert all(0<=i<32 for i in (rd,rs1,rs2))
    return (rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x33

def ori_regs(rd,rs1,rs2):return rr(rd,rs1,rs2,6)

def shift_imm(rd,rs1,shamt,f3):
    assert 0<=shamt<32
    return (shamt<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x13

def slli(rd,rs1,shift):return shift_imm(rd,rs1,shift,1)
def srli(rd,rs1,shift):return shift_imm(rd,rs1,shift,5)
def jalr(rd,rs1,offset=0):
    assert -2048<=offset<=2047
    return ((offset&4095)<<20)|(rs1<<15)|(rd<<7)|0x67

def bne(rs1,rs2,delta):
    assert delta%2==0 and -4096<=delta<=4094
    v=delta&8191
    return (((v>>12)&1)<<31)|(((v>>5)&63)<<25)|(rs2<<20)|(rs1<<15)|(1<<12)|(((v>>1)&15)<<8)|(((v>>11)&1)<<7)|0x63

class Firmware(Program):
    def branch_ne(self,a,b,target,note):self.inst.append((('BNE',a,b,target),note))
    def call(self,target,note):self.inst.append((('CALL',target),note))
    def finish(self):
        output=[]
        for i,(item,note) in enumerate(self.inst):
            if not isinstance(item,tuple):output.append((item,note));continue
            if item[0]=='BEQ':w=beq(item[1],item[2],self.labels[item[3]]-4*i)
            elif item[0]=='BNE':w=bne(item[1],item[2],self.labels[item[3]]-4*i)
            elif item[0]=='CALL':w=jal(21,self.labels[item[1]]-4*i)
            elif item[0]=='JAL':w=jal(0,self.labels[item[1]]-4*i)
            else:raise ValueError(item)
            output.append((w,note))
        return output

p=Firmware()
p.add(lui(1,0x40000),'x1 UART MMIO base')
p.add(lui(2,0x40001),'x2 display/LED MMIO base')
p.add(lui(3,0x40003),'x3 SoC ID base')
p.add(lui(10,0x40002),'x10 PWM MMIO base')
p.add(lui(14,0x40004),'x14 accelerator MMIO base')
p.label('loop')
p.label('wait_cmd')
p.add(lw(4,12,1),'poll UART RX status')
p.add(andi(4,4,1),'RX valid?')
p.beq(4,0,'wait_cmd','wait for UART opcode')
p.add(lw(5,8,1),'pop opcode')
for command,label in [(0x4c,'led_set'),(0x52,'led_get'),(0x49,'soc_id'),(0x50,'pwm_command'),(0x4d,'matrix_command')]:
    p.add(addi(6,0,command),f'dispatch opcode {command:02x}')
    p.beq(5,6,label,f'if {command:02x} branch')
p.label('nak')
p.add(addi(7,0,0x15),'NAK unknown command or invalid PWM')
p.jump('reply','send NAK')
p.label('led_set')
p.label('led_arg')
p.add(lw(4,12,1),'LED RX status')
p.add(andi(4,4,1),'LED argument valid?')
p.beq(4,0,'led_arg','wait for LED arg')
p.add(lw(8,8,1),'LED argument pop')
p.add(andi(8,8,255),'low byte of LED value')
p.add(sw(8,4,2),'write LEDs')
p.jump('ack','ack LED update')
p.label('led_get')
p.add(lw(7,4,2),'read LED MMIO')
p.add(andi(7,7,255),'LED low byte')
p.jump('reply','respond LED')
p.label('soc_id')
p.add(lw(7,0,3),'read ID')
p.add(andi(7,7,255),'ID low byte')
p.jump('reply','respond ID')
p.label('pwm_command')
p.label('pwm_arg')
p.add(lw(4,12,1),'PWM RX status')
p.add(andi(4,4,1),'PWM argument valid?')
p.beq(4,0,'pwm_arg','wait for PWM profile')
p.add(lw(8,8,1),'pop PWM profile')
for profile,label in [(0,'pwm_off'),(1,'pwm_1k25'),(2,'pwm_4k50'),(3,'pwm_8k75')]:
    p.add(addi(6,0,profile),f'PWM profile {profile}')
    p.beq(8,6,label,f'branch PWM profile {profile}')
p.jump('nak','unknown PWM profile')
p.label('pwm_off')
p.add(addi(13,0,2),'PWM apply=1 enable=0')
p.add(sw(13,8,10),'disable PWM')
p.jump('ack','ACK PWM off')
for label,period,high in [('pwm_1k25',99999,25000),('pwm_4k50',24999,12500),('pwm_8k75',12499,9375)]:
    p.label(label)
    for rd,val in [(11,period),(12,high)]:
        upper=(val+2048)>>12;lower=val-(upper<<12)
        p.add(lui(rd,upper),f'{label} count upper')
        p.add(addi(rd,rd,lower),f'{label} count={val}')
    p.add(sw(11,0,10),f'{label} stage period')
    p.add(sw(12,4,10),f'{label} stage high')
    p.add(addi(13,0,3),'PWM apply=1 enable=1')
    p.add(sw(13,8,10),f'{label} apply')
    p.jump('ack',f'ACK {label}')




p.label('matrix_command')
p.add(addi(15,14,0x20),'A0 operand pointer')
p.add(addi(16,0,32),'32 matrix operand words')
p.label('matrix_operand_loop')
p.label('matrix_low_wait')
p.add(lw(4,12,1),'wait low RX status')
p.add(andi(4,4,1),'valid low?')
p.beq(4,0,'matrix_low_wait','poll low')
p.add(lw(17,8,1),'pop low byte')
p.label('matrix_high_wait')
p.add(lw(4,12,1),'wait high RX status')
p.add(andi(4,4,1),'valid high?')
p.beq(4,0,'matrix_high_wait','poll high')
p.add(lw(18,8,1),'pop high byte')
p.add(slli(18,18,8),'high byte to bits [15:8]')
p.add(ori_regs(19,17,18),'combine into signed-16 bit pattern')
p.add(sw(19,0,15),'write accelerator A/B operand')
p.add(addi(15,15,4),'advance operand pointer')
p.add(addi(16,16,-1),'decrement operand count')
p.branch_ne(16,0,'matrix_operand_loop','next matrix operand')
p.add(addi(19,0,3),'START=1 and W1C DONE/ERROR=1')
p.add(sw(19,0,14),'start matrix calculation')
p.label('matrix_wait_done')
p.add(lw(19,0,14),'read accelerator status')
p.add(andi(19,19,2),'DONE flag')
p.beq(19,0,'matrix_wait_done','poll accelerator DONE')
p.add(addi(7,0,0x06),'ACK calculation accepted and finished')
p.call('emit_byte','emit matrix ACK')
p.add(addi(15,14,0xa0),'point to result C0')
p.add(addi(16,0,16),'16 matrix result words')
p.label('matrix_result_loop')
p.add(lw(19,0,15),'read signed32 C result')
for i in range(4):
    p.add(andi(7,19,255),f'result byte {i} of 4')
    p.call('emit_byte',f'transmit result byte {i}')
    if i<3:p.add(srli(19,19,8),'advance result byte')
p.add(addi(15,15,4),'advance C pointer')
p.add(addi(16,16,-1),'decrement result count')
p.branch_ne(16,0,'matrix_result_loop','continue streaming C')
p.jump('loop','matrix transaction completed')

p.label('ack')
p.add(addi(7,0,0x06),'ACK regular command')
p.label('reply')
p.call('emit_byte','emit G5/G6 response')
p.jump('loop','persistent service')
p.label('emit_byte')
p.label('tx_ready')
p.add(lw(9,4,1),'poll UART TX status')
p.add(andi(9,9,1),'ready?')
p.beq(9,0,'tx_ready','wait TX ready')
p.add(sw(7,0,1),'send one response byte')
p.add(jalr(0,21,0),'return from UART emitter')

program=p.finish()
assert len(program)<250,len(program)
assert len(program)*4<16384
assert all(w!=0x00100073 for w,_ in program)
assert p.labels['loop']==20
for i,(w,_) in enumerate(program):
    op=w&0x7f
    if op==0x63:
        im=(((w>>31)&1)<<12)|(((w>>7)&1)<<11)|(((w>>25)&63)<<5)|(((w>>8)&15)<<1)
        if im&4096:im-=8192
        assert 4*i+im in p.labels.values(),('branch',i,im)
    elif op==0x6f:
        im=(((w>>31)&1)<<20)|(((w>>12)&255)<<12)|(((w>>20)&1)<<11)|(((w>>21)&1023)<<1)
        if im&(1<<20):im-=(1<<21)
        assert 4*i+im in p.labels.values(),('jal',i,im)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--verify',action='store_true');ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parent.parent)
    a=ap.parse_args()
    files={'boot_rom.mem':''.join(f'{w:08x}\n' for w,_ in program)}
    for n,s in files.items():
        dst=a.root/'firmware'/n
        if a.verify:
            if not dst.exists() or dst.read_bytes()!=s.encode('ascii'):raise SystemExit(f'SYNVEC FIRMWARE VERIFY FAILED: {n}')
        else:
            dst.parent.mkdir(parents=True,exist_ok=True)
            dst.write_bytes(s.encode('ascii'))
    print(f'SYNVEC FIRMWARE {"VERIFY PASS" if a.verify else "GENERATED"}: {len(program)} instructions, {len(program)*4} bytes, matrix full input/output protocol, branch targets checked')
