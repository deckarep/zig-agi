pub const LogicControlOpCode = enum(u8) {
    const Self = @This();

    Return = 0x00,
    Or = 0xFC,
    Not = 0xFD,
    Else = 0xFE,
    If = 0xFF,

    SetScan = 0x91,
    ResetScan = 0x92,

    pub inline fn into(e: Self) u8 {
        return @enumToInt(e);
    }
};
