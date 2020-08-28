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

        const Instruction = union(enum) {
            R: fn (*CPU(T), u8) void,
            W: fn (*CPU(T)) u8,
            RW: fn (*CPU(T), u8) u8,
        };

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
            self.tick();

            try self.exec(opcode);
        }

        fn tick(self: *CPU(T)) void {
            self.pins = self.context.tick(self.pins);
        }

        fn fetch(self: *CPU(T)) u8 {
            self.registers.pc += 1;
            self.pins.a = self.registers.pc;
            return self.pins.d;
        }

        fn setNZ(self: *CPU(T), result: u8) void {
            var flags = self.registers.p.flags;
            flags.n = false;
            flags.z = false;

            if (result & 0xFF == 0) {
                flags.z = true;
            } else {
                flags.n = result >> 7 != 0;
            }

            self.registers.p.flags = flags;
        }

        fn indexedIndirect(self: *CPU(T), instruction: Instruction) void {
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

            switch (instruction) {
                .R => |r| {
                    self.tick();
                    r(self, self.pins.d);
                },
                .W => |w| {
                    self.pins.rw = false;
                    self.pins.d = w(self);
                    self.tick();
                },
                .RW => |rw| {
                    const val = self.pins.d;
                    self.pins.rw = false;
                    self.tick();

                    self.pins.d = rw(self, val);
                    self.tick();

                    self.pins.rw = true;
                },
            }

            self.pins.a = self.registers.pc;
            self.tick();
        }

        fn cld(self: *CPU(T)) void {
            self.registers.p.flags.d = false;
        }

        fn ora(self: *CPU(T), value: u8) void {
            self.registers.a |= value;
            self.setNZ(self.registers.a);
        }

        pub fn exec(self: *CPU(T), opcode: u8) !void {
            return switch (opcode) {
                // 0x00 => self.implied(Instruction{ .R = CPU(T).brk }),
                0x01 => self.indexedIndirect(Instruction{ .R = CPU(T).ora }),
                // 0x05 => self.zeroPage(Instruction{ .R = CPU(T).ora }),
                // 0x06 => self.zeroPage(Instruction{ .R = CPU(T).asl }),
                // 0x08 => self.implied(Instruction{ .W = CPU(T).php }),
                // 0x09 => self.immediate(Instruction{ .R = CPU(T).ora }),
                // 0x0A => self.accumulator(Instruction{ .RW = CPU(T).asl }),
                // 0x0D => self.absolute(Instruction{ .R = CPU(T).ora }),
                // 0x0E => self.absolute(Instruction{ .RW = CPU(T).asl }),
                // 0x10 => self.relative(Instruction{ .R = CPU(T).bpl }),
                // 0x11 => self.indirectIndexed(Instruction{ .R = CPU(T).ora }),
                // 0x15 => self.zeroPageX(Instruction{ .R = CPU(T).ora }),
                // 0x16 => self.zeroPageX(Instruction{ .RW = CPU(T).asl }),
                // 0x18 => self.implied(Instruction{ .R = CPU(T).clc }),
                // 0x19 => self.absoluteY(Instruction{ .R = CPU(T).ora }),
                // 0x1D => self.absoluteX(Instruction{ .R = CPU(T).ora }),
                // 0x1E => self.absoluteX(Instruction{ .RW = CPU(T).asl }),
                // 0x20 => self.absolute(Instruction{ .RW = CPU(T).jsr }),
                // 0x21 => self.indexedIndirect(Instruction{ .R = CPU(T).and }),
                // 0x24 => self.zeroPage(Instruction{ .R = CPU(T).bit }),
                // 0x25 => self.zeroPage(Instruction{ .R = CPU(T).and }),
                // 0x26 => self.zeroPage(Instruction{ .RW = CPU(T).rol }),
                // 0x28 => self.implied(Instruction{ .R = CPU(T).plp }),
                // 0x29 => self.absoluteY(Instruction{ .R = CPU(T).and }),
                // 0x2A => self.accumulator(Instruction{ .RW = CPU(T).rol }),
                // 0x2C => self.absolute(Instruction{ .R = CPU(T).bit }),
                // 0x2D => self.absolute(Instruction{ .R = CPU(T).and }),
                // 0x2E => self.absolute(Instruction{ .RW = CPU(T).rol }),
                // 0x30 => self.relative(Instruction{ .R = CPU(T).bmi }),
                // 0x31 => self.indirectIndexed(Instruction{ .R = CPU(T).and }),
                // 0x35 => self.zeroPageX(Instruction{ .R = CPU(T).and }),
                // 0x36 => self.zeroPageX(Instruction{ .RW = CPU(T).rol }),
                // 0x38 => self.implied(Instruction{ .R = CPU(T).sec }),
                // 0x39 => self.absoluteY(Instruction{ .R = CPU(T).and }),
                // 0x3D => self.absoluteX(Instruction{ .R = CPU(T).and }),
                // 0x3E => self.absoluteX(Instruction{ .RW = CPU(T).rol }),
                // 0x40 => self.implied(Instruction{ .R = CPU(T).rti }),
                // 0x41 => self.indexedIndirect(Instruction{ .R = CPU(T).eor }),
                // 0x45 => self.zeroPage(Instruction{ .R = CPU(T).eor }),
                // 0x46 => self.zeroPage(Instruction{ .RW = CPU(T).lsr }),
                // 0x48 => self.implied(Instruction{ .W = CPU(T).pha }),
                // 0x49 => self.immediate(Instruction{ .R = CPU(T).eor }),
                // 0x4A => self.accumulator(Instruction{ .RW = CPU(T).lsr }),
                // 0x4C => self.absolute(Instruction{ .R = CPU(T).jmp }),
                // 0x4D => self.absolute(Instruction{ .R = CPU(T).eor }),
                // 0x4E => self.absolute(Instruction{ .RW = CPU(T).lsr }),
                // 0x50 => self.relative(Instruction{ .R = CPU(T).bvc }),
                // 0x51 => self.indirectIndexed(Instruction{ .R = CPU(T).eor }),
                // 0x55 => self.zeroPageX(Instruction{ .R = CPU(T).eor }),
                // 0x56 => self.zeroPageX(Instruction{ .RW = CPU(T).lsr }),
                // 0x58 => self.implied(Instruction{ .R = CPU(T).cli }),
                // 0x59 => self.absoluteY(Instruction{ .R = CPU(T).eor }),
                // 0x5D => self.absoluteX(Instruction{ .R = CPU(T).eor }),
                // 0x5E => self.absoluteX(Instruction{ .RW = CPU(T).lsr }),
                // 0x60 => self.implied(Instruction{ .R = CPU(T).rts }),
                // 0x61 => self.indexedIndirect(Instruction{ .R = CPU(T).adc }),
                // 0x65 => self.zeroPage(Instruction{ .R = CPU(T).adc }),
                // 0x66 => self.zeroPage(Instruction{ .RW = CPU(T).ror }),
                // 0x68 => self.implied(Instruction{ .R = CPU(T).pla }),
                // 0x69 => self.immediate(Instruction{ .R = CPU(T).adc }),
                // 0x6A => self.accumulator(Instruction{ .RW = CPU(T).ror }),
                // 0x6C => self.indirect(Instruction{ .R = CPU(T).jmp }),
                // 0x6D => self.absolute(Instruction{ .R = CPU(T).adc }),
                // 0x6E => self.absolute(Instruction{ .RW = CPU(T).ror }),
                // 0x70 => self.relative(Instruction{ .R = CPU(T).bvs }),
                // 0x71 => self.indirectIndexed(Instruction{ .R = CPU(T).adc }),
                // 0x75 => self.zeroPageX(Instruction{ .R = CPU(T).adc }),
                // 0x76 => self.zeroPageX(Instruction{ .RW = CPU(T).ror }),
                // 0x78 => self.implied(Instruction{ .R = CPU(T).sei }),
                // 0x79 => self.absoluteY(Instruction{ .R = CPU(T).adc }),
                // 0x7D => self.absoluteX(Instruction{ .R = CPU(T).adc }),
                // 0x7E => self.absoluteX(Instruction{ .RW = CPU(T).ror }),
                // 0x81 => self.indexedIndirect(Instruction{ .W = CPU(T).sta }),
                // 0x84 => self.zeroPage(Instruction{ .W = CPU(T).sty }),
                // 0x85 => self.zeroPage(Instruction{ .W = CPU(T).sta }),
                // 0x86 => self.zeroPage(Instruction{ .W = CPU(T).stx }),
                // 0x88 => self.implied(Instruction{ .R = CPU(T).dey }),
                // 0x8A => self.implied(Instruction{ .R = CPU(T).txa }),
                // 0x8C => self.absolute(Instruction{ .W = CPU(T).sty }),
                // 0x8D => self.absolute(Instruction{ .W = CPU(T).sta }),
                // 0x8E => self.absolute(Instruction{ .W = CPU(T).stx }),
                // 0x90 => self.relative(Instruction{ .R = CPU(T).bcc }),
                // 0x91 => self.indirectIndexed(Instruction{ .W = CPU(T).sta }),
                // 0x94 => self.zeroPageX(Instruction{ .W = CPU(T).sty }),
                // 0x95 => self.zeroPageX(Instruction{ .W = CPU(T).sta }),
                // 0x96 => self.zeroPageY(Instruction{ .W = CPU(T).stx }),
                // 0x98 => self.implied(Instruction{ .R = CPU(T).tay }),
                // 0x99 => self.absoluteY(Instruction{ .W = CPU(T).sta }),
                // 0x9A => self.implied(Instruction{ .R = CPU(T).txs }),
                // 0x9D => self.absoluteX(Instruction{ .W = CPU(T).sta }),
                // 0xA0 => self.immediate(Instruction{ .R = CPU(T).ldy }),
                // 0xA1 => self.indexedIndirect(Instruction{ .R = CPU(T).lda }),
                // 0xA2 => self.immediate(Instruction{ .R = CPU(T).ldx }),
                // 0xA4 => self.zeroPage(Instruction{ .R = CPU(T).ldy }),
                // 0xA5 => self.zeroPage(Instruction{ .R = CPU(T).lda }),
                // 0xA6 => self.zeroPage(Instruction{ .R = CPU(T).ldx }),
                // 0xA8 => self.implied(Instruction{ .R = CPU(T).tay }),
                // 0xA9 => self.immediate(Instruction{ .R = CPU(T).lda }),
                // 0xAA => self.implied(Instruction{ .R = CPU(T).tax }),
                // 0xAC => self.absolute(Instruction{ .R = CPU(T).ldy }),
                // 0xAD => self.absolute(Instruction{ .R = CPU(T).lda }),
                // 0xAE => self.absolute(Instruction{ .R = CPU(T).ldx }),
                // 0xB0 => self.relative(Instruction{ .R = CPU(T).bcs }),
                // 0xB1 => self.indirectIndexed(Instruction{ .R = CPU(T).lda }),
                // 0xB4 => self.zeroPageX(Instruction{ .R = CPU(T).ldy }),
                // 0xB5 => self.zeroPageX(Instruction{ .R = CPU(T).lda }),
                // 0xB6 => self.zeroPageY(Instruction{ .R = CPU(T).ldx }),
                // 0xB8 => self.implied(Instruction{ .R = CPU(T).clv }),
                // 0xB9 => self.absoluteY(Instruction{ .R = CPU(T).lda }),
                // 0xBA => self.implied(Instruction{ .R = CPU(T).tsx }),
                // 0xBC => self.absoluteX(Instruction{ .R = CPU(T).ldy }),
                // 0xBD => self.absoluteX(Instruction{ .R = CPU(T).lda }),
                // 0xBE => self.absoluteY(Instruction{ .R = CPU(T).ldx }),
                // 0xC0 => self.immediate(Instruction{ .R = CPU(T).cpy }),
                // 0xC1 => self.indexedIndirect(Instruction{ .R = CPU(T).cmp }),
                // 0xC4 => self.zeroPage(Instruction{ .R = CPU(T).cpy }),
                // 0xC5 => self.zeroPage(Instruction{ .R = CPU(T).cmp }),
                // 0xC6 => self.zeroPage(Instruction{ .RW = CPU(T).dec }),
                // 0xC8 => self.implied(Instruction{ .R = CPU(T).iny }),
                // 0xC9 => self.immediate(Instruction{ .R = CPU(T).cmp }),
                // 0xCA => self.implied(Instruction{ .R = CPU(T).dex }),
                // 0xCC => self.absolute(Instruction{ .R = CPU(T).cpy }),
                // 0xCD => self.absolute(Instruction{ .R = CPU(T).cmp }),
                // 0xCE => self.absolute(Instruction{ .RW = CPU(T).dec }),
                // 0xD0 => self.relative(Instruction{ .R = CPU(T).bne }),
                // 0xD1 => self.indirectIndexed(Instruction{ .R = CPU(T).cmp }),
                // 0xD5 => self.zeroPageX(Instruction{ .R = CPU(T).cmp }),
                // 0xD6 => self.zeroPageX(Instruction{ .RW = CPU(T).dec }),
                // 0xD8 => self.implied(Instruction{ .R = CPU(T).cld }),
                // 0xD9 => self.absoluteY(Instruction{ .R = CPU(T).cmp }),
                // 0xDD => self.absoluteX(Instruction{ .R = CPU(T).cmp }),
                // 0xDE => self.absoluteX(Instruction{ .RW = CPU(T).dec }),
                // 0xE0 => self.immediate(Instruction{ .R = CPU(T).cpx }),
                // 0xE1 => self.indexedIndirect(Instruction{ .R = CPU(T).sbc }),
                // 0xE4 => self.zeroPage(Instruction{ .R = CPU(T).cpx }),
                // 0xE5 => self.zeroPage(Instruction{ .R = CPU(T).sbc }),
                // 0xE6 => self.zeroPage(Instruction{ .RW = CPU(T).inc }),
                // 0xE8 => self.implied(Instruction{ .R = CPU(T).inx }),
                // 0xE9 => self.immediate(Instruction{ .R = CPU(T).sbc }),
                // 0xEA => self.implied(Instruction{ .R = CPU(T).nop }),
                // 0xEC => self.absolute(Instruction{ .R = CPU(T).cpx }),
                // 0xED => self.absolute(Instruction{ .R = CPU(T).sbc }),
                // 0xEE => self.absolute(Instruction{ .RW = CPU(T).inc }),
                // 0xF0 => self.relative(Instruction{ .R = CPU(T).beq }),
                // 0xF1 => self.indirectIndexed(Instruction{ .R = CPU(T).sbc }),
                // 0xF5 => self.zeroPageX(Instruction{ .R = CPU(T).sbc }),
                // 0xF6 => self.zeroPageX(Instruction{ .RW = CPU(T).inc }),
                // 0xF8 => self.implied(Instruction{ .R = CPU(T).sed }),
                // 0xF9 => self.absoluteY(Instruction{ .R = CPU(T).sbc }),
                // 0xFD => self.absoluteX(Instruction{ .R = CPU(T).sbc }),
                // 0xFE => self.absoluteX(Instruction{ .RW = CPU(T).inc }),
                else => DecodeError.InvalidOpcode,
            };
        }
    };
}

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
    try cpu.exec(0x01);

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

