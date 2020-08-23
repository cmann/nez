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

const CPU = struct {
    // Registers
    registers: struct {
        pc: u16,
        sp: u8,
        p: StatusRegister,
        a: u8,
        x: u8,
        y: u8,
    },

    pins: struct {
        a: u16,
        d: u8,
        rw: bool,
        sync: bool,
    },

    pub fn init() CPU {
        return CPU{
            .registers = .{
                .pc = 0,
                .sp = 0xFD,
                .p = .{ .p = 0x34 },
                .a = 0,
                .x = 0,
                .y = 0,
            },
            .pins = .{
                .sync = false,
                .rw = true,
                .a = 0,
                .d = 0,
            },
        };
    }

    pub fn step(self: CPU) !void {
        // Cycle 1
        const opcode = self.pins.d;
        const instruction = try decode(opcode);
        self.registers.pc += 1;
        self.pins.a = self.registers.pc;
        // call tick

        instruction.exec();

        // Cycle 2 for CLD
        self.registers.p.flags.d = false;
        self.fetch();
        // call tick
    }

    pub fn fetch(self: CPU, mode: MemoryAccess) u8 {
        self.register.pc += 1;
        self.pins.a = self.register.pc;
        return self.pins.d;
    }

    pub fn implied(self: CPU, instruction: Instruction) void {
        instruction.exec();
        // call tick
    }

    pub fn indexedIndirect(self: CPU, instruction: Instruction) void {
        const addr = self.fetchByte();
        self.pins.a = addr;
        // call tick

        const b = self.pins.d + self.registers.x;
        self.pins.a = b;
        // call tick

        const lo = self.pins.d;
        self.pins.a = b + 1;
        // call tick

        const hi = self.pins.d;
        self.pins.a = @as(u16, hi) << 8 | @as(u16, lo);
        if (instruction.access == .W) {
            self.pins.rw = false;
            self.pins.d = instruction.write();
        }
        // call tick

        if (instruction.access == .R) {
            instruction.read(self.pins.d);
        }
        // call tick
    }
};

const MemoryAccess = enum {
    R,
    W,
    RW,
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

    pub fn access(self: InstructionType) MemoryAccess {
        return switch (self) {
            ADC => MemoryAccess.R,
            AND => MemoryAccess.R,
            ASL => MemoryAccess.RW,
            BCC => MemoryAccess.R,
            BCS => MemoryAccess.R,
            BEQ => MemoryAccess.R,
            BIT => MemoryAccess.R,
            BMI => MemoryAccess.R,
            BNE => MemoryAccess.R,
            BPL => MemoryAccess.R,
            BRK => MemoryAccess.R,
            BVC => MemoryAccess.R,
            BVS => MemoryAccess.R,
            CLC => MemoryAccess.R,
            CLD => MemoryAccess.R,
            CLI => MemoryAccess.R,
            CLV => MemoryAccess.R,
            CMP => MemoryAccess.R,
            CPX => MemoryAccess.R,
            CPY => MemoryAccess.R,
            DEC => MemoryAccess.RW,
            DEX => MemoryAccess.R,
            DEY => MemoryAccess.R,
            EOR => MemoryAccess.R,
            INC => MemoryAccess.RW,
            INX => MemoryAccess.R,
            INY => MemoryAccess.R,
            JMP => MemoryAccess.R,
            JSR => MemoryAccess.RW, // or W?
            LDA => MemoryAccess.R,
            LDX => MemoryAccess.R,
            LDY => MemoryAccess.R,
            LSR => MemoryAccess.RW,
            NOP => MemoryAccess.R,
            ORA => MemoryAccess.R,
            PHA => MemoryAccess.W,
            PHP => MemoryAccess.W,
            PLA => MemoryAccess.R,
            PLP => MemoryAccess.R,
            ROL => MemoryAccess.RW,
            ROR => MemoryAccess.RW,
            RTI => MemoryAccess.R,
            RTS => MemoryAccess.R,
            SBC => MemoryAccess.R,
            SEC => MemoryAccess.R,
            SED => MemoryAccess.R,
            SEI => MemoryAccess.R,
            STA => MemoryAccess.W,
            STX => MemoryAccess.W,
            STY => MemoryAccess.W,
            TAX => MemoryAccess.R,
            TAY => MemoryAccess.R,
            TSX => MemoryAccess.R,
            TXA => MemoryAccess.R,
            TXS => MemoryAccess.R,
            TYA => MemoryAccess.R,
        };
    }
};

const AddressMode = enum {
    // Non-indexed, non-memory
    Accumulator,
    Immediate,
    Implied,
    // Non-indexed, memory
    Relative,
    Absolute,
    ZeroPage,
    Indirect,
    // Indexed, memory
    AbsoluteX,
    AbsoluteY,
    ZeroPageX,
    ZeroPageY,
    IndexedIndirect,
    IndirectIndexed,
};

