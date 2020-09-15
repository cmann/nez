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
    d: u8,
    a: u4,
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

        fn tick(self: *PPU(T)) void {}
    };
}
