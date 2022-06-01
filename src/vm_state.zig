const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const go = @import("game_object.zig");

pub const TOTAL_VARS: usize = 256;
pub const TOTAL_FLAGS: usize = 256;
pub const TOTAL_CONTROLLERS: usize = 50;
pub const TOTAL_STRINGS: usize = 24;
// also called screen objs.
pub const TOTAL_GAME_OBJS: usize = 16;

pub const VMState = struct {
    const Self = @This();

    vars: [TOTAL_VARS]u8 = std.mem.zeroes([TOTAL_VARS]u8),
    flags: [TOTAL_FLAGS]bool = std.mem.zeroes([TOTAL_FLAGS]bool),
    gameObjects: [TOTAL_GAME_OBJS]go.GameObject = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject),

    pub fn init() Self {
        return Self{};
    }

    pub fn reset(self: *Self) void {
        self.vars = std.mem.zeroes([TOTAL_VARS]u8);
        self.flags = std.mem.zeroes([TOTAL_FLAGS]bool);
        self.gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject);
    }
};

test "vm inits, sets some random data and then is reset" {
    var vms = VMState.init();

    vms.vars[23] = 0xff;
    vms.vars[19] = 0xff;

    vms.flags[23] = true;
    vms.flags[19] = true;

    vms.gameObjects[6] = go.GameObject.init();
    vms.gameObjects[11] = go.GameObject.init();

    vms.reset();

    // Ensure original vm state is equal to a freshly initialized vm state.
    var freshVms = VMState.init();
    try testing.expect(std.meta.eql(freshVms, vms));
}
