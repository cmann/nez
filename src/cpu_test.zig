const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;
const warn = std.debug.warn;

const CPU = @import("cpu.zig");

const a = std.testing.allocator;

const Context = struct {
    memory: []u8,

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

test "6502_functional_test" {
    var context = try Context.init();
    context.memory = try a.alloc(u8, 0x10000);
    defer a.free(context.memory);

    const file = try (fs.cwd().openFile("../rom/6502_functional_test.bin", .{}));
    errdefer file.close();

    _ = try file.readAll(context.memory);
    file.close();

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
