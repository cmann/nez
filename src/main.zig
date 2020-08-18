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

const Context = struct {
    registers: Registers,
    memory: []u8,

    pub fn init() Context {
        return Context{
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

// Address Modes:
//
// A        Accumulator            OPC A         operand is AC (implied single byte instruction)
// abs      absolute               OPC $LLHH     operand is address $HHLL *
// abs,X    absolute, X-indexed    OPC $LLHH,X   operand is address; effective address is address incremented by X with carry **
// abs,Y    absolute, Y-indexed    OPC $LLHH,Y   operand is address; effective address is address incremented by Y with carry **
// #        immediate              OPC #$BB      operand is byte BB
// impl     implied                OPC           operand implied
// ind      indirect               OPC ($LLHH)   operand is address; effective address is contents of word at address: C.w($HHLL)
// X,ind    X-indexed, indirect    OPC ($LL,X)   operand is zeropage address; effective address is word in (LL + X, LL + X + 1), inc. without carry: C.w($00LL + X)
// ind,Y    indirect, Y-indexed    OPC ($LL),Y   operand is zeropage address; effective address is word in (LL, LL + 1) incremented by Y with carry: C.w($00LL) + Y
// rel      relative               OPC $BB       branch target is PC + signed offset BB ***
// zpg      zeropage               OPC $LL       operand is zeropage address (hi-byte is zero, address = $00LL)
// zpg,X    zeropage, X-indexed    OPC $LL,X     operand is zeropage address; effective address is address incremented by X without carry **
// zpg,Y    zeropage, Y-indexed    OPC $LL,Y     operand is zeropage address; effective address is address incremented by Y without carry **
//
// *   16-bit address words are little endian, lo(w)-byte first, followed by the high-byte.
// (An assembler will use a human readable, big-endian notation as in $HHLL.)
//
// **  The available 16-bit address space is conceived as consisting of pages of 256 bytes each, with
// address hi-bytes representing the page index. An increment with carry may affect the hi-byte
// and may thus result in a crossing of page boundaries, adding an extra cycle to the execution.
// Increments without carry do not affect the hi-byte of an address and no page transitions do occur.
// Generally, increments of 16-bit addresses include a carry, increments of zeropage addresses don't.
// Notably this is not related in any way to the state of the carry bit of the accumulator.
//
// *** Branch offsets are signed 8-bit values, -128 ... +127, negative offsets in two's complement.
// Page transitions may occur and add an extra cycle to the execution.
const instructions = [_]u8{
    //  00           01        02       03       04           05           06        07        08          09          0A        0B       0C           0D           0E         0F
    "BRK impl", "ORA X,ind", "---",   "---", "---",       "ORA zpg",   "ASL zpg",   "---", "PHP impl", "ORA #",     "ASL A",    "---", "---",       "ORA abs",   "ASL abs",   "---", // 00
    "BPL rel",  "ORA ind,Y", "---",   "---", "---",       "ORA zpg,X", "ASL zpg,X", "---", "CLC impl", "ORA abs,Y", "---",      "---", "---",       "ORA abs,X", "ASL abs,X", "---", // 10
    "JSR abs",  "AND X,ind", "---",   "---", "BIT zpg",   "AND zpg",   "ROL zpg",   "---", "PLP impl", "AND #",     "ROL A",    "---", "BIT abs",   "AND abs",   "ROL abs",   "---", // 20
    "BMI rel",  "AND ind,Y", "---",   "---", "---",       "AND zpg,X", "ROL zpg,X", "---", "SEC impl", "AND abs,Y", "---",      "---", "---",       "AND abs,X", "ROL abs,X", "---", // 30
    "RTI impl", "EOR X,ind", "---",   "---", "---",       "EOR zpg",   "LSR zpg",   "---", "PHA impl", "EOR #",     "LSR A",    "---", "JMP abs",   "EOR abs",   "LSR abs",   "---", // 40
    "BVC rel",  "EOR ind,Y", "---",   "---", "---",       "EOR zpg,X", "LSR zpg,X", "---", "CLI impl", "EOR abs,Y", "---",      "---", "---",       "EOR abs,X", "LSR abs,X", "---", // 50
    "RTS impl", "ADC X,ind", "---",   "---", "---",       "ADC zpg",   "ROR zpg",   "---", "PLA impl", "ADC #",     "ROR A",    "---", "JMP ind",   "ADC abs",   "ROR abs",   "---", // 60
    "BVS rel",  "ADC ind,Y", "---",   "---", "---",       "ADC zpg,X", "ROR zpg,X", "---", "SEI impl", "ADC abs,Y", "---",      "---", "---",       "ADC abs,X", "ROR abs,X", "---", // 70
    "---",      "STA X,ind", "---",   "---", "STY zpg",   "STA zpg",   "STX zpg",   "---", "DEY impl", "---",       "TXA impl", "---", "STY abs",   "STA abs",   "STX abs",   "---", // 80
    "BCC rel",  "STA ind,Y", "---",   "---", "STY zpg,X", "STA zpg,X", "STX zpg,Y", "---", "TYA impl", "STA abs,Y", "TXS impl", "---", "---",       "STA abs,X", "---",       "---", // 90
    "LDY #",    "LDA X,ind", "LDX #", "---", "LDY zpg",   "LDA zpg",   "LDX zpg",   "---", "TAY impl", "LDA #",     "TAX impl", "---", "LDY abs",   "LDA abs",   "LDX abs",   "---", // A0
    "BCS rel",  "LDA ind,Y", "---",   "---", "LDY zpg,X", "LDA zpg,X", "LDX zpg,Y", "---", "CLV impl", "LDA abs,Y", "TSX impl", "---", "LDY abs,X", "LDA abs,X", "LDX abs,Y", "---", // B0
    "CPY #",    "CMP X,ind", "---",   "---", "CPY zpg",   "CMP zpg",   "DEC zpg",   "---", "INY impl", "CMP #",     "DEX impl", "---", "CPY abs",   "CMP abs",   "DEC abs",   "---", // C0
    "BNE rel",  "CMP ind,Y", "---",   "---", "---",       "CMP zpg,X", "DEC zpg,X", "---", "CLD impl", "CMP abs,Y", "---",      "---", "---",       "CMP abs,X", "DEC abs,X", "---", // D0
    "CPX #",    "SBC X,ind", "---",   "---", "CPX zpg",   "SBC zpg",   "INC zpg",   "---", "INX impl", "SBC #",     "NOP impl", "---", "CPX abs",   "SBC abs",   "INC abs",   "---", // E0
    "BEQ rel",  "SBC ind,Y", "---",   "---", "---",       "SBC zpg,X", "INC zpg,X", "---", "SED impl", "SBC abs,Y", "---",      "---", "---",       "SBC abs,X", "INC abs,X", "---", // F0
};

const AddressMode = enum {
    // Non-indexed, non-memory
    Accumulator,
    Immediate,
    Implied,
    // Non-indexed, memory
    Relative,
    Absolute,
    ZeroPage,
    Indirect,
    // Indexed, memory
    AbsoluteX,
    AbsoluteY,
    ZeroPageX,
    ZeroPageY,
    IndexedIndirect,
    IndirectIndexed,

    pub fn load(mode: AddressMode, context: Context) ![]u8 {
        const val = switch (mode) {
            Accumulator => context.registers.a,
            Immediate => context.memory[context.registers.pc + 1],
            Relative => context.registers.pc + @bitCast(i8, context.memory[context.registers.pc + 1]),
            Absolute => context.memory[context.memory[context.registers.pc + 1] + context.memory[context.registers.pc + 2]],
            ZeroPage => context.memory[context.memory[context.registers.pc + 1]],

            Implied => 0xff,
        };
    }
};

const modes = [_]addressModes{};

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

    var i: usize = 0x0400;
    while (i < 0x3399) : (i += 1) {
        const opc = bin[i];

        std.debug.warn("{x:2}\n", .{opc});
    }

    var context = Context.init();
}
