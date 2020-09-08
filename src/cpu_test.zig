const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;
const warn = std.debug.warn;

const CPU = @import("cpu.zig");

const Context = struct {
    memory: [0x10000]u8,

    pub fn init() !Context {
        return Context{
            .memory = undefined,
        };
    }

    pub fn tick(self: *Context, cur: CPU.Pins) CPU.Pins {
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

test "functional test" {
    var context = try Context.init();

    const file = try (fs.cwd().openFile("../6502_functional_test.bin", .{}));
    _ = try file.readAll(&context.memory);

    var cpu = CPU.CPU(Context).init(&context);

    cpu.registers.pc = 0x0400;
    cpu.pins.a = 0x0400;
    cpu.pins.d = 0xD8;

    while (true) {
        const pc = cpu.registers.pc;
        const opcode = context.memory[pc];
        const instruction = try CPU.decode(opcode);

        cpu.step() catch |err| {
            if (cpu.registers.pc == 0x369B) {
                break;
            }

            warn("{X}: {} {} {}\n", .{ pc, instruction.type, instruction.mode, instruction.access });
            warn("REGISTERS: {X}\n", .{cpu.registers});
            warn("P: {X}\n", .{cpu.registers.p.flags});
            return err;
        };
    }
}
