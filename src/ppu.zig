const Registers = struct {
    ctrl: u8,
    mask: u8,
    status: u8,
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
    rw: bool,
    int: bool,
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

        fn tick(self: *PPU(T), pins: Pins) Pins {
            // switch (pins.regA) {
            //     0x2000 => self.registers.ctrl = pins.regD,
            //     0x2001 => self.registers.mask = pins.regD,
            //     0x2002 => self.registers.status = pins.regD,
            //     0x2003 => self.registers.oamaddr = pins.regD,
            //     0x2004 => self.registers.oamdata = pins.regD,
            //     0x2005 => self.registers.scroll = pins.regD,
            //     0x2006 => self.registers.addr = pins.regD,
            //     0x2007 => self.registers.data = pins.regD,
            //     0x4014 => self.registers.oamdma = pins.regD,
            // }
        }
    };
}
