const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const testing = std.testing;

// Args wrangling helps with consuming and passing around args.
// Keep in mind if you reuse the struct you need to ensure your set args are either the same size or less (count-wise).
pub const Args = struct {
    buf: []u8,

    arity: usize,
    get: getter,
    set: setter,

    pub fn init(buf: []u8) Args {
        var a = Args{
            .buf = buf,
            .get = getter{ .buf = buf },
            .set = setter{ .buf = buf, .newArity = 0 },
            .arity = 0,
        };
        return a;
    }

    fn consume(self: *Args, rdr: *std.io.FixedBufferStream([]const u8), count: usize) !void {
        // Make sure our buffer is large enough before eating and re-slicing.
        assert(self.buf.len >= count);

        // Record the arity as we might need it for later.
        self.arity = count;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.buf[i] = try rdr.reader().readByte();
        }

        // Upon eating all values, re-slice the buffer to arity size.
        self.buf = self.buf[0..count];
    }

    pub fn eat(self: *Args, rdr: *std.io.FixedBufferStream([]const u8), count: usize) !*Args {
        // Only consume if we have args to deal with, otherwise just return.
        if (count > 0) {
            try self.consume(rdr, count);
        }
        return self;
    }

    pub fn pack(self: *Args) *Args {
        // Only take the newArity if at least one setter was called.
        if (self.set.newArity > 0) {
            // Make all slices match for posterity.
            self.buf = self.buf[0..self.set.newArity];
            self.set.buf = self.buf;
            self.get.buf = self.buf;
        }
        return self;
    }
};

const getter = struct {
    buf: []u8,
    pub fn a(self: *getter) u8 {
        return self.buf[0];
    }

    pub fn b(self: *getter) u8 {
        return self.buf[1];
    }

    pub fn c(self: *getter) u8 {
        return self.buf[2];
    }

    pub fn d(self: *getter) u8 {
        return self.buf[3];
    }

    pub fn e(self: *getter) u8 {
        return self.buf[4];
    }

    pub fn f(self: *getter) u8 {
        return self.buf[5];
    }

    pub fn g(self: *getter) u8 {
        return self.buf[6];
    }

    pub fn h(self: *getter) u8 {
        return self.buf[7];
    }
};

const setter = struct {
    // We track a newArity because we may populate a smaller amount of args when reusing this object.
    newArity: usize,
    buf: []u8,

    pub fn a(self: *setter, val: u8) void {
        self.buf[0] = val;
        self.newArity += 1;
    }

    pub fn b(self: *setter, val: u8) void {
        self.buf[1] = val;
        self.newArity += 1;
    }

    pub fn c(self: *setter, val: u8) void {
        self.buf[2] = val;
        self.newArity += 1;
    }

    pub fn d(self: *setter, val: u8) void {
        self.buf[3] = val;
        self.newArity += 1;
    }

    pub fn e(self: *setter, val: u8) void {
        self.buf[4] = val;
        self.newArity += 1;
    }

    pub fn f(self: *setter, val: u8) void {
        self.buf[5] = val;
        self.newArity += 1;
    }

    pub fn g(self: *setter, val: u8) void {
        self.buf[6] = val;
        self.newArity += 1;
    }

    pub fn h(self: *setter, val: u8) void {
        self.buf[7] = val;
        self.newArity += 1;
    }
};

test "args system" {
    // 1. create fixed buffer with test data.
    const bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };
    var fbs = std.io.fixedBufferStream(&bytes);

    // 2. instantiate args system with a temp buffer.
    var buf: [10]u8 = undefined;
    var myArgs = Args.init(&buf);

    try myArgs.eat(&fbs, 3);

    // 3. try to "get" our args off
    const a = myArgs.get.a();
    const b = myArgs.get.b();
    const c = myArgs.get.c();

    try testing.expect(a == 1);
    try testing.expect(b == 2);
    try testing.expect(c == 3);

    // 4. finally, manifest new args and re-pack as a slice either the same size or smaller (we can't go bigger, ie have more args)
    myArgs.set.a(11);
    myArgs.set.b(12);
    myArgs.set.c(15);

    const result = myArgs.pack();

    try testing.expect(result[0] == 11);
    try testing.expect(result[1] == 12);
    try testing.expect(result[2] == 15);
}
