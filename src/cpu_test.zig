const std = @import("std");
const assert = std.debug.assert;
const fs = std.fs;
const warn = std.debug.warn;

const c = @cImport(@cInclude("sys/time.h"));

const CPU = @import("cpu.zig");

const a = std.testing.allocator;

const Context = struct {
    memory: []u8 = undefined,
    cycles: u64 = 0,

    pub fn tick(self: *Context, cur: CPU.Pins) CPU.Pins {
        self.cycles += 1;
        var next = cur;

        if (cur.rw) {
            next.d = self.memory[cur.a];
        } else {
            self.memory[cur.a] = cur.d;
        }

        return next;
    }
};

const InterruptContext = struct {
    memory: []u8 = undefined,

    pub fn tick(self: *InterruptContext, cur: CPU.Pins) CPU.Pins {
        var next = cur;

        if (cur.rw) {
            next.d = self.memory[cur.a];
        } else {
            self.memory[cur.a] = cur.d;
            if (cur.a == 0xBFFC) {
                next.irq = cur.d & 0b1 == 0;
                next.nmi = cur.d & 0b10 == 0;
            }
        }

        return next;
    }
};

test "6502_functional_test" {
    var context = Context{ .memory = try a.alloc(u8, 0x10000) };
    defer a.free(context.memory);

    const file = try (fs.cwd().openFile("../rom/6502_functional_test.bin", .{}));
    defer file.close();

    _ = try file.readAll(context.memory);

    var cpu = CPU.CPU(Context).init(&context);

    cpu.registers.pc = 0x0400;
    cpu.pins.a = 0x0400;
    cpu.pins.d = context.memory[cpu.registers.pc];

    var start = c.timeval{ .tv_sec = 0, .tv_usec = 0 };
    var end = c.timeval{ .tv_sec = 0, .tv_usec = 0 };

    _ = c.gettimeofday(&start, null);

    while (true) {
        const pc = cpu.registers.pc;

        cpu.step() catch |err| {
            if (cpu.registers.pc == 0x369B) {
                break;
            }

            const opcode = context.memory[pc];
            const instruction = try CPU.decode(opcode);
            warn("{X}: {} {} {}\n", .{ pc, instruction.type, instruction.mode, instruction.access });
            warn("REGISTERS: {X}\n", .{cpu.registers});
            warn("P: {X}\n", .{cpu.registers.p.flags});
            return err;
        };
    }

    _ = c.gettimeofday(&end, null);

    const usec = (end.tv_sec - start.tv_sec) * 1000000 + end.tv_usec - start.tv_usec;
    const sec = @intToFloat(f64, usec);
    warn("\nCPS: {} cycles / {d} useconds = {d} MHz\n", .{ context.cycles, sec, @intToFloat(f64, context.cycles) / sec });
}

test "6502_interrupt_test" {
    var context = InterruptContext{ .memory = try a.alloc(u8, 0x10000) };
    defer a.free(context.memory);

    const file = try (fs.cwd().openFile("../rom/6502_interrupt_test.bin", .{}));
    defer file.close();

    _ = try file.readAll(context.memory);

    var cpu = CPU.CPU(InterruptContext).init(&context);

    cpu.registers.pc = 0x0400;
    cpu.pins.a = 0x0400;
    cpu.pins.d = context.memory[cpu.registers.pc];
    context.memory[0xBFFC] = 0;

    while (true) {
        const pc = cpu.registers.pc;

        cpu.step() catch |err| {
            if (pc == 0x06F5) {
                break;
            }

            const opcode = context.memory[pc];
            const instruction = try CPU.decode(opcode);
            warn("{X}: {} {} {}\n", .{ pc, instruction.type, instruction.mode, instruction.access });
            warn("REGISTERS: {X}\n", .{cpu.registers});
            warn("P: {X}\n", .{cpu.registers.p.flags});
            return err;
        };

        if (cpu.registers.pc == pc) {
            break;
        }
    }
}
