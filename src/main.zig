const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const LoadError = error{ UnsupportedMapper, UnsupportedFormat, InvalidFormat };

const Flags = struct {
    mirroring: bool,
    battery: bool,
    trainer: bool,
    ignore: bool,
    mapper: u8,
};

pub fn load(path: []const u8, memory: []u8) !void {
    const file = try fs.cwd().openFile(path, .{});
    var header: [16]u8 = undefined;

    const read = try file.read(header[0..header.len]);
    if (read != 16)
        return LoadError.InvalidFormat;

    if (!mem.eql(u8, header[0..3], "\x4E\x45\x53\x1A"))
        return LoadError.UnsupportedFormat;

    const flags = Flags{
        .mirroring = header[6] & 0b1 == 0b1,
        .battery = header[6] & 0b10 == 0b10,
        .trainer = header[6] & 0b100 == 0b100,
        .ignore = header[6] & 0b1000 == 0b1000,
        .mapper = (header[7] & 0b11110000) | (header[6] & 0b11110000 >> 4),
    };

    if (flags.mapper != 0)
        return LoadError.UnsupportedMapper;

    const prgSize = @as(usize, header[4]) * 16 * 1024;
    const chrSize = @as(usize, header[5]) * 8 * 1024;

    const prgStart: usize = if (flags.trainer) 16 + 512 else 16;
    const chrStart = prgStart + prgSize;

    try file.seekTo(prgStart);
    _ = try file.read(memory[0x8000 .. 0x8000 + prgSize]);

    if (prgSize <= 16 * 1024)
        mem.copy(u8, memory[0x8000..0xC000], memory[0xC000..0x10000]);
}

pub fn main() !void {
    var foo = "asdfasdf";
    var memory: [0x10000]u8 = undefined;
    try load(foo, &memory);
}
