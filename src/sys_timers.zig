// https://github.com/sonneveld/nagi/blob/dd0665b618ef5eb9cea3498eb6efe0c5df3d7deb/src/sys/time.c
const std = @import("std");
const clib = @import("c_defs.zig").c;

pub const TimerState = enum(u8) {
    Stopped,
    Started,
    Paused,
    Shutdown,
};

const TICK_SCALE = 50;

// TODO: Timing is much closer to ticking per second.
// Note: Monotonic and Relaxed are the same thing in the context of atomic ops.

pub const VM_Timer = struct {
    threadHandle: std.Thread,

    state: std.atomic.Atomic(TimerState),

    aSeconds: std.atomic.Atomic(u8),
    aMinutes: std.atomic.Atomic(u8),
    aHours: std.atomic.Atomic(u8),
    aDays: std.atomic.Atomic(u8),

    // private state to the spin loop.
    ticks: u32,

    pub fn init() !VM_Timer {
        var t = VM_Timer{
            .state = std.atomic.Atomic(TimerState).init(TimerState.Stopped),
            .ticks = 0,

            .aSeconds = std.atomic.Atomic(u8).init(0),
            .aMinutes = std.atomic.Atomic(u8).init(0),
            .aHours = std.atomic.Atomic(u8).init(0),
            .aDays = std.atomic.Atomic(u8).init(0),

            .threadHandle = undefined,
        };
        return t;
    }

    pub fn start(self: *VM_Timer) !void {
        // NOTE: need to pass in a self since `spin` is a bound fn.
        self.threadHandle = try std.Thread.spawn(.{}, VM_Timer.spin, .{self});
        self.state.store(TimerState.Started, std.atomic.Ordering.Monotonic);
    }

    fn spin(self: *VM_Timer) void {
        var tick: u32 = 0;
        var tick_prev: u32 = 0;
        var time_counter: u32 = 0;

        tick_prev = @floatToInt(u32, clib.GetTime() * 1000);

        while (self.state.load(std.atomic.Ordering.Monotonic) != TimerState.Shutdown) {
            tick = @floatToInt(u32, clib.GetTime() * 1000);
            self.ticks += (tick - tick_prev) / TICK_SCALE;

            // it's in 1/20's of seconds
            time_counter += (tick - tick_prev);

            while (time_counter >= 20 * TICK_SCALE) {
                time_counter -= 20 * TICK_SCALE;

                var secondsVal = self.aSeconds.fetchAdd(1, std.atomic.Ordering.Monotonic);

                if (secondsVal >= 60) {
                    self.aSeconds.store(0, std.atomic.Ordering.Monotonic);
                    _ = self.aMinutes.fetchAdd(1, std.atomic.Ordering.Monotonic);
                }

                if (self.aMinutes.load(std.atomic.Ordering.Monotonic) >= 60) {
                    self.aMinutes.store(0, std.atomic.Ordering.Monotonic);
                    _ = self.aHours.fetchAdd(1, std.atomic.Ordering.Monotonic);
                }

                if (self.aHours.load(std.atomic.Ordering.Monotonic) >= 24) {
                    self.aHours.store(0, std.atomic.Ordering.Monotonic);
                    _ = self.aDays.fetchAdd(1, std.atomic.Ordering.Monotonic);
                }
            }

            tick_prev = tick;

            //std.log.info("hello!!! from thread -> {d}:secs, {d}:mins, {d}:hrs, {d}:days", .{ self.aSeconds.load(std.atomic.Ordering.Monotonic), self.aMinutes.load(std.atomic.Ordering.Monotonic), self.aHours.load(std.atomic.Ordering.Monotonic), self.aDays.load(std.atomic.Ordering.Monotonic) });
            std.time.sleep(500 * std.time.ns_per_ms);
        }
    }

    pub fn secs(self: *VM_Timer) u8 {
        return self.aSeconds.load(std.atomic.Ordering.Monotonic);
    }

    pub fn mins(self: *VM_Timer) u8 {
        return self.aMinutes.load(std.atomic.Ordering.Monotonic);
    }

    pub fn hrs(self: *VM_Timer) u8 {
        return self.aHours.load(std.atomic.Ordering.Monotonic);
    }

    pub fn days(self: *VM_Timer) u8 {
        return self.aDays.load(std.atomic.Ordering.Monotonic);
    }

    pub fn deinit(self: *VM_Timer) void {
        std.log.info("vm_timer shutdown requested...", .{});
        self.state.store(TimerState.Shutdown, std.atomic.Ordering.Monotonic);
        self.threadHandle.join();
        self.state.store(TimerState.Stopped, std.atomic.Ordering.Monotonic);
        std.log.info("vm_timer shutdown successfully...", .{});
    }
};
