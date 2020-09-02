const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;

const functional_test_bin = @embedFile("../6502_functional_test.bin");

test "functional test" {
    var a: u8 = 0b01000001;
    var b = @bitCast(i8, a);
    var c: u8 = 0;
    if (b >= 0) {
        c = @intCast(u8, b);
    } else {
        c = @intCast(u8, b * -1);
    }
    warn("\n{} {}\n", .{ b, c });
    assert(@bitCast(i8, a) == -127);
}
