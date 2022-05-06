const std = @import("std");
const ArrayList = std.ArrayList;
const c = @import("c_defs.zig").c;

const go = @import("game_object.zig");
const hlp = @import("raylib_helpers.zig");
const cmds = @import("agi_cmds.zig");
const agi_vm = @import("vm.zig");

var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

// NOTES:
//  * if (initLog) {} means "initial logic" or constructor code for a logic room.
//  * when sound is played, a flag is also passed in to know completion, ie. 'musicDone'...unless sound is implemented full game logic won't work.

var vmInstance = agi_vm.VM.init();

// Adapted from: https://github.com/r1sc/agi.js/blob/master/Interpreter.ts
// TODO: all array indices should be usize.

pub fn main() anyerror!void {
    c.SetConfigFlags(c.FLAG_VSYNC_HINT);
    // Remember: these dimensions are the ExtractAGI upscaled size!!!
    c.InitWindow(1280, 672, "AGI Interpreter - @deckarep");
    c.InitAudioDevice();
    c.SetTargetFPS(60);
    defer c.CloseWindow();

    // Hide mouse cursor.
    c.HideCursor();
    defer c.ShowCursor();

    // Seed the VM with data it needs.
    try vmInstance.vm_bootstrap();

    // Background texture.
    const bg = c.LoadTexture("test-agi-game/extracted/pic/11_pic.png");
    defer c.UnloadTexture(bg);

    // Character.
    const larry = c.LoadTexture("test-agi-game/extracted/view/0_1_2.png");
    defer c.UnloadTexture(larry);

    //std.log.info("logic dir:", .{});
    //try readDir(logDirFile);
    vmInstance.vm_start();

    while (!c.WindowShouldClose()) {
        // Update section.
        try vmInstance.vm_cycle();

        // Draw section.
        drawwRaylib(&bg, &larry);
    }
}

fn drawwRaylib(bg: *const c.Texture, larry: *const c.Texture) void {
    // RENDER AT SPEED GOVERNED BY RAYLIB
    c.BeginDrawing();
    defer c.EndDrawing();

    c.ClearBackground(c.BLACK);

    c.DrawTexturePro(bg.*, hlp.rect(0, 0, 1280, 672), hlp.rect(0, 0, 1280, 672), hlp.vec2(0, 0), 0, c.WHITE);
    c.DrawTexturePro(larry.*, hlp.rect(0, 0, 56, 128), hlp.rect(570, 479, 56, 128), hlp.vec2(0, 0), 0, c.WHITE);

    // Cross-hair for cursor.
    c.DrawLineEx(hlp.vec2(@intToFloat(f32, c.GetMouseX()), 0), hlp.vec2(@intToFloat(f32, c.GetMouseX()), 672), 1.5, c.RED);
    c.DrawLineEx(hlp.vec2(0, @intToFloat(f32, c.GetMouseY())), hlp.vec2(1280, @intToFloat(f32, c.GetMouseY())), 1.5, c.RED);
}
