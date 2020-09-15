const std = @import("std");
const warn = std.debug.warn;

const CPU = @import("cpu.zig");
const PPU = @import("ppu.zig");

const a = std.testing.allocator;

const MappedRegisters = enum(u8) {
    PPUCTRL = 0x2000,
    PPUMASK = 0x2001,
    PPUSTATUS = 0x2002,
    OAMADDR = 0x2003,
    OAMDATA = 0x2004,
    PPUSCROLL = 0x2005,
    PPUADDR = 0x2006,
    PPUDATA = 0x2007,
    OAMDMA = 0x4014,
};

const NESContext = struct {
    cpuMemory: []u8 = undefined,
    ppuMemory: []u8 = undefined,

    pub fn init() Context {
        return Context{
            .cpuMemory = a.alloc(u8, 0x0800),
            .ppuMemory = a.alloc(u8, 0x4000),
        };
    }

    pub fn deinit(self: *Context) void {
        a.free(self.cpuMemory);
        a.free(self.ppuMemory);
    }

    pub fn tick(self: *Context, in: CPU.Pins) CPU.Pins {
        var out = in;

        out = switch (pins.a) {
            0x0000...0x1FFF => self.cpuMemoryAccess(pin),
            0x2000...0x3FFF => self.ppuAccess(pins),
            // 0x4000...0x4017 => self.apuIOStuff(addr),
            // 0x4018...0x401F => self.apuIODisabledStuff(addr),
            // 0x4020...0xFFFF => self.cartridgeAccess(addr),
            else => pins, // Temporary do nothing
        };

        return out;
    }

    fn cpuMemoryAccess(self: *Context, in: CPU.Pins) CPU.Pins {
        const out = in;

        const addr = switch (pins.a) {
            0x0000...0x07FF => pins.a,
            0x0800...0x1FFF => pins.a % 0x0800,
            else => unreachable,
        };

        if (in.rw) {
            out.d = self.memory[addr];
        } else {
            self.memory[addr] = in.d;
        }

        return out;
    }

    fn ppuAccess(self: *Context, in: CPU.Pins) CPU.Pins {
        const out = in;

        const addr = switch (pins.a) {
            0x2000...0x2007 => pins.a,
            0x2008...0x3FFF => 0x2000 + pins.a % 0x2008,
            else => unreachable,
        };
    }
};
