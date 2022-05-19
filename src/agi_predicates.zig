const std = @import("std");
const assert = std.debug.assert;
const vm = @import("vm.zig");
const aw = @import("args.zig");

// AGI Predicate invocations.

// nop is for a known command that we just consume it's args but ignore.
pub fn agi_nop(self: *vm.VM, args: *aw.Args) anyerror!bool {
    self.vm_log("agi_nop({any})...SKIPPING.", .{args.buf});
    return false;
}

// AGI Test invocations.
pub fn agi_test_equaln(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo = args.get.a();
    const val = args.get.b();

    return self.read_var(varNo) == val;
}

pub fn agi_test_equalv(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    return try agi_test_equaln(self, args.pack());
}

pub fn agi_test_greatern(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo = args.get.a();
    const val = args.get.b();

    return self.read_var(varNo) > val;
}

pub fn agi_test_isset(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const flagNo = args.get.a();

    return self.get_flag(flagNo);
}

pub fn agi_test_controller(_: *vm.VM, _: *aw.Args) anyerror!bool {
    return false;
}

pub fn agi_test_have_key(self: *vm.VM, _: *aw.Args) anyerror!bool {
    var hk = self.haveKey;
    self.haveKey = false;
    return hk;
}

// agi_test_said needs to handle the args in a special way as they are u16 (little-endian) args
// Therefore, this is the *ONLY* function where it's handled in a hacky way
// Fuck you, it's called pragmatism and you should try it sometime
// Fuck you again, yes I'm missing punctuation to end my sentences
pub fn agi_test_said(self: *vm.VM, args: *aw.Args) anyerror!bool { //args: []const u16) bool {
    // consume the args in lil endian as 16-bit integers instead of single-byte integers.

    var fb = std.io.fixedBufferStream(args.buf);
    const argCount = args.arity / 2;

    var arguments: [30]u16 = undefined;
    var i: usize = 0;
    while (i < argCount) : (i += 1) {
        arguments[i] = try fb.reader().readInt(u16, std.builtin.Endian.Little);
    }

    // Slice the args, since we are only reading up to a limit.
    const actualArgs = arguments[0..argCount];

    self.vm_log("agi_test_said({any}) invoked...", .{actualArgs});
    return false;
}