const Instruction = struct {
    type: InstructionType,
    mode: AddressMode,
    access: MemoryAccess,

    pub fn exec(self: Instruction) void {}
};

pub fn decode(opcode: u8) !Instruction {
    return switch (opcode) {
        0x00 => Instruction{ .type = .BRK, .mode = .Implied },
        0x01 => Instruction{ .type = .ORA, .mode = .IndexedIndirect },
        0x05 => Instruction{ .type = .ORA, .mode = .ZeroPage },
        0x06 => Instruction{ .type = .ASL, .mode = .ZeroPage },
        0x08 => Instruction{ .type = .PHP, .mode = .Implied },
        0x09 => Instruction{ .type = .ORA, .mode = .Immediate },
        0x0A => Instruction{ .type = .ASL, .mode = .Accumulator },
        0x0D => Instruction{ .type = .ORA, .mode = .Absolute },
        0x0E => Instruction{ .type = .ASL, .mode = .Absolute },
        0x10 => Instruction{ .type = .BPL, .mode = .Relative },
        0x11 => Instruction{ .type = .ORA, .mode = .IndirectIndexed },
        0x15 => Instruction{ .type = .ORA, .mode = .ZeroPageX },
        0x16 => Instruction{ .type = .ASL, .mode = .ZeroPageX },
        0x18 => Instruction{ .type = .CLC, .mode = .Implied },
        0x19 => Instruction{ .type = .ORA, .mode = .AbsoluteY },
        0x1D => Instruction{ .type = .ORA, .mode = .AbsoluteX },
        0x1E => Instruction{ .type = .ASL, .mode = .AbsoluteX },
        0x20 => Instruction{ .type = .JSR, .mode = .Absolute },
        0x21 => Instruction{ .type = .AND, .mode = .IndexedIndirect },
        0x24 => Instruction{ .type = .BIT, .mode = .ZeroPage },
        0x25 => Instruction{ .type = .AND, .mode = .ZeroPage },
        0x26 => Instruction{ .type = .ROL, .mode = .ZeroPage },
        0x28 => Instruction{ .type = .PLP, .mode = .Implied },
        0x29 => Instruction{ .type = .AND, .mode = .AbsoluteY },
        0x2A => Instruction{ .type = .ROL, .mode = .Accumulator },
        0x2C => Instruction{ .type = .BIT, .mode = .Absolute },
        0x2D => Instruction{ .type = .AND, .mode = .Absolute },
        0x2E => Instruction{ .type = .ROL, .mode = .Absolute },
        0x30 => Instruction{ .type = .BMI, .mode = .Relative },
        0x31 => Instruction{ .type = .AND, .mode = .IndirectIndexed },
        0x35 => Instruction{ .type = .AND, .mode = .ZeroPageX },
        0x36 => Instruction{ .type = .ROL, .mode = .ZeroPageX },
        0x38 => Instruction{ .type = .SEC, .mode = .Implied },
        0x39 => Instruction{ .type = .AND, .mode = .AbsoluteY },
        0x3D => Instruction{ .type = .AND, .mode = .AbsoluteX },
        0x3E => Instruction{ .type = .ROL, .mode = .AbsoluteX },
        0x40 => Instruction{ .type = .RTI, .mode = .Implied },
        0x41 => Instruction{ .type = .EOR, .mode = .IndexedIndirect },
        0x45 => Instruction{ .type = .EOR, .mode = .ZeroPage },
        0x46 => Instruction{ .type = .LSR, .mode = .ZeroPage },
        0x48 => Instruction{ .type = .PHA, .mode = .Implied },
        0x49 => Instruction{ .type = .EOR, .mode = .Immediate },
        0x4A => Instruction{ .type = .LSR, .mode = .Accumulator },
        0x4C => Instruction{ .type = .JMP, .mode = .Absolute },
        0x4D => Instruction{ .type = .EOR, .mode = .Absolute },
        0x4E => Instruction{ .type = .LSR, .mode = .Absolute },
        0x50 => Instruction{ .type = .BVC, .mode = .Relative },
        0x51 => Instruction{ .type = .EOR, .mode = .IndirectIndexed },
        0x55 => Instruction{ .type = .EOR, .mode = .ZeroPageX },
        0x56 => Instruction{ .type = .LSR, .mode = .ZeroPageX },
        0x58 => Instruction{ .type = .CLI, .mode = .Implied },
        0x59 => Instruction{ .type = .EOR, .mode = .AbsoluteY },
        0x5D => Instruction{ .type = .EOR, .mode = .AbsoluteX },
        0x5E => Instruction{ .type = .LSR, .mode = .AbsoluteX },
        0x60 => Instruction{ .type = .RTS, .mode = .Implied },
        0x61 => Instruction{ .type = .ADC, .mode = .IndexedIndirect },
        0x65 => Instruction{ .type = .ADC, .mode = .ZeroPage },
        0x66 => Instruction{ .type = .ROR, .mode = .ZeroPage },
        0x68 => Instruction{ .type = .PLA, .mode = .Implied },
        0x69 => Instruction{ .type = .ADC, .mode = .Immediate },
        0x6A => Instruction{ .type = .ROR, .mode = .Accumulator },
        0x6C => Instruction{ .type = .JMP, .mode = .Indirect },
        0x6D => Instruction{ .type = .ADC, .mode = .Absolute },
        0x6E => Instruction{ .type = .ROR, .mode = .Absolute },
        0x70 => Instruction{ .type = .BVS, .mode = .Relative },
        0x71 => Instruction{ .type = .ADC, .mode = .IndirectIndexed },
        0x75 => Instruction{ .type = .ADC, .mode = .ZeroPageX },
        0x76 => Instruction{ .type = .ROR, .mode = .ZeroPageX },
        0x78 => Instruction{ .type = .SEI, .mode = .Implied },
        0x79 => Instruction{ .type = .ADC, .mode = .AbsoluteY },
        0x7D => Instruction{ .type = .ADC, .mode = .AbsoluteX },
        0x7E => Instruction{ .type = .ROR, .mode = .AbsoluteX },
        0x81 => Instruction{ .type = .STA, .mode = .IndexedIndirect },
        0x84 => Instruction{ .type = .STY, .mode = .ZeroPage },
        0x85 => Instruction{ .type = .STA, .mode = .ZeroPage },
        0x86 => Instruction{ .type = .STX, .mode = .ZeroPage },
        0x88 => Instruction{ .type = .DEY, .mode = .Implied },
        0x8A => Instruction{ .type = .TXA, .mode = .Implied },
        0x8C => Instruction{ .type = .STY, .mode = .Absolute },
        0x8D => Instruction{ .type = .STA, .mode = .Absolute },
        0x8E => Instruction{ .type = .STX, .mode = .Absolute },
        0x90 => Instruction{ .type = .BCC, .mode = .Relative },
        0x91 => Instruction{ .type = .STA, .mode = .IndirectIndexed },
        0x94 => Instruction{ .type = .STY, .mode = .ZeroPageX },
        0x95 => Instruction{ .type = .STA, .mode = .ZeroPageX },
        0x96 => Instruction{ .type = .STX, .mode = .ZeroPageY },
        0x98 => Instruction{ .type = .TAY, .mode = .Implied },
        0x99 => Instruction{ .type = .STA, .mode = .AbsoluteY },
        0x9A => Instruction{ .type = .TXS, .mode = .Implied },
        0x9D => Instruction{ .type = .STA, .mode = .AbsoluteX },
        0xA0 => Instruction{ .type = .LDY, .mode = .Immediate },
        0xA1 => Instruction{ .type = .LDA, .mode = .IndexedIndirect },
        0xA2 => Instruction{ .type = .LDX, .mode = .Immediate },
        0xA4 => Instruction{ .type = .LDY, .mode = .ZeroPage },
        0xA5 => Instruction{ .type = .LDA, .mode = .ZeroPage },
        0xA6 => Instruction{ .type = .LDX, .mode = .ZeroPage },
        0xA8 => Instruction{ .type = .TAY, .mode = .Implied },
        0xA9 => Instruction{ .type = .LDA, .mode = .Immediate },
        0xAA => Instruction{ .type = .TAX, .mode = .Implied },
        0xAC => Instruction{ .type = .LDY, .mode = .Absolute },
        0xAD => Instruction{ .type = .LDA, .mode = .Absolute },
        0xAE => Instruction{ .type = .LDX, .mode = .Absolute },
        0xB0 => Instruction{ .type = .BCS, .mode = .Relative },
        0xB1 => Instruction{ .type = .LDA, .mode = .IndirectIndexed },
        0xB4 => Instruction{ .type = .LDY, .mode = .ZeroPageX },
        0xB5 => Instruction{ .type = .LDA, .mode = .ZeroPageX },
        0xB6 => Instruction{ .type = .LDX, .mode = .ZeroPageY },
        0xB8 => Instruction{ .type = .CLV, .mode = .Implied },
        0xB9 => Instruction{ .type = .LDA, .mode = .AbsoluteY },
        0xBA => Instruction{ .type = .TSX, .mode = .Implied },
        0xBC => Instruction{ .type = .LDY, .mode = .AbsoluteX },
        0xBD => Instruction{ .type = .LDA, .mode = .AbsoluteX },
        0xBE => Instruction{ .type = .LDX, .mode = .AbsoluteY },
        0xC0 => Instruction{ .type = .CPY, .mode = .Immediate },
        0xC1 => Instruction{ .type = .CMP, .mode = .IndexedIndirect },
        0xC4 => Instruction{ .type = .CPY, .mode = .ZeroPage },
        0xC5 => Instruction{ .type = .CMP, .mode = .ZeroPage },
        0xC6 => Instruction{ .type = .DEC, .mode = .ZeroPage },
        0xC8 => Instruction{ .type = .INY, .mode = .Implied },
        0xC9 => Instruction{ .type = .CMP, .mode = .Immediate },
        0xCA => Instruction{ .type = .DEX, .mode = .Implied },
        0xCC => Instruction{ .type = .CPY, .mode = .Absolute },
        0xCD => Instruction{ .type = .CMP, .mode = .Absolute },
        0xCE => Instruction{ .type = .DEC, .mode = .Absolute },
        0xD0 => Instruction{ .type = .BNE, .mode = .Relative },
        0xD1 => Instruction{ .type = .CMP, .mode = .IndirectIndexed },
        0xD5 => Instruction{ .type = .CMP, .mode = .ZeroPageX },
        0xD6 => Instruction{ .type = .DEC, .mode = .ZeroPageX },
        0xD8 => Instruction{ .type = .CLD, .mode = .Implied },
        0xD9 => Instruction{ .type = .CMP, .mode = .AbsoluteY },
        0xDD => Instruction{ .type = .CMP, .mode = .AbsoluteX },
        0xDE => Instruction{ .type = .DEC, .mode = .AbsoluteX },
        0xE0 => Instruction{ .type = .CPX, .mode = .Immediate },
        0xE1 => Instruction{ .type = .SBC, .mode = .IndexedIndirect },
        0xE4 => Instruction{ .type = .CPX, .mode = .ZeroPage },
        0xE5 => Instruction{ .type = .SBC, .mode = .ZeroPage },
        0xE6 => Instruction{ .type = .INC, .mode = .ZeroPage },
        0xE8 => Instruction{ .type = .INX, .mode = .Implied },
        0xE9 => Instruction{ .type = .SBC, .mode = .Immediate },
        0xEA => Instruction{ .type = .NOP, .mode = .Implied },
        0xEC => Instruction{ .type = .CPX, .mode = .Absolute },
        0xED => Instruction{ .type = .SBC, .mode = .Absolute },
        0xEE => Instruction{ .type = .INC, .mode = .Absolute },
        0xF0 => Instruction{ .type = .BEQ, .mode = .Relative },
        0xF1 => Instruction{ .type = .SBC, .mode = .IndirectIndexed },
        0xF5 => Instruction{ .type = .SBC, .mode = .ZeroPageX },
        0xF6 => Instruction{ .type = .INC, .mode = .ZeroPageX },
        0xF8 => Instruction{ .type = .SED, .mode = .Implied },
        0xF9 => Instruction{ .type = .SBC, .mode = .AbsoluteY },
        0xFD => Instruction{ .type = .SBC, .mode = .AbsoluteX },
        0xFE => Instruction{ .type = .INC, .mode = .AbsoluteX },
        else => DecodeError.InvalidOpcode,
    };
}

