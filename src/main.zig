const std = @import("std");
const fs = std.fs;
const process = std.process;

var a: *std.mem.Allocator = undefined;

const DecodeError = error{InvalidOpcode};

const StatusRegister = packed union {
    byte: u8,
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

const Pins = struct {
    a: u16,
    d: u8,
    rw: bool,
    sync: bool,
};

fn CPU(comptime T: type) type {
    return struct {
        // Registers
        registers: struct {
            pc: u16,
            sp: u8,
            p: StatusRegister,
            a: u8,
            x: u8,
            y: u8,
        },

        pins: Pins,

        context: T,

        pub fn init(context: T) CPU(T) {
            return CPU(T){
                .registers = .{
                    .pc = 0,
                    .sp = 0xFD,
                    .p = .{ .byte = 0x34 },
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
                .context = context,
            };
        }

        pub fn step(self: *CPU(T)) !void {
            const opcode = self.fetch();
            const instruction = try decode(opcode);
            self.tick();

            // instruction.exec();
        }

        pub fn tick(self: CPU(T)) void {
            self.pins = self.context.tick(self.pins);
        }

        pub fn fetch(self: *CPU(T)) u8 {
            self.registers.pc += 1;
            self.pins.a = self.registers.pc;
            return self.pins.d;
        }

        pub fn indexedIndirect(self: CPU(T), instruction: Instruction) void {
            const addr = self.fetch();
            self.tick();

            self.pins.a += self.registers.x;
            self.pins.a |= 0xFF;
            self.tick();

            const lo = self.pins.d;
            self.pins.a += 1;
            self.pins.a |= 0xFF;
            self.tick();

            const hi = self.pins.d;
            self.pins.a = word(lo, hi);
            if (instruction.access == .W) {
                self.pins.rw = false;
                self.pins.d = instruction.write(self);
            }
            self.tick();

            if (instruction.access == .R) {
                instruction.read(self);
            }
            self.pins.a = self.registers.PC;
            // sync pin?
            self.tick();
        }

        pub fn setNZ(self: CPU(T), result: u8) void {
            var flags = self.registers.p.flags;
            flags.n = false;
            flags.z = false;

            if (result & 0xFF == 0) {
                flags.z = true;
            } else {
                flags.n = result >> 7;
            }

            self.registers.p.flags = flags;
        }
    };
}

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

    pub fn read(self: InstructionType, cpu: CPU) void {
        switch (self) {
            .ADC => cpu.registers.a += cpu.pins.d,
            .CLD => cpu.registers.p.flags.d = false,
            .ORA => {
                cpu.registers.a |= cpu.pins.d;
                setNZ(cpu, cpu.registers.a);
            },
            else => return,
        }
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

const MemoryAccess = enum {
    R,
    W,
    RW,
};

const Instruction = struct {
    type: InstructionType,
    mode: AddressMode,
    access: MemoryAccess,

    pub fn exec(self: Instruction) void {
        self.mode.exec(self.type);
    }
};

const Context = struct {
    memory: []u8,

    pub fn init() !Context {
        return Context{
            .memory = try a.alloc(u8, 0x10000),
        };
    }

    pub fn tick(self: Context, cur: Pins) Pins {
        const addr = cur.a;
        var next = cur;

        if (cur.rw) {
            next.d = self.memory[addr];
        } else {
            self.memory[addr] = cur.d;
        }

        return next;
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

    _ = try file.readAll(context.memory);

    var cpu = CPU(Context).init(context);
    _ = try cpu.step();

    // TODO: Figure out why the code segment starts here and not at 0x0400
    cpu.registers.pc = 0x03F6;

    while (true) {
        const opcode = context.memory[cpu.registers.pc];
        const instruction = try decode(opcode);

        std.debug.warn("{X} {} {} {}\n", .{ opcode, instruction.type, instruction.mode, instruction.access });

        // try instruction.exec(&context);
        break;
    }
}

pub inline fn word(lo: u8, hi: u8) u16 {
    return @as(u16, hi) << 8 | @as(u16, lo);
}

pub fn decode(opcode: u8) !Instruction {
    return switch (opcode) {
        0x00 => Instruction{ .type = .BRK, .mode = .Implied, .access = .R },
        0x01 => Instruction{ .type = .ORA, .mode = .IndexedIndirect, .access = .R },
        0x05 => Instruction{ .type = .ORA, .mode = .ZeroPage, .access = .R },
        0x06 => Instruction{ .type = .ASL, .mode = .ZeroPage, .access = .R },
        0x08 => Instruction{ .type = .PHP, .mode = .Implied, .access = .W },
        0x09 => Instruction{ .type = .ORA, .mode = .Immediate, .access = .R },
        0x0A => Instruction{ .type = .ASL, .mode = .Accumulator, .access = .RW },
        0x0D => Instruction{ .type = .ORA, .mode = .Absolute, .access = .R },
        0x0E => Instruction{ .type = .ASL, .mode = .Absolute, .access = .RW },
        0x10 => Instruction{ .type = .BPL, .mode = .Relative, .access = .R },
        0x11 => Instruction{ .type = .ORA, .mode = .IndirectIndexed, .access = .R },
        0x15 => Instruction{ .type = .ORA, .mode = .ZeroPageX, .access = .R },
        0x16 => Instruction{ .type = .ASL, .mode = .ZeroPageX, .access = .RW },
        0x18 => Instruction{ .type = .CLC, .mode = .Implied, .access = .R },
        0x19 => Instruction{ .type = .ORA, .mode = .AbsoluteY, .access = .R },
        0x1D => Instruction{ .type = .ORA, .mode = .AbsoluteX, .access = .R },
        0x1E => Instruction{ .type = .ASL, .mode = .AbsoluteX, .access = .RW },
        0x20 => Instruction{ .type = .JSR, .mode = .Absolute, .access = .RW },
        0x21 => Instruction{ .type = .AND, .mode = .IndexedIndirect, .access = .R },
        0x24 => Instruction{ .type = .BIT, .mode = .ZeroPage, .access = .R },
        0x25 => Instruction{ .type = .AND, .mode = .ZeroPage, .access = .R },
        0x26 => Instruction{ .type = .ROL, .mode = .ZeroPage, .access = .RW },
        0x28 => Instruction{ .type = .PLP, .mode = .Implied, .access = .R },
        0x29 => Instruction{ .type = .AND, .mode = .AbsoluteY, .access = .R },
        0x2A => Instruction{ .type = .ROL, .mode = .Accumulator, .access = .RW },
        0x2C => Instruction{ .type = .BIT, .mode = .Absolute, .access = .R },
        0x2D => Instruction{ .type = .AND, .mode = .Absolute, .access = .R },
        0x2E => Instruction{ .type = .ROL, .mode = .Absolute, .access = .RW },
        0x30 => Instruction{ .type = .BMI, .mode = .Relative, .access = .R },
        0x31 => Instruction{ .type = .AND, .mode = .IndirectIndexed, .access = .R },
        0x35 => Instruction{ .type = .AND, .mode = .ZeroPageX, .access = .R },
        0x36 => Instruction{ .type = .ROL, .mode = .ZeroPageX, .access = .RW },
        0x38 => Instruction{ .type = .SEC, .mode = .Implied, .access = .R },
        0x39 => Instruction{ .type = .AND, .mode = .AbsoluteY, .access = .R },
        0x3D => Instruction{ .type = .AND, .mode = .AbsoluteX, .access = .R },
        0x3E => Instruction{ .type = .ROL, .mode = .AbsoluteX, .access = .RW },
        0x40 => Instruction{ .type = .RTI, .mode = .Implied, .access = .R },
        0x41 => Instruction{ .type = .EOR, .mode = .IndexedIndirect, .access = .R },
        0x45 => Instruction{ .type = .EOR, .mode = .ZeroPage, .access = .R },
        0x46 => Instruction{ .type = .LSR, .mode = .ZeroPage, .access = .RW },
        0x48 => Instruction{ .type = .PHA, .mode = .Implied, .access = .W },
        0x49 => Instruction{ .type = .EOR, .mode = .Immediate, .access = .R },
        0x4A => Instruction{ .type = .LSR, .mode = .Accumulator, .access = .RW },
        0x4C => Instruction{ .type = .JMP, .mode = .Absolute, .access = .R },
        0x4D => Instruction{ .type = .EOR, .mode = .Absolute, .access = .R },
        0x4E => Instruction{ .type = .LSR, .mode = .Absolute, .access = .RW },
        0x50 => Instruction{ .type = .BVC, .mode = .Relative, .access = .R },
        0x51 => Instruction{ .type = .EOR, .mode = .IndirectIndexed, .access = .R },
        0x55 => Instruction{ .type = .EOR, .mode = .ZeroPageX, .access = .R },
        0x56 => Instruction{ .type = .LSR, .mode = .ZeroPageX, .access = .RW },
        0x58 => Instruction{ .type = .CLI, .mode = .Implied, .access = .R },
        0x59 => Instruction{ .type = .EOR, .mode = .AbsoluteY, .access = .R },
        0x5D => Instruction{ .type = .EOR, .mode = .AbsoluteX, .access = .R },
        0x5E => Instruction{ .type = .LSR, .mode = .AbsoluteX, .access = .RW },
        0x60 => Instruction{ .type = .RTS, .mode = .Implied, .access = .R },
        0x61 => Instruction{ .type = .ADC, .mode = .IndexedIndirect, .access = .R },
        0x65 => Instruction{ .type = .ADC, .mode = .ZeroPage, .access = .R },
        0x66 => Instruction{ .type = .ROR, .mode = .ZeroPage, .access = .RW },
        0x68 => Instruction{ .type = .PLA, .mode = .Implied, .access = .R },
        0x69 => Instruction{ .type = .ADC, .mode = .Immediate, .access = .R },
        0x6A => Instruction{ .type = .ROR, .mode = .Accumulator, .access = .RW },
        0x6C => Instruction{ .type = .JMP, .mode = .Indirect, .access = .R },
        0x6D => Instruction{ .type = .ADC, .mode = .Absolute, .access = .R },
        0x6E => Instruction{ .type = .ROR, .mode = .Absolute, .access = .RW },
        0x70 => Instruction{ .type = .BVS, .mode = .Relative, .access = .R },
        0x71 => Instruction{ .type = .ADC, .mode = .IndirectIndexed, .access = .R },
        0x75 => Instruction{ .type = .ADC, .mode = .ZeroPageX, .access = .R },
        0x76 => Instruction{ .type = .ROR, .mode = .ZeroPageX, .access = .RW },
        0x78 => Instruction{ .type = .SEI, .mode = .Implied, .access = .R },
        0x79 => Instruction{ .type = .ADC, .mode = .AbsoluteY, .access = .R },
        0x7D => Instruction{ .type = .ADC, .mode = .AbsoluteX, .access = .R },
        0x7E => Instruction{ .type = .ROR, .mode = .AbsoluteX, .access = .RW },
        0x81 => Instruction{ .type = .STA, .mode = .IndexedIndirect, .access = .W },
        0x84 => Instruction{ .type = .STY, .mode = .ZeroPage, .access = .W },
        0x85 => Instruction{ .type = .STA, .mode = .ZeroPage, .access = .W },
        0x86 => Instruction{ .type = .STX, .mode = .ZeroPage, .access = .W },
        0x88 => Instruction{ .type = .DEY, .mode = .Implied, .access = .R },
        0x8A => Instruction{ .type = .TXA, .mode = .Implied, .access = .R },
        0x8C => Instruction{ .type = .STY, .mode = .Absolute, .access = .W },
        0x8D => Instruction{ .type = .STA, .mode = .Absolute, .access = .W },
        0x8E => Instruction{ .type = .STX, .mode = .Absolute, .access = .W },
        0x90 => Instruction{ .type = .BCC, .mode = .Relative, .access = .R },
        0x91 => Instruction{ .type = .STA, .mode = .IndirectIndexed, .access = .W },
        0x94 => Instruction{ .type = .STY, .mode = .ZeroPageX, .access = .W },
        0x95 => Instruction{ .type = .STA, .mode = .ZeroPageX, .access = .W },
        0x96 => Instruction{ .type = .STX, .mode = .ZeroPageY, .access = .W },
        0x98 => Instruction{ .type = .TAY, .mode = .Implied, .access = .R },
        0x99 => Instruction{ .type = .STA, .mode = .AbsoluteY, .access = .W },
        0x9A => Instruction{ .type = .TXS, .mode = .Implied, .access = .R },
        0x9D => Instruction{ .type = .STA, .mode = .AbsoluteX, .access = .W },
        0xA0 => Instruction{ .type = .LDY, .mode = .Immediate, .access = .R },
        0xA1 => Instruction{ .type = .LDA, .mode = .IndexedIndirect, .access = .R },
        0xA2 => Instruction{ .type = .LDX, .mode = .Immediate, .access = .R },
        0xA4 => Instruction{ .type = .LDY, .mode = .ZeroPage, .access = .R },
        0xA5 => Instruction{ .type = .LDA, .mode = .ZeroPage, .access = .R },
        0xA6 => Instruction{ .type = .LDX, .mode = .ZeroPage, .access = .R },
        0xA8 => Instruction{ .type = .TAY, .mode = .Implied, .access = .R },
        0xA9 => Instruction{ .type = .LDA, .mode = .Immediate, .access = .R },
        0xAA => Instruction{ .type = .TAX, .mode = .Implied, .access = .R },
        0xAC => Instruction{ .type = .LDY, .mode = .Absolute, .access = .R },
        0xAD => Instruction{ .type = .LDA, .mode = .Absolute, .access = .R },
        0xAE => Instruction{ .type = .LDX, .mode = .Absolute, .access = .R },
        0xB0 => Instruction{ .type = .BCS, .mode = .Relative, .access = .R },
        0xB1 => Instruction{ .type = .LDA, .mode = .IndirectIndexed, .access = .R },
        0xB4 => Instruction{ .type = .LDY, .mode = .ZeroPageX, .access = .R },
        0xB5 => Instruction{ .type = .LDA, .mode = .ZeroPageX, .access = .R },
        0xB6 => Instruction{ .type = .LDX, .mode = .ZeroPageY, .access = .R },
        0xB8 => Instruction{ .type = .CLV, .mode = .Implied, .access = .R },
        0xB9 => Instruction{ .type = .LDA, .mode = .AbsoluteY, .access = .R },
        0xBA => Instruction{ .type = .TSX, .mode = .Implied, .access = .R },
        0xBC => Instruction{ .type = .LDY, .mode = .AbsoluteX, .access = .R },
        0xBD => Instruction{ .type = .LDA, .mode = .AbsoluteX, .access = .R },
        0xBE => Instruction{ .type = .LDX, .mode = .AbsoluteY, .access = .R },
        0xC0 => Instruction{ .type = .CPY, .mode = .Immediate, .access = .R },
        0xC1 => Instruction{ .type = .CMP, .mode = .IndexedIndirect, .access = .R },
        0xC4 => Instruction{ .type = .CPY, .mode = .ZeroPage, .access = .R },
        0xC5 => Instruction{ .type = .CMP, .mode = .ZeroPage, .access = .R },
        0xC6 => Instruction{ .type = .DEC, .mode = .ZeroPage, .access = .RW },
        0xC8 => Instruction{ .type = .INY, .mode = .Implied, .access = .R },
        0xC9 => Instruction{ .type = .CMP, .mode = .Immediate, .access = .R },
        0xCA => Instruction{ .type = .DEX, .mode = .Implied, .access = .R },
        0xCC => Instruction{ .type = .CPY, .mode = .Absolute, .access = .R },
        0xCD => Instruction{ .type = .CMP, .mode = .Absolute, .access = .R },
        0xCE => Instruction{ .type = .DEC, .mode = .Absolute, .access = .RW },
        0xD0 => Instruction{ .type = .BNE, .mode = .Relative, .access = .R },
        0xD1 => Instruction{ .type = .CMP, .mode = .IndirectIndexed, .access = .R },
        0xD5 => Instruction{ .type = .CMP, .mode = .ZeroPageX, .access = .R },
        0xD6 => Instruction{ .type = .DEC, .mode = .ZeroPageX, .access = .RW },
        0xD8 => Instruction{ .type = .CLD, .mode = .Implied, .access = .R },
        0xD9 => Instruction{ .type = .CMP, .mode = .AbsoluteY, .access = .R },
        0xDD => Instruction{ .type = .CMP, .mode = .AbsoluteX, .access = .R },
        0xDE => Instruction{ .type = .DEC, .mode = .AbsoluteX, .access = .RW },
        0xE0 => Instruction{ .type = .CPX, .mode = .Immediate, .access = .R },
        0xE1 => Instruction{ .type = .SBC, .mode = .IndexedIndirect, .access = .R },
        0xE4 => Instruction{ .type = .CPX, .mode = .ZeroPage, .access = .R },
        0xE5 => Instruction{ .type = .SBC, .mode = .ZeroPage, .access = .R },
        0xE6 => Instruction{ .type = .INC, .mode = .ZeroPage, .access = .RW },
        0xE8 => Instruction{ .type = .INX, .mode = .Implied, .access = .R },
        0xE9 => Instruction{ .type = .SBC, .mode = .Immediate, .access = .R },
        0xEA => Instruction{ .type = .NOP, .mode = .Implied, .access = .R },
        0xEC => Instruction{ .type = .CPX, .mode = .Absolute, .access = .R },
        0xED => Instruction{ .type = .SBC, .mode = .Absolute, .access = .R },
        0xEE => Instruction{ .type = .INC, .mode = .Absolute, .access = .RW },
        0xF0 => Instruction{ .type = .BEQ, .mode = .Relative, .access = .R },
        0xF1 => Instruction{ .type = .SBC, .mode = .IndirectIndexed, .access = .R },
        0xF5 => Instruction{ .type = .SBC, .mode = .ZeroPageX, .access = .R },
        0xF6 => Instruction{ .type = .INC, .mode = .ZeroPageX, .access = .RW },
        0xF8 => Instruction{ .type = .SED, .mode = .Implied, .access = .R },
        0xF9 => Instruction{ .type = .SBC, .mode = .AbsoluteY, .access = .R },
        0xFD => Instruction{ .type = .SBC, .mode = .AbsoluteX, .access = .R },
        0xFE => Instruction{ .type = .INC, .mode = .AbsoluteX, .access = .RW },
        else => DecodeError.InvalidOpcode,
    };
}
