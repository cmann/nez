const std = @import("std");
const fs = std.fs;
const process = std.process;

var a: *std.mem.Allocator = undefined;

const StatusRegister = packed union {
    p: u8,
    flags: packed struct {
        c: bool,
        z: bool,
        i: bool,
        d: bool,
        b: bool,
        u: bool,
        v: bool,
        n: bool,
    },
};

const Registers = struct {
    pc: u16,
    sp: u8,
    p: u8,
    a: u8,
    x: u8,
    y: u8,
};

const Context = struct {
    registers: Registers,
    memory: []u8,

    pub fn init() Context {
        return Context{
            .registers = Registers{
                .pc = 0,
                .sp = 0xFD,
                .p = 0x34,
                .a = 0,
                .x = 0,
                .y = 0,
            },
            .memory = [_]u8{0} ** 0x10000,
        };
    }
};

const Instruction = enum {
    ADC,
    AND,
    ASL,
    BCC,
    BCS,
    BEQ,
    BIT,
    BMI,
    BNE,
    BPL,
    BRK,
    BVC,
    BVS,
    CLC,
    CLD,
    CLI,
    CLV,
    CMP,
    CPX,
    CPY,
    DEC,
    DEX,
    DEY,
    EOR,
    INC,
    INX,
    INY,
    JMP,
    JSR,
    LDA,
    LDX,
    LDY,
    LSR,
    NOP,
    ORA,
    PHA,
    PHP,
    PLA,
    PLP,
    ROL,
    ROR,
    RTI,
    RTS,
    SBC,
    SEC,
    SED,
    SEI,
    STA,
    STX,
    STY,
    TAX,
    TAY,
    TSX,
    TXA,
    TXS,
    TYA,
};

const AddressMode = union(enum) {
    // Non-indexed, non-memory
    Accumulator: void,
    Immediate: u8,
    Implied: void,
    // Non-indexed, memory
    Relative: u8,
    Absolute: u16,
    ZeroPage: u8,
    Indirect,
    // Indexed, memory
    AbsoluteX: u16,
    AbsoluteY: u16,
    ZeroPageX: u8,
    ZeroPageY: u8,
    IndexedIndirect: u8,
    IndirectIndexed: u8,

    pub fn load(self: AddressMode, context: Context) ![]u8 {
        const val = switch (self) {
            .Accumulator => context.registers.a,
            .Immediate => context.memory[context.registers.pc + 1],
            .Relative => context.registers.pc + @bitCast(i8, context.memory[context.registers.pc + 1]),
            .Absolute => context.memory[context.memory[context.registers.pc + 1] + context.memory[context.registers.pc + 2]],
            .ZeroPage => context.memory[context.memory[context.registers.pc + 1]],

            .Implied => 0xff,
        };
    }
};

const DecodeError = error{InvalidOpcode};

