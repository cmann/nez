const std = @import("std");
const fs = std.fs;
const process = std.process;

var a: *std.mem.Allocator = undefined;

const DecodeError = error{InvalidOpcode};

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

const InstructionType = enum {
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
    Indirect: u16,
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
            else => 0x00,
        };
    }
};

const Instruction = struct {
    type: InstructionType,
    mode: AddressMode,
};

pub fn decode(opcode: u8, lo: u8, hi: u8) !Instruction {
    return switch (opcode) {
        0x00 => Instruction{ .type = .BRK, .mode = AddressMode{ .Implied = .{} } },
        0x01 => Instruction{ .type = .ORA, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0x05 => Instruction{ .type = .ORA, .mode = AddressMode{ .ZeroPage = .{} } },
        0x06 => Instruction{ .type = .ASL, .mode = AddressMode{ .ZeroPage = .{} } },
        0x08 => Instruction{ .type = .PHP, .mode = AddressMode{ .Implied = .{} } },
        0x09 => Instruction{ .type = .ORA, .mode = AddressMode{ .Immediate = .{} } },
        0x0A => Instruction{ .type = .ASL, .mode = AddressMode{ .Accumulator = .{} } },
        0x0D => Instruction{ .type = .ORA, .mode = AddressMode{ .Absolute = .{} } },
        0x0E => Instruction{ .type = .ASL, .mode = AddressMode{ .Absolute = .{} } },
        0x10 => Instruction{ .type = .BPL, .mode = AddressMode{ .Relative = .{} } },
        0x11 => Instruction{ .type = .ORA, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0x15 => Instruction{ .type = .ORA, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x16 => Instruction{ .type = .ASL, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x18 => Instruction{ .type = .CLC, .mode = AddressMode{ .Implied = .{} } },
        0x19 => Instruction{ .type = .ORA, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x1D => Instruction{ .type = .ORA, .mode = AddressMode{ .AbsoluteX  = .{} } },
        0x1E => Instruction{ .type = .ASL, .mode = AddressMode{ .AbsoluteX  = .{} } },
        0x20 => Instruction{ .type = .JSR, .mode = AddressMode{ .Absolute = .{} } },
        0x21 => Instruction{ .type = .AND, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0x24 => Instruction{ .type = .BIT, .mode = AddressMode{ .ZeroPage = .{} } },
        0x25 => Instruction{ .type = .AND, .mode = AddressMode{ .ZeroPage = .{} } },
        0x26 => Instruction{ .type = .ROL, .mode = AddressMode{ .ZeroPage = .{} } },
        0x28 => Instruction{ .type = .PLP, .mode = AddressMode{ .Implied = .{} } },
        0x29 => Instruction{ .type = .AND, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x2A => Instruction{ .type = .ROL, .mode = AddressMode{ .Accumulator = .{} } },
        0x2C => Instruction{ .type = .BIT, .mode = AddressMode{ .Absolute = .{} } },
        0x2D => Instruction{ .type = .AND, .mode = AddressMode{ .Absolute = .{} } },
        0x2E => Instruction{ .type = .ROL, .mode = AddressMode{ .Absolute = .{} } },
        0x30 => Instruction{ .type = .BMI, .mode = AddressMode{ .Relative = .{} } },
        0x31 => Instruction{ .type = .AND, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0x35 => Instruction{ .type = .AND, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x36 => Instruction{ .type = .ROL, .mode = AddressMode{ .ZeroPageX  = .{} } },
        0x38 => Instruction{ .type = .SEC, .mode = AddressMode{ .Implied = .{} } },
        0x39 => Instruction{ .type = .AND, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x3D => Instruction{ .type = .AND, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x3E => Instruction{ .type = .ROL, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x40 => Instruction{ .type = .RTI, .mode = AddressMode{ .Implied = .{} } },
        0x41 => Instruction{ .type = .EOR, .mode = AddressMode{ .Indirect = .{} } },
        0x45 => Instruction{ .type = .EOR, .mode = AddressMode{ .ZeroPage = .{} } },
        0x46 => Instruction{ .type = .LSR, .mode = AddressMode{ .ZeroPage = .{} } },
        0x48 => Instruction{ .type = .PHA, .mode = AddressMode{ .Implied = .{} } },
        0x49 => Instruction{ .type = .EOR, .mode = AddressMode{ .Immediate = .{} } },
        0x4A => Instruction{ .type = .LSR, .mode = AddressMode{ .Accumulator = .{} } },
        0x4C => Instruction{ .type = .JMP, .mode = AddressMode{ .Absolute = .{} } },
        0x4D => Instruction{ .type = .EOR, .mode = AddressMode{ .Absolute  = .{} } },
        0x4E => Instruction{ .type = .LSR, .mode = AddressMode{ .Absolute  = .{} } },
        0x50 => Instruction{ .type = .BVC, .mode = AddressMode{ .Relative = .{} } },
        0x51 => Instruction{ .type = .EOR, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0x55 => Instruction{ .type = .EOR, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x56 => Instruction{ .type = .LSR, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x58 => Instruction{ .type = .CLI, .mode = AddressMode{ .Implied = .{} } },
        0x59 => Instruction{ .type = .EOR, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x5D => Instruction{ .type = .EOR, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x5E => Instruction{ .type = .LSR, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x60 => Instruction{ .type = .RTS, .mode = AddressMode{ .Implied = .{} } },
        0x61 => Instruction{ .type = .ADC, .mode = AddressMode{ .Indirect = .{} } },
        0x65 => Instruction{ .type = .ADC, .mode = AddressMode{ .ZeroPage = .{} } },
        0x66 => Instruction{ .type = .ROR, .mode = AddressMode{ .ZeroPage = .{} } },
        0x68 => Instruction{ .type = .PLA, .mode = AddressMode{ .Implied = .{} } },
        0x69 => Instruction{ .type = .ADC, .mode = AddressMode{ .Immediate = .{} } },
        0x6A => Instruction{ .type = .ROR, .mode = AddressMode{ .Accumulator = .{} } },
        0x6C => Instruction{ .type = .JMP, .mode = AddressMode{ .Indirect = .{} } },
        0x6D => Instruction{ .type = .ADC, .mode = AddressMode{ .Absolute = .{} } },
        0x6E => Instruction{ .type = .ROR, .mode = AddressMode{ .Absolute = .{} } },
        0x70 => Instruction{ .type = .BVS, .mode = AddressMode{ .Relative = .{} } },
        0x71 => Instruction{ .type = .ADC, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0x75 => Instruction{ .type = .ADC, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x76 => Instruction{ .type = .ROR, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x78 => Instruction{ .type = .SEI, .mode = AddressMode{ .Implied = .{} } },
        0x79 => Instruction{ .type = .ADC, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x7D => Instruction{ .type = .ADC, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x7E => Instruction{ .type = .ROR, .mode = AddressMode{ .AbsoluteX = .{} } },
        0x81 => Instruction{ .type = .STA, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0x84 => Instruction{ .type = .STY, .mode = AddressMode{ .ZeroPage = .{} } },
        0x85 => Instruction{ .type = .STA, .mode = AddressMode{ .ZeroPage  = .{} } },
        0x86 => Instruction{ .type = .STX, .mode = AddressMode{ .ZeroPage  = .{} } },
        0x88 => Instruction{ .type = .DEY, .mode = AddressMode{ .Implied = .{} } },
        0x8A => Instruction{ .type = .TXA, .mode = AddressMode{ .Implied = .{} } },
        0x8C => Instruction{ .type = .STY, .mode = AddressMode{ .Absolute = .{} } },
        0x8D => Instruction{ .type = .STA, .mode = AddressMode{ .Absolute = .{} } },
        0x8E => Instruction{ .type = .STX, .mode = AddressMode{ .Absolute = .{} } },
        0x90 => Instruction{ .type = .BCC, .mode = AddressMode{ .Relative = .{} } },
        0x91 => Instruction{ .type = .STA, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0x94 => Instruction{ .type = .STY, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x95 => Instruction{ .type = .STA, .mode = AddressMode{ .ZeroPageX = .{} } },
        0x96 => Instruction{ .type = .STX, .mode = AddressMode{ .ZeroPageY = .{} } },
        0x98 => Instruction{ .type = .TAY, .mode = AddressMode{ .Implied = .{} } },
        0x99 => Instruction{ .type = .STA, .mode = AddressMode{ .AbsoluteY = .{} } },
        0x9A => Instruction{ .type = .TXS, .mode = AddressMode{ .Implied = .{} } },
        0x9D => Instruction{ .type = .STA, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xA0 => Instruction{ .type = .LDY, .mode = AddressMode{ .Immediate = .{} } },
        0xA1 => Instruction{ .type = .LDA, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0xA2 => Instruction{ .type = .LDX, .mode = AddressMode{ .Immediate = .{} } },
        0xA4 => Instruction{ .type = .LDY, .mode = AddressMode{ .ZeroPage = .{} } },
        0xA5 => Instruction{ .type = .LDA, .mode = AddressMode{ .ZeroPage = .{} } },
        0xA6 => Instruction{ .type = .LDX, .mode = AddressMode{ .ZeroPage = .{} } },
        0xA8 => Instruction{ .type = .TAY, .mode = AddressMode{ .Implied = .{} } },
        0xA9 => Instruction{ .type = .LDA, .mode = AddressMode{ .Immediate = .{} } },
        0xAA => Instruction{ .type = .TAX, .mode = AddressMode{ .Implied = .{} } },
        0xAC => Instruction{ .type = .LDY, .mode = AddressMode{ .Absolute = .{} } },
        0xAD => Instruction{ .type = .LDA, .mode = AddressMode{ .Absolute = .{} } },
        0xAE => Instruction{ .type = .LDX, .mode = AddressMode{ .Absolute = .{} } },
        0xB0 => Instruction{ .type = .BCS, .mode = AddressMode{ .Relative = .{} } },
        0xB1 => Instruction{ .type = .LDA, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0xB4 => Instruction{ .type = .LDY, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xB5 => Instruction{ .type = .LDA, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xB6 => Instruction{ .type = .LDX, .mode = AddressMode{ .ZeroPageY = .{} } },
        0xB8 => Instruction{ .type = .CLV, .mode = AddressMode{ .Implied = .{} } },
        0xB9 => Instruction{ .type = .LDA, .mode = AddressMode{ .AbsoluteY = .{} } },
        0xBA => Instruction{ .type = .TSX, .mode = AddressMode{ .Implied = .{} } },
        0xBC => Instruction{ .type = .LDY, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xBD => Instruction{ .type = .LDA, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xBE => Instruction{ .type = .LDX, .mode = AddressMode{ .AbsoluteY = .{} } },
        0xC0 => Instruction{ .type = .CPY, .mode = AddressMode{ .Immediate = .{} } },
        0xC1 => Instruction{ .type = .CMP, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0xC4 => Instruction{ .type = .CPY, .mode = AddressMode{ .ZeroPage = .{} } },
        0xC5 => Instruction{ .type = .CMP, .mode = AddressMode{ .ZeroPage = .{} } },
        0xC6 => Instruction{ .type = .DEC, .mode = AddressMode{ .ZeroPage = .{} } },
        0xC8 => Instruction{ .type = .INY, .mode = AddressMode{ .Implied = .{} } },
        0xC9 => Instruction{ .type = .CMP, .mode = AddressMode{ .Immediate = .{} } },
        0xCA => Instruction{ .type = .DEX, .mode = AddressMode{ .Implied = .{} } },
        0xCC => Instruction{ .type = .CPY, .mode = AddressMode{ .Absolute = .{} } },
        0xCD => Instruction{ .type = .CMP, .mode = AddressMode{ .Absolute = .{} } },
        0xCE => Instruction{ .type = .DEC, .mode = AddressMode{ .Absolute = .{} } },
        0xD0 => Instruction{ .type = .BNE, .mode = AddressMode{ .Relative = .{} } },
        0xD1 => Instruction{ .type = .CMP, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0xD5 => Instruction{ .type = .CMP, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xD6 => Instruction{ .type = .DEC, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xD8 => Instruction{ .type = .CLD, .mode = AddressMode{ .Implied = .{} } },
        0xD9 => Instruction{ .type = .CMP, .mode = AddressMode{ .AbsoluteY = .{} } },
        0xDD => Instruction{ .type = .CMP, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xDE => Instruction{ .type = .DEC, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xE0 => Instruction{ .type = .CPX, .mode = AddressMode{ .Immediate = .{} } },
        0xE1 => Instruction{ .type = .SBC, .mode = AddressMode{ .IndexedIndirect = .{} } },
        0xE4 => Instruction{ .type = .CPX, .mode = AddressMode{ .ZeroPage = .{} } },
        0xE5 => Instruction{ .type = .SBC, .mode = AddressMode{ .ZeroPage = .{} } },
        0xE6 => Instruction{ .type = .INC, .mode = AddressMode{ .ZeroPage = .{} } },
        0xE8 => Instruction{ .type = .INX, .mode = AddressMode{ .Implied = .{} } },
        0xE9 => Instruction{ .type = .SBC, .mode = AddressMode{ .Immediate = .{} } },
        0xEA => Instruction{ .type = .NOP, .mode = AddressMode{ .Implied = .{} } },
        0xEC => Instruction{ .type = .CPX, .mode = AddressMode{ .Absolute = .{} } },
        0xED => Instruction{ .type = .SBC, .mode = AddressMode{ .Absolute = .{} } },
        0xEE => Instruction{ .type = .INC, .mode = AddressMode{ .Absolute = .{} } },
        0xF0 => Instruction{ .type = .BEQ, .mode = AddressMode{ .Relative = .{} } },
        0xF1 => Instruction{ .type = .SBC, .mode = AddressMode{ .IndirectIndexed = .{} } },
        0xF5 => Instruction{ .type = .SBC, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xF6 => Instruction{ .type = .INC, .mode = AddressMode{ .ZeroPageX = .{} } },
        0xF8 => Instruction{ .type = .SED, .mode = AddressMode{ .Implied = .{} } },
        0xF9 => Instruction{ .type = .SBC, .mode = AddressMode{ .AbsoluteY = .{} } },
        0xFD => Instruction{ .type = .SBC, .mode = AddressMode{ .AbsoluteX = .{} } },
        0xFE => Instruction{ .type = .INC, .mode = AddressMode{ .AbsoluteX = .{} } },
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

    const mode = AddressMode{ .Absolute = 0x0000 };
    // mode.load();
}
