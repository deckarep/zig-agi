const std = @import("std");

pub fn number() !i64 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [10]u8 = undefined;

    try stdout.print("A number please: ", .{});

    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
        return std.fmt.parseInt(i64, user_input, 10);
    } else {
        return @as(i64, 0);
    }
}

pub fn char(msg: []const u8) !u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [10]u8 = undefined;

    try stdout.print("{s}:\n>", .{msg});

    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
        std.log.info("You said: \"{s}\" or \"{d}\"", .{ user_input, user_input[0] });
        return user_input[0];
    } else {
        return @as(u8, 0);
    }
}
