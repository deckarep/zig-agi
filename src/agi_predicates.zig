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

pub fn agi_unimplemented(_: *vm.VM, args: *aw.Args) anyerror!bool {
    std.log.warn("agi_unimplemented({any})...PREDICATE UNIMPLEMENTED", .{args.buf});
    return error.Error;
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

pub fn agi_test_greaterv(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    return try agi_test_greatern(self, args.pack());
}

pub fn agi_test_lessn(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo = args.get.a();
    const val = args.get.b();

    return self.read_var(varNo) < val;
}

pub fn agi_test_lessv(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    return try agi_test_lessn(self, args.pack());
}

pub fn agi_test_isset(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const flagNo = args.get.a();

    return self.get_flag(flagNo);
}

pub fn agi_test_controller(_: *vm.VM, _: *aw.Args) anyerror!bool {
    return false;
}

pub fn agi_test_have_key(_: *vm.VM, _: *aw.Args) anyerror!bool {
    // var hk = self.haveKey;
    // self.haveKey = false;
    // return hk;
    // TODO: HACK: to skip intro for now, put code back from above...this simulates a key was pressed as true.
    return true;
}

// agi_test_said needs to handle the args in a special way as they are u16 (little-endian) args
// Therefore, this is the *ONLY* function where it's handled in a hacky way
// Fuck you, I know this is a hack...it's called pragmatism and you should try it sometime
// Fuck you again, yes I'm missing punctuation on the end my sentences...
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

pub fn agi_posn(self: *vm.VM, args: *aw.Args) anyerror!bool {
    const objNo = args.get.a();
    const x1 = args.get.b();
    const y1 = args.get.c();
    const x2 = args.get.d();
    const y2 = args.get.e();

    const obj = &self.state.gameObjects[objNo];
    return x1 <= obj.x and obj.x <= x2 and y1 <= obj.y and obj.y <= y2;
}

pub fn agi_obj_in_room(_: *vm.VM, _: *aw.Args) anyerror!bool {
    return false;
}