pub fn decode(opcode: u8, lo: u8, hi: u8) !Instruction {
    return switch (opcode) {
        0x00 => .BRK,
        0x01 => .ORA,
        0x05 => .ORA,
        0x06 => .ASL,
        0x08 => .PHP,
        0x09 => .ORA,
        0x0A => .ASL,
        0x0D => .ORA,
        0x0E => .ASL,
        0x10 => .BPL,
        0x11 => .ORA,
        0x15 => .ORA,
        0x16 => .ASL,
        0x18 => .CLC,
        0x19 => .ORA,
        0x1D => .ORA,
        0x1E => .ASL,
        0x20 => .JSR,
        0x21 => .AND,
        0x24 => .BIT,
        0x25 => .AND,
        0x26 => .ROL,
        0x28 => .PLP,
        0x29 => .AND,
        0x2A => .ROL,
        0x2C => .BIT,
        0x2D => .AND,
        0x2E => .ROL,
        0x30 => .BMI,
        0x31 => .AND,
        0x35 => .AND,
        0x36 => .ROL,
        0x38 => .SEC,
        0x39 => .AND,
        0x3D => .AND,
        0x3E => .ROL,
        0x40 => .RTI,
        0x41 => .EOR,
        0x45 => .EOR,
        0x46 => .LSR,
        0x48 => .PHA,
        0x49 => .EOR,
        0x4A => .LSR,
        0x4C => .JMP,
        0x4D => .EOR,
        0x4E => .LSR,
        0x50 => .BVC,
        0x51 => .EOR,
        0x55 => .EOR,
        0x56 => .LSR,
        0x58 => .CLI,
        0x59 => .EOR,
        0x5D => .EOR,
        0x5E => .LSR,
        0x60 => .RTS,
        0x61 => .ADC,
        0x65 => .ADC,
        0x66 => .ROR,
        0x68 => .PLA,
        0x69 => .ADC,
        0x6A => .ROR,
        0x6C => .JMP,
        0x6D => .ADC,
        0x6E => .ROR,
        0x70 => .BVS,
        0x71 => .ADC,
        0x75 => .ADC,
        0x76 => .ROR,
        0x78 => .SEI,
        0x79 => .ADC,
        0x7D => .ADC,
        0x7E => .ROR,
        0x81 => .STA,
        // 0x83 => .SAX,
        0x84 => .STY,
        0x85 => .STA,
        0x86 => .STX,
        // 0x87 => .SAX,
        0x88 => .DEY,
        0x8A => .TXA,
        0x8C => .STY,
        0x8D => .STA,
        0x8E => .STX,
        // 0x8F => .SAX,
        0x90 => .BCC,
        0x91 => .STA,
        0x94 => .STY,
        0x95 => .STA,
        0x96 => .STX,
        // 0x97 => .SAX,
        0x98 => .TYA,
        0x99 => .STA,
        0x9A => .TXS,
        0x9D => .STA,
        0xA0 => .LDY,
        0xA1 => .LDA,
        0xA2 => .LDX,
        // 0xA3 => .LAX,
        0xA4 => .LDY,
        0xA5 => .LDA,
        0xA6 => .LDX,
        // 0xA7 => .LAX,
        0xA8 => .TAY,
        0xA9 => .LDA,
        0xAA => .TAX,
        0xAC => .LDY,
        0xAD => .LDA,
        0xAE => .LDX,
        // 0xAF => .LAX,
        0xB0 => .BCS,
        0xB1 => .LDA,
        // 0xB3 => .LAX,
        0xB4 => .LDY,
        0xB5 => .LDA,
        0xB6 => .LDX,
        // 0xB7 => .LAX,
        0xB8 => .CLV,
        0xB9 => .LDA,
        0xBA => .TSX,
        0xBC => .LDY,
        0xBD => .LDA,
        0xBE => .LDX,
        // 0xBF => .LAX,
        0xC0 => .CPY,
        0xC1 => .CMP,
        0xC4 => .CPY,
        0xC5 => .CMP,
        0xC6 => .DEC,
        0xC8 => .INY,
        0xC9 => .CMP,
        0xCA => .DEX,
        // 0xCB => .AXS,
        0xCC => .CPY,
        0xCD => .CMP,
        0xCE => .DEC,
        0xD0 => .BNE,
        0xD1 => .CMP,
        0xD5 => .CMP,
        0xD6 => .DEC,
        0xD8 => .CLD,
        0xD9 => .CMP,
        0xDD => .CMP,
        0xDE => .DEC,
        0xE0 => .CPX,
        0xE1 => .SBC,
        0xE4 => .CPX,
        0xE5 => .SBC,
        0xE6 => .INC,
        0xE8 => .INX,
        0xE9 => .SBC,
        0xEA => .NOP,
        0xEC => .CPX,
        0xED => .SBC,
        0xEE => .INC,
        0xF0 => .BEQ,
        0xF1 => .SBC,
        0xF5 => .SBC,
        0xF6 => .INC,
        0xF8 => .SED,
        0xF9 => .SBC,
        0xFD => .SBC,
        0xFE => .INC,
        else => DecodeError.InvalidOpcode,
    };
}

pub fn main() !void {
    a = std.heap.c_allocator;

    var args = process.args();
    _ = args.skip();

    const bin_path = try (args.next(a) orelse {
        return error.InvalidArgs;
    });
    defer a.free(bin_path);

    const bin = try (fs.cwd().readFileAlloc(a, bin_path, 1024 * 100));
    defer a.free(bin);

    var i: usize = 0x0400;
    while (i < 0x3399) : (i += 1) {
        const opcode = bin[i];
        const lo = bin[i + 1];
        const hi = bin[i + 2];

        std.debug.warn("{}\n", .{decode(opcode, lo, hi)});
    }

    const mode = AddressMode.Absolute;
    // mode.load();
}