const Context = struct {
    cpu: CPU,
    memory: []u8,

    pub fn init() !Context {
        return Context{
            .cpu = CPU.init(),
            .memory = try a.alloc(u8, 0x10000),
        };
    }

    pub fn tick(self: Context, cpu: *CPU) void {
        const addr = cpu.*.pins.a;

        if (cpu.*.pins.rw) {
            cpu.*.pins.d = self.memory[addr];
        } else {
            self.memory[addr] = cpu.*.pins.d;
        }
    }
};

pub fn main() !void {
    a = std.heap.c_allocator;

    var args = process.args();
    _ = args.skip();

    const bin_path = try args.next(a) orelse {
        return error.InvalidArgs;
    };
    errdefer a.free(bin_path);

    const file = try (fs.cwd().openFile(bin_path, .{}));
    a.free(bin_path);

    var context = try Context.init();
    defer a.free(context.memory);

    _ = try (file.readAll(context.memory));

    // TODO: Figure out why the code segment starts here and not at 0x0400
    context.cpu.registers.pc = 0x03F6;

    while (true) {
        const opcode = bin[i];
        const lo = bin[i + 1];
        const hi = bin[i + 2];
        const instruction = try decode(opcode, lo, hi);

        std.debug.warn("{X} {} {X}\n", .{ opcode, instruction.type, instruction.mode });

        try instruction.exec(&context);
        break;
    }
}
