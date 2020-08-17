const std = @import("std");
const fs = std.fs;
const process = std.process;

var a: *std.mem.Allocator = undefined;

const Flags = struct {
    carry: bool,
    zero: bool,
    interruptDisable: bool,
    decimalMode: bool,
    brk: bool,
    unused: bool,
    overflow: bool,
    negative: bool,
};

const Registers = struct {
    pc: u16,
    sp: u8,
    p: u8,
    a: u8,
    x: u8,
    y: u8,
};

const CPU = struct {
    registers: Registers,
    // flags: Flags,
    memory: [0x10000]u8,

    pub fn powerOn() CPU {
        return CPU{
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

    var cpu = CPU.powerOn();
}
