def reg(n):
    assert isinstance(n, int) and 0 <= n < 32


def sign(n, bits):
    assert -(1 << (bits - 1)) <= n < (1 << (bits - 1)), (n, bits)
    return n & ((1 << bits) - 1)


def lui(rd, upper):
    reg(rd); assert 0 <= upper < (1 << 20)
    return (upper << 12) | (rd << 7) | 0x37


def addi(rd, rs1, imm):
    reg(rd); reg(rs1)
    return (sign(imm, 12) << 20) | (rs1 << 15) | (rd << 7) | 0x13


def andi(rd, rs1, imm):
    reg(rd); reg(rs1)
    return (sign(imm, 12) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13


def lw(rd, offset, rs1):
    reg(rd); reg(rs1)
    return (sign(offset, 12) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03


def sw(rs2, offset, rs1):
    reg(rs1); reg(rs2)
    v = sign(offset, 12)
    return ((v >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | ((v & 31) << 7) | 0x23


def beq(rs1, rs2, delta):
    reg(rs1); reg(rs2)
    assert delta % 2 == 0
    v = sign(delta, 13)
    return (((v >> 12) & 1) << 31) | (((v >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (((v >> 1) & 15) << 8) | (((v >> 11) & 1) << 7) | 0x63


def jal(rd, delta):
    reg(rd)
    assert delta % 2 == 0
    v = sign(delta, 21)
    return (((v >> 20) & 1) << 31) | (((v >> 1) & 1023) << 21) | (((v >> 11) & 1) << 20) | (((v >> 12) & 255) << 12) | (rd << 7) | 0x6f


class Program:
    def __init__(self):
        self.inst = []; self.labels = {}
    def label(self, name):
        assert name not in self.labels
        self.labels[name] = 4 * len(self.inst)
    def add(self, word, note):
        self.inst.append((word, note))
    def beq(self, a, b, target, note):
        self.inst.append((('BEQ', a, b, target), note))
    def jump(self, target, note):
        self.inst.append((('JAL', target), note))
    def finish(self):
        result=[]
        for i,(item,note) in enumerate(self.inst):
            if isinstance(item,tuple):
                if item[0]=='BEQ':
                    _,a,b,target = item
                    word=beq(a,b,self.labels[target]-4*i)
                else:
                    _,target = item
                    word=jal(0,self.labels[target]-4*i)
            else:
                word=item
            result.append((word,note))
        return result
