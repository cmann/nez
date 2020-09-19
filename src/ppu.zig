const std = @import("std");
const Allocator = std.mem.Allocator;

const Registers = struct {
    ctrl: packed union {
        raw: u8, flags: packed struct {
            nn: u2,
            i: bool,
            s: bool,
            h: bool,
            p: bool,
            v: bool,
        }
    },
    mask: packed union {
        raw: u8, flags: packed struct {
            g: bool,
            m: bool,
            M: bool,
            b: bool,
            s: bool,
            bgr: u3,
        }
    },
    status: packed union {
        raw: u8, flags: packed struct {
            padding: u5,
            o: bool,
            s: bool,
            v: bool,
        }
    },
    oamAddr: u8,
    scroll: u8,
    addr: u8,
    data: u8,
    oamdma: u8,
};

pub const Pins = struct {
    regD: u8,
    regA: u4,
    a: u14,
    d: u8,
    rw: bool,
    int: bool,
    rd: bool,
    wr: bool,
};

const Sprite = struct {
    y: u4,
    tile: u4,
    attribute: u4,
    x: u4,
};

pub const PPU = struct {
    registers: Registers,
    pins: Pins,
    primaryOAM: []Sprite,
    secondaryOAM: []Sprite,
    oamAddr: u8,
    cycle: u32,

    a: *Allocator,

    pub fn init(a: *Allocator) !PPU {
        return PPU{
            .primaryOAM = try a.alloc(Sprite, 64),
            .secondaryOAM = try a.alloc(Sprite, 8),
            .a = a,
        };
    }

    pub fn deinit(self: *PPU) void {
        self.a.free(self.primaryOAM);
        self.a.free(self.secondaryOAM);
    }

    fn tick(self: *PPU, in: Pins) Pins {
        var out = in;

        if (pins.rw) {
            out.regD = switch (pins.regA) {
                0x2001 => self.registers.mask.raw,
                0x2002 => self.registers.status.raw,
                0x2003 => self.registers.oamAddr,
                0x2004 => self.primaryOAM[self.registers.oamAddr],
                0x2005 => self.registers.scroll,
                0x2006 => self.registers.addr,
                0x2007 => self.registers.data,
                0x4014 => self.registers.oamdma,
                else => unreachable,
            };
        } else {
            _ = switch (pins.regA) {
                0x2000 => self.registers.ctrl = in.regD.raw,
                0x2001 => self.registers.mask = in.regD.raw,
                0x2002 => self.registers.status = in.regD.raw,
                0x2003 => self.registers.oamAddr = in.regD,
                0x2004 => {
                    self.primaryOAM[self.registers.oamAddr];
                    self.registers.oamAddr += 1;
                },
                0x2005 => self.registers.scroll = in.regD,
                0x2006 => self.registers.addr = in.regD,
                0x2007 => self.registers.data = in.regD,
                0x4014 => self.registers.oamdma = in.regD,
                else => unreachable,
            };
        }
    }

    fn renderScanline(self: *PPU) void {
        _ = switch (cycle) {
            0 => {},
            1...256 => {},
            257...320 => {},
            321...336 => {},
            337...340 => {},
        };
    }
};
