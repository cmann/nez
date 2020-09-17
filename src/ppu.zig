const Registers = struct {
    ctrl: packed struct {
        raw: u8, flags: packed struct {
            nn: u2,
            i: bool,
            s: bool,
            h: bool,
            p: bool,
            v: bool,
        }
    },
    mask: packed struct {
        raw: u8, flags: packed struct {
            g: bool,
            m: bool,
            M: bool,
            b: bool,
            s: bool,
            bgr: u3,
        }
    },
    status: packed struct {
        raw: u8, flags: packed struct {
            padding: u5,
            o: bool,
            s: bool,
            v: bool,
        }
    },
    oamaddr: u8,
    oamdata: u8,
    scroll: u8,
    addr: u8,
    data: u8,
    oamdma: u8,
};

const Pins = struct {
    regD: u8,
    regA: u4,
    a: u14,
    d: u8,
    rw: bool,
    int: bool,
    rd: bool,
    wr: bool,
};

pub fn PPU(comptime T: type) type {
    return struct {
        registers: Registers,
        pins: Pins,
        oam: []u8,
        cycle: u32,
        context: *T,

        pub fn init(context: *T) PPU(T) {
            return PPU(T){
                .context = context,
            };
        }

        fn tick(self: *PPU(T), in: Pins) Pins {
            var out = in;

            if (pins.rw) {
                out.regD = switch (pins.regA) {
                    0x2000 => self.registers.ctrl,
                    0x2001 => self.registers.mask,
                    0x2002 => self.registers.status,
                    0x2003 => self.registers.oamaddr,
                    0x2004 => self.registers.oamdata,
                    0x2005 => self.registers.scroll,
                    0x2006 => self.registers.addr,
                    0x2007 => self.registers.data,
                    0x4014 => self.registers.oamdma,
                };
            } else {
                _ = switch (pins.regA) {
                    0x2000 => self.registers.ctrl = in.regD,
                    0x2001 => self.registers.mask = in.regD,
                    0x2002 => self.registers.status = in.regD,
                    0x2003 => self.registers.oamaddr = in.regD,
                    0x2004 => self.registers.oamdata = in.regD,
                    0x2005 => self.registers.scroll = in.regD,
                    0x2006 => self.registers.addr = in.regD,
                    0x2007 => self.registers.data = in.regD,
                    0x4014 => self.registers.oamdma = in.regD,
                };
            }
        }
    };
}
