const c = @import("c_defs.zig").c;
const std = @import("std");

var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

// col is a helper to create a Raylib Color.
pub fn col(r: u8, g: u8, b: u8, a: u8) c.Color {
    return c.Color{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}

// rect is a helper to create a Raylib Rectangle.
pub fn rect(x: f32, y: f32, w: f32, h: f32) c.Rectangle {
    return c.Rectangle{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

// vec2 is a helper to create a Raylib Vector2.
pub fn vec2(x: f32, y: f32) c.Vector2 {
    return c.Vector2{
        .x = x,
        .y = y,
    };
}

pub fn cpVecToVec2(v: c.cpVect) c.Vector2 {
    return vec2(v.x, v.y);
}

pub fn vec2TocpVec(v: c.Vector2) c.cpVect {
    return c.cpv(v.x, v.y);
}

// Returns a random -1 or 1 as an f32, that's it.
pub fn someOne() f32 {
    return @intToFloat(f32, rand.intRangeAtMost(i8, 0, 1) * 2 - 1);
}
