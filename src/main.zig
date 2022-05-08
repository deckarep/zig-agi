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

// Logic:
//  * if (initLog) {} means "initial logic" or constructor code for a logic room.
//  * when sound is played, a flag is also passed in to know completion, ie. 'musicDone'...unless sound is implemented full game logic won't work.

// Views:
//  * Extracted format is: 40_0_1.png aka: {viewNo}_{loop}_{cell}.png.

// Raylib drawing:
//  * Using the Image api is slow and not recommended with raylib when it comes to frame/by/frame or speed.
//  * Instead, one strategy is to just use my own raw memory in Zig for each painting buffer I need.
//  * Then, for all blit routines loop over the raw memory as needed and just do a DrawPixel call to either the screen or a render texture, therefore avoiding the Image api entirely.

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
    //c.HideCursor();
    //defer c.ShowCursor();

    // Seed the VM with data it needs.
    try vmInstance.vm_bootstrap();

    // Background texture.
    const bg = c.LoadTexture("test-agi-game/extracted/pic/11_pic.png");
    defer c.UnloadTexture(bg);

    // Character.
    const larry = c.LoadTexture("test-agi-game/extracted/view/0_1_2.png");
    defer c.UnloadTexture(larry);

    vmInstance.vm_start();

    // var target = c.LoadRenderTexture(1280, 672);
    // c.BeginTextureMode(target);
    // c.ClearBackground(hlp.col(255, 255, 255, 0));
    // c.EndTextureMode();

    while (!c.WindowShouldClose()) {
        // Update section.
        try vmInstance.vm_cycle();

        // Draw section.
        //drawwRaylib(&bg, &larry);
        // RENDER AT SPEED GOVERNED BY RAYLIB
        // c.BeginTextureMode(target);
        // // Do drawing stuff here
        // const value = c.GetRandomValue(0, 5);
        // if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
        //     //c.DrawPixel(value, value, c.RED);
        //     c.DrawPixel(c.GetMouseX(), c.GetMouseY(), c.Fade(c.RED, 0.2));
        //     c.DrawPixel(c.GetMouseX() + value, c.GetMouseY() + value, c.Fade(c.GREEN, 0.2));
        //     c.DrawPixel(c.GetMouseX() - value, c.GetMouseY() + value, c.Fade(c.BLUE, 0.2));
        //     c.DrawPixel(c.GetMouseX() + value, c.GetMouseY() - value, c.Fade(c.RED, 0.2));
        //     c.DrawPixel(c.GetMouseX() - value, c.GetMouseY() - value, c.Fade(c.YELLOW, 0.2));
        // }

        // c.EndTextureMode();

        c.BeginDrawing();
        c.ClearBackground(c.BLACK);

        var i: usize = 0;
        var xOffset: c_int = 10;
        var yOffset: c_int = 10;
        for (vmInstance.flags) |flg| {
            c.DrawText(if (flg) "T" else "F", @intCast(c_int, ((i % 50) * 10)) + xOffset, @intCast(c_int, ((i % 10) * 10)) + yOffset, 10, c.RED);
            i += 1;

            //std.log.info("boom: {t}", .{flg});
        }
        // // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
        // var i: usize = 0;
        // //var rFactor: c_int = if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) 30 else 1;
        // //const valueA = @intToFloat(f32, c.GetRandomValue(1, rFactor));
        // //c.BeginBlendMode(c.BLEND_ADDITIVE);
        // while (i < 5) : (i += 1) {
        //     // const valueB = @intToFloat(f32, c.GetRandomValue(1, rFactor));
        //     // const valueC = @intToFloat(f32, c.GetRandomValue(1, rFactor));
        //     // const valueD = @intToFloat(f32, c.GetRandomValue(1, rFactor));
        //     c.DrawTexturePro(target.texture, hlp.rect(0, 0, 1280, -672), hlp.rect(0, 0, 1280, 672), hlp.vec2(0, 0), 0, c.WHITE);
        // }
        //c.EndBlendMode();
        c.EndDrawing();
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
