const std = @import("std");
const Allocator = std.mem.Allocator;
const warn = std.debug.warn;

const CPU = @import("cpu.zig");
const PPU = @import("ppu.zig");

pub const NES = struct {
    cpu: CPU.CPU(NES),
    cpuMemory: []u8,

    ppu: PPU.PPU,
    ppuPins: PPU.Pins,
    ppuMemory: []u8,

    a: *Allocator,

    pub fn init(a: *Allocator) !NES {
        return NES{
            .cpuMemory = try a.alloc(u8, 0x0800),
            .ppuMemory = try a.alloc(u8, 0x4000),
            .ppu = try PPU.PPU.init(a),
            .a = a,
        };
    }

    pub fn deinit(self: *Context) void {
        self.a.free(self.cpuMemory);
        self.a.free(self.ppuMemory);
        self.ppu.deinit();
    }

    pub fn tick(self: *Context, cpuIn: CPU.Pins) CPU.Pins {
        var cpuOut = switch (pins.a) {
            0x0000...0x1FFF => self.cpuMemoryAccess(cpuIn),
            // 0x4000...0x4017 => self.apuIOStuff(addr),
            // 0x4018...0x401F => self.apuIODisabledStuff(addr),
            // 0x4020...0xFFFF => self.cartridgeAccess(addr),
            else => cpuIn, // Temporary do nothing
        };

        cpuOut = self.tickPPU(cpuOut);

        return cpuOut;
    }

    fn tickPPU(self: *Context, cpuIn: CPU.Pins) CPU.Pins {
        var cpuOut = cpuIn;

        const addr = switch (cpuIn.a) {
            0x2000...0x2007 => cpuIn.a,
            0x2008...0x3FFF => 0x2000 + cpuIn.a % 0x2008,
            else => 0,
        };

        if (addr != 0) {
            self.ppuPins.regA = @truncate(u4, addr) & 0x7;
            self.ppuPins.regD = cpuIn.d;
            self.ppuPins.rw = cpuIn.rw;
        }

        self.ppuPins = self.ppu.tick(self.ppuPins);

        cpuOut.d = self.ppuPins.d;

        self.ppuPins = self.ppu.tick(self.ppuPins);
        self.ppuPins = self.ppu.tick(self.ppuPins);

        return cpuOut;
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
};