pub fn decode(opcode: u8) !PrettyInstruction {
    return switch (opcode) {
        0x00 => PrettyInstruction{ .type = .BRK, .mode = .Implied, .access = .R },
        0x01 => PrettyInstruction{ .type = .ORA, .mode = .IndexedIndirect, .access = .R },
        0x05 => PrettyInstruction{ .type = .ORA, .mode = .ZeroPage, .access = .R },
        0x06 => PrettyInstruction{ .type = .ASL, .mode = .ZeroPage, .access = .R },
        0x08 => PrettyInstruction{ .type = .PHP, .mode = .Implied, .access = .W },
        0x09 => PrettyInstruction{ .type = .ORA, .mode = .Immediate, .access = .R },
        0x0A => PrettyInstruction{ .type = .ASL, .mode = .Accumulator, .access = .RW },
        0x0D => PrettyInstruction{ .type = .ORA, .mode = .Absolute, .access = .R },
        0x0E => PrettyInstruction{ .type = .ASL, .mode = .Absolute, .access = .RW },
        0x10 => PrettyInstruction{ .type = .BPL, .mode = .Relative, .access = .R },
        0x11 => PrettyInstruction{ .type = .ORA, .mode = .IndirectIndexed, .access = .R },
        0x15 => PrettyInstruction{ .type = .ORA, .mode = .ZeroPageX, .access = .R },
        0x16 => PrettyInstruction{ .type = .ASL, .mode = .ZeroPageX, .access = .RW },
        0x18 => PrettyInstruction{ .type = .CLC, .mode = .Implied, .access = .R },
        0x19 => PrettyInstruction{ .type = .ORA, .mode = .AbsoluteY, .access = .R },
        0x1D => PrettyInstruction{ .type = .ORA, .mode = .AbsoluteX, .access = .R },
        0x1E => PrettyInstruction{ .type = .ASL, .mode = .AbsoluteX, .access = .RW },
        0x20 => PrettyInstruction{ .type = .JSR, .mode = .Absolute, .access = .RW },
        0x21 => PrettyInstruction{ .type = .AND, .mode = .IndexedIndirect, .access = .R },
        0x24 => PrettyInstruction{ .type = .BIT, .mode = .ZeroPage, .access = .R },
        0x25 => PrettyInstruction{ .type = .AND, .mode = .ZeroPage, .access = .R },
        0x26 => PrettyInstruction{ .type = .ROL, .mode = .ZeroPage, .access = .RW },
        0x28 => PrettyInstruction{ .type = .PLP, .mode = .Implied, .access = .R },
        0x29 => PrettyInstruction{ .type = .AND, .mode = .AbsoluteY, .access = .R },
        0x2A => PrettyInstruction{ .type = .ROL, .mode = .Accumulator, .access = .RW },
        0x2C => PrettyInstruction{ .type = .BIT, .mode = .Absolute, .access = .R },
        0x2D => PrettyInstruction{ .type = .AND, .mode = .Absolute, .access = .R },
        0x2E => PrettyInstruction{ .type = .ROL, .mode = .Absolute, .access = .RW },
        0x30 => PrettyInstruction{ .type = .BMI, .mode = .Relative, .access = .R },
        0x31 => PrettyInstruction{ .type = .AND, .mode = .IndirectIndexed, .access = .R },
        0x35 => PrettyInstruction{ .type = .AND, .mode = .ZeroPageX, .access = .R },
        0x36 => PrettyInstruction{ .type = .ROL, .mode = .ZeroPageX, .access = .RW },
        0x38 => PrettyInstruction{ .type = .SEC, .mode = .Implied, .access = .R },
        0x39 => PrettyInstruction{ .type = .AND, .mode = .AbsoluteY, .access = .R },
        0x3D => PrettyInstruction{ .type = .AND, .mode = .AbsoluteX, .access = .R },
        0x3E => PrettyInstruction{ .type = .ROL, .mode = .AbsoluteX, .access = .RW },
        0x40 => PrettyInstruction{ .type = .RTI, .mode = .Implied, .access = .R },
        0x41 => PrettyInstruction{ .type = .EOR, .mode = .IndexedIndirect, .access = .R },
        0x45 => PrettyInstruction{ .type = .EOR, .mode = .ZeroPage, .access = .R },
        0x46 => PrettyInstruction{ .type = .LSR, .mode = .ZeroPage, .access = .RW },
        0x48 => PrettyInstruction{ .type = .PHA, .mode = .Implied, .access = .W },
        0x49 => PrettyInstruction{ .type = .EOR, .mode = .Immediate, .access = .R },
        0x4A => PrettyInstruction{ .type = .LSR, .mode = .Accumulator, .access = .RW },
        0x4C => PrettyInstruction{ .type = .JMP, .mode = .Absolute, .access = .R },
        0x4D => PrettyInstruction{ .type = .EOR, .mode = .Absolute, .access = .R },
        0x4E => PrettyInstruction{ .type = .LSR, .mode = .Absolute, .access = .RW },
        0x50 => PrettyInstruction{ .type = .BVC, .mode = .Relative, .access = .R },
        0x51 => PrettyInstruction{ .type = .EOR, .mode = .IndirectIndexed, .access = .R },
        0x55 => PrettyInstruction{ .type = .EOR, .mode = .ZeroPageX, .access = .R },
        0x56 => PrettyInstruction{ .type = .LSR, .mode = .ZeroPageX, .access = .RW },
        0x58 => PrettyInstruction{ .type = .CLI, .mode = .Implied, .access = .R },
        0x59 => PrettyInstruction{ .type = .EOR, .mode = .AbsoluteY, .access = .R },
        0x5D => PrettyInstruction{ .type = .EOR, .mode = .AbsoluteX, .access = .R },
        0x5E => PrettyInstruction{ .type = .LSR, .mode = .AbsoluteX, .access = .RW },
        0x60 => PrettyInstruction{ .type = .RTS, .mode = .Implied, .access = .R },
        0x61 => PrettyInstruction{ .type = .ADC, .mode = .IndexedIndirect, .access = .R },
        0x65 => PrettyInstruction{ .type = .ADC, .mode = .ZeroPage, .access = .R },
        0x66 => PrettyInstruction{ .type = .ROR, .mode = .ZeroPage, .access = .RW },
        0x68 => PrettyInstruction{ .type = .PLA, .mode = .Implied, .access = .R },
        0x69 => PrettyInstruction{ .type = .ADC, .mode = .Immediate, .access = .R },
        0x6A => PrettyInstruction{ .type = .ROR, .mode = .Accumulator, .access = .RW },
        0x6C => PrettyInstruction{ .type = .JMP, .mode = .Indirect, .access = .R },
        0x6D => PrettyInstruction{ .type = .ADC, .mode = .Absolute, .access = .R },
        0x6E => PrettyInstruction{ .type = .ROR, .mode = .Absolute, .access = .RW },
        0x70 => PrettyInstruction{ .type = .BVS, .mode = .Relative, .access = .R },
        0x71 => PrettyInstruction{ .type = .ADC, .mode = .IndirectIndexed, .access = .R },
        0x75 => PrettyInstruction{ .type = .ADC, .mode = .ZeroPageX, .access = .R },
        0x76 => PrettyInstruction{ .type = .ROR, .mode = .ZeroPageX, .access = .RW },
        0x78 => PrettyInstruction{ .type = .SEI, .mode = .Implied, .access = .R },
        0x79 => PrettyInstruction{ .type = .ADC, .mode = .AbsoluteY, .access = .R },
        0x7D => PrettyInstruction{ .type = .ADC, .mode = .AbsoluteX, .access = .R },
        0x7E => PrettyInstruction{ .type = .ROR, .mode = .AbsoluteX, .access = .RW },
        0x81 => PrettyInstruction{ .type = .STA, .mode = .IndexedIndirect, .access = .W },
        0x84 => PrettyInstruction{ .type = .STY, .mode = .ZeroPage, .access = .W },
        0x85 => PrettyInstruction{ .type = .STA, .mode = .ZeroPage, .access = .W },
        0x86 => PrettyInstruction{ .type = .STX, .mode = .ZeroPage, .access = .W },
        0x88 => PrettyInstruction{ .type = .DEY, .mode = .Implied, .access = .R },
        0x8A => PrettyInstruction{ .type = .TXA, .mode = .Implied, .access = .R },
        0x8C => PrettyInstruction{ .type = .STY, .mode = .Absolute, .access = .W },
        0x8D => PrettyInstruction{ .type = .STA, .mode = .Absolute, .access = .W },
        0x8E => PrettyInstruction{ .type = .STX, .mode = .Absolute, .access = .W },
        0x90 => PrettyInstruction{ .type = .BCC, .mode = .Relative, .access = .R },
        0x91 => PrettyInstruction{ .type = .STA, .mode = .IndirectIndexed, .access = .W },
        0x94 => PrettyInstruction{ .type = .STY, .mode = .ZeroPageX, .access = .W },
        0x95 => PrettyInstruction{ .type = .STA, .mode = .ZeroPageX, .access = .W },
        0x96 => PrettyInstruction{ .type = .STX, .mode = .ZeroPageY, .access = .W },
        0x98 => PrettyInstruction{ .type = .TAY, .mode = .Implied, .access = .R },
        0x99 => PrettyInstruction{ .type = .STA, .mode = .AbsoluteY, .access = .W },
        0x9A => PrettyInstruction{ .type = .TXS, .mode = .Implied, .access = .R },
        0x9D => PrettyInstruction{ .type = .STA, .mode = .AbsoluteX, .access = .W },
        0xA0 => PrettyInstruction{ .type = .LDY, .mode = .Immediate, .access = .R },
        0xA1 => PrettyInstruction{ .type = .LDA, .mode = .IndexedIndirect, .access = .R },
        0xA2 => PrettyInstruction{ .type = .LDX, .mode = .Immediate, .access = .R },
        0xA4 => PrettyInstruction{ .type = .LDY, .mode = .ZeroPage, .access = .R },
        0xA5 => PrettyInstruction{ .type = .LDA, .mode = .ZeroPage, .access = .R },
        0xA6 => PrettyInstruction{ .type = .LDX, .mode = .ZeroPage, .access = .R },
        0xA8 => PrettyInstruction{ .type = .TAY, .mode = .Implied, .access = .R },
        0xA9 => PrettyInstruction{ .type = .LDA, .mode = .Immediate, .access = .R },
        0xAA => PrettyInstruction{ .type = .TAX, .mode = .Implied, .access = .R },
        0xAC => PrettyInstruction{ .type = .LDY, .mode = .Absolute, .access = .R },
        0xAD => PrettyInstruction{ .type = .LDA, .mode = .Absolute, .access = .R },
        0xAE => PrettyInstruction{ .type = .LDX, .mode = .Absolute, .access = .R },
        0xB0 => PrettyInstruction{ .type = .BCS, .mode = .Relative, .access = .R },
        0xB1 => PrettyInstruction{ .type = .LDA, .mode = .IndirectIndexed, .access = .R },
        0xB4 => PrettyInstruction{ .type = .LDY, .mode = .ZeroPageX, .access = .R },
        0xB5 => PrettyInstruction{ .type = .LDA, .mode = .ZeroPageX, .access = .R },
        0xB6 => PrettyInstruction{ .type = .LDX, .mode = .ZeroPageY, .access = .R },
        0xB8 => PrettyInstruction{ .type = .CLV, .mode = .Implied, .access = .R },
        0xB9 => PrettyInstruction{ .type = .LDA, .mode = .AbsoluteY, .access = .R },
        0xBA => PrettyInstruction{ .type = .TSX, .mode = .Implied, .access = .R },
        0xBC => PrettyInstruction{ .type = .LDY, .mode = .AbsoluteX, .access = .R },
        0xBD => PrettyInstruction{ .type = .LDA, .mode = .AbsoluteX, .access = .R },
        0xBE => PrettyInstruction{ .type = .LDX, .mode = .AbsoluteY, .access = .R },
        0xC0 => PrettyInstruction{ .type = .CPY, .mode = .Immediate, .access = .R },
        0xC1 => PrettyInstruction{ .type = .CMP, .mode = .IndexedIndirect, .access = .R },
        0xC4 => PrettyInstruction{ .type = .CPY, .mode = .ZeroPage, .access = .R },
        0xC5 => PrettyInstruction{ .type = .CMP, .mode = .ZeroPage, .access = .R },
        0xC6 => PrettyInstruction{ .type = .DEC, .mode = .ZeroPage, .access = .RW },
        0xC8 => PrettyInstruction{ .type = .INY, .mode = .Implied, .access = .R },
        0xC9 => PrettyInstruction{ .type = .CMP, .mode = .Immediate, .access = .R },
        0xCA => PrettyInstruction{ .type = .DEX, .mode = .Implied, .access = .R },
        0xCC => PrettyInstruction{ .type = .CPY, .mode = .Absolute, .access = .R },
        0xCD => PrettyInstruction{ .type = .CMP, .mode = .Absolute, .access = .R },
        0xCE => PrettyInstruction{ .type = .DEC, .mode = .Absolute, .access = .RW },
        0xD0 => PrettyInstruction{ .type = .BNE, .mode = .Relative, .access = .R },
        0xD1 => PrettyInstruction{ .type = .CMP, .mode = .IndirectIndexed, .access = .R },
        0xD5 => PrettyInstruction{ .type = .CMP, .mode = .ZeroPageX, .access = .R },
        0xD6 => PrettyInstruction{ .type = .DEC, .mode = .ZeroPageX, .access = .RW },
        0xD8 => PrettyInstruction{ .type = .CLD, .mode = .Implied, .access = .R },
        0xD9 => PrettyInstruction{ .type = .CMP, .mode = .AbsoluteY, .access = .R },
        0xDD => PrettyInstruction{ .type = .CMP, .mode = .AbsoluteX, .access = .R },
        0xDE => PrettyInstruction{ .type = .DEC, .mode = .AbsoluteX, .access = .RW },
        0xE0 => PrettyInstruction{ .type = .CPX, .mode = .Immediate, .access = .R },
        0xE1 => PrettyInstruction{ .type = .SBC, .mode = .IndexedIndirect, .access = .R },
        0xE4 => PrettyInstruction{ .type = .CPX, .mode = .ZeroPage, .access = .R },
        0xE5 => PrettyInstruction{ .type = .SBC, .mode = .ZeroPage, .access = .R },
        0xE6 => PrettyInstruction{ .type = .INC, .mode = .ZeroPage, .access = .RW },
        0xE8 => PrettyInstruction{ .type = .INX, .mode = .Implied, .access = .R },
        0xE9 => PrettyInstruction{ .type = .SBC, .mode = .Immediate, .access = .R },
        0xEA => PrettyInstruction{ .type = .NOP, .mode = .Implied, .access = .R },
        0xEC => PrettyInstruction{ .type = .CPX, .mode = .Absolute, .access = .R },
        0xED => PrettyInstruction{ .type = .SBC, .mode = .Absolute, .access = .R },

        0xF0 => PrettyInstruction{ .type = .BEQ, .mode = .Relative, .access = .R },
        0xF1 => PrettyInstruction{ .type = .SBC, .mode = .IndirectIndexed, .access = .R },
        0xF5 => PrettyInstruction{ .type = .SBC, .mode = .ZeroPageX, .access = .R },
        0xF6 => PrettyInstruction{ .type = .INC, .mode = .ZeroPageX, .access = .RW },
        0xF8 => PrettyInstruction{ .type = .SED, .mode = .Implied, .access = .R },
        0xF9 => PrettyInstruction{ .type = .SBC, .mode = .AbsoluteY, .access = .R },
        0xFD => PrettyInstruction{ .type = .SBC, .mode = .AbsoluteX, .access = .R },
        0xFE => PrettyInstruction{ .type = .INC, .mode = .AbsoluteX, .access = .RW },
        else => DecodeError.InvalidOpcode,
    };
}

const PrettyInstruction = struct {
    type: InstructionType,
    mode: AddressMode,
    access: MemoryAccess,
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
