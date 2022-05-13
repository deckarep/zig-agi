const std = @import("std");
const ArrayList = std.ArrayList;
const c = @import("c_defs.zig").c;

const go = @import("game_object.zig");
const hlp = @import("raylib_helpers.zig");
const cmds = @import("agi_cmds.zig");
const agi_vm = @import("vm.zig");
const rm = @import("resource_manager.zig");

var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const pathAudio = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/ripped_music/";
const kIntro = rm.WithKey(rm.ResourceTag.MusicStream, pathAudio ++ "Larry - Intro.mp3");
const playAudio = false;

const pathTextures = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/extracted/view/";
const sampleTexture = pathTextures ++ "43_0_0.png";

// NOTES:

// VM Runtime
//  * Interpret runs at 1/20th of a second * var[10] (time delay)...

// Logic:
//  * This -> [ indicates a line comment in original source.
//  * if (initLog) {} means "initial logic" or constructor code for a logic room.
//  * some rooms, like room 0, have their initLog defined in a separate file: RM50.cg
//  * Variables can now be live monitored with the: monitorVarSet call below passing in a var mapping table with names.
//      * The index of the variable is pulled from the source GAMEDEFS.h file '%var' declarations.
//  * when sound is played, a flag is also passed in to know completion, ie. 'musicDone'...unless sound is implemented full game logic won't work.
//  * When seeing something like below:(this is a label!!!!)
//      [*****
//      :exit  (this is a label, and we can jump relative forward or backwards yall)
//      [*****
//  * I need a mechanism to update the internal game clock which is held by VARS 11(seconds),12(min),13(hrs),14(days)
//    * Idea: just use a dedicated thread bumping atomic vars. Then, when reading a var if it's (11,12,13,14) just read the atomic vars directly.

// Views:
//  * Extracted format is: 40_0_1.png aka: {viewNo}_{loop}_{cell}.png.
//  * Original screen dimensions: 320x200

// Raylib drawing:
//  * Using the Image api is slow and not recommended with raylib when it comes to frame/by/frame or speed.
//  * Instead, one strategy is to just use my own raw memory in Zig for each painting buffer I need.
//  * Then, for all blit routines loop over the raw memory as needed and just do a DrawPixel call to either the screen or a render texture, therefore avoiding the Image api entirely.
//  TODO: noticed the vm_cycle is in the while loop but outside of the Begin/EndDrawing routines. But the VM itself does issue draw commands...so probably should move it.

// Music:
//  * NOTE: The music stream needs to be updated at a low enough latency therefore I might need to set that up in it's own dedicated thread.
//  * NOTE: One user commented to try and increase the buffer size!!!

var vmInstance = agi_vm.VM.init(false);

// Adapted from: https://github.com/r1sc/agi.js/blob/master/Interpreter.ts
// TODO: all array indices should be usize.

pub fn main() anyerror!void {
    defer arena.deinit();

    c.SetConfigFlags(c.FLAG_VSYNC_HINT);
    // Remember: these dimensions are the ExtractAGI upscaled size!!!
    c.InitWindow(1280 + 300, 672, "AGI Interpreter - @deckarep");
    c.InitAudioDevice();
    c.SetTargetFPS(60);
    defer c.CloseWindow();

    var resMan = rm.ResourceManager.init(allocator);
    defer resMan.deinit();

    // Load music streams...
    _ = try resMan.add_musicstream(kIntro);
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

    try vmInstance.vm_start();
    defer vmInstance.deinit();

    // var target = c.LoadRenderTexture(1280, 672);
    // c.BeginTextureMode(target);
    // c.ClearBackground(hlp.col(255, 255, 255, 0));
    // c.EndTextureMode();

    while (!c.WindowShouldClose()) {
        // Update section.

        if (playAudio) {
            if (!resMan.isMusicStreamPlaying(kIntro)) {
                //resMan.stopMusicStream(kIntro);
                resMan.playMusicStream(kIntro);
            }
            resMan.updateMusicStream(kIntro);
        }

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

        std.log.info("before vm_cycle", .{});
        try vmInstance.vm_cycle();
        std.log.info("after vm_cycle", .{});

        //std.log.info("frame: {d}", .{c.GetFrameTime()});

        //const flags = [_]bool{ true, false, true, false, true, false, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, true, true, false, false, true, false };
        debugDrawVars(&vmInstance.vars);
        debugDrawFlags(&vmInstance.flags);

        const varSet = [_]monVar{
            .{ .name = "egoDir", .idx = 6 },
            .{ .name = "elapsedSeconds", .idx = 11 },
            .{ .name = "elapsedMin", .idx = 12 },
            .{ .name = "elapsedHrs", .idx = 13 },
            .{ .name = "elapsedDays", .idx = 14 },
            .{ .name = "egoX", .idx = 38 },
            .{ .name = "oldEgoX", .idx = 40 },
            .{ .name = "egoY", .idx = 39 },
            .{ .name = "oldEgoY", .idx = 41 },
            .{ .name = "oldEgoDir", .idx = 42 },
            .{ .name = "passInRoom", .idx = 62 },
            .{ .name = "script", .idx = 65 },
            .{ .name = "scriptCycles", .idx = 66 },
            .{ .name = "scriptTimer", .idx = 67 },
            .{ .name = "gameSeconds", .idx = 115 },
        };
        try moniterVarSet(varSet[0..]);

        const flagSet = [_]monFlag{
            .{ .name = "scriptDone", .idx = 75 },
        };
        try moniterFlagSet(flagSet[0..]);
        c.EndDrawing();

        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

const monVar = struct {
    name: []const u8,
    idx: usize,
};

fn moniterVarSet(vars: []const monVar) !void {
    const xOffset = 1200;
    const yOffset = 10;
    const size = 15;

    var i: usize = 0;
    for (vars) |v| {
        // Need to pass a null-terminated proper c-string.
        //const cstr = try allocator.dupeZ(u8, v.name);
        //defer allocator.free(cstr);

        // NOTE: need to pass pointer child-type hence the .ptr or else get C ABI Zig bug.  :shrug:
        const symbol = c.TextFormat("%s: %03i => %03i", v.name.ptr, v.idx, vmInstance.read_var(v.idx));
        c.DrawText(symbol, xOffset, yOffset + (@intCast(c_int, i) * 16), size, c.GREEN);
        i += 1;
    }
}

const monFlag = struct {
    name: []const u8,
    idx: usize,
};

fn moniterFlagSet(flags: []const monFlag) !void {
    const xOffset = 1200;
    const yOffset = 300;
    const size = 15;

    var i: usize = 0;
    for (flags) |f| {
        // Need to pass a null-terminated proper c-string.
        //const cstr = try allocator.dupeZ(u8, v.name);
        //defer allocator.free(cstr);

        // NOTE: need to pass pointer child-type hence the .ptr or else get C ABI Zig bug.  :shrug:
        const symbol = c.TextFormat("%s: %03i => %s", f.name.ptr, f.idx, if (vmInstance.flags[f.idx]) "T" else "F");
        c.DrawText(symbol, xOffset, yOffset + (@intCast(c_int, i) * 18), size, c.WHITE);
        i += 1;
    }
}

// for now this works like a HEAT-MAP of the var values in each var register....at some point I need to actually render each cell u8 value.
// alternatively: when hovering with the mouse, show a tooltip like: var[x] = 12;
fn debugDrawVars(vars: []u8) void {
    const xOrigin = 1360 + 4;
    const yOrigin = 100;
    const padding = 4;
    const width = 8;

    const cols = 20;
    const rows = 13;

    const falseColor = c.GRAY;
    const noDataColor = hlp.col(128, 128, 128, 80);

    //std.log.info("*******", .{});
    var col: usize = 0;
    while (col < cols) : (col += 1) {
        var row: usize = 0;
        while (row < rows) : (row += 1) {
            const x = (@intCast(c_int, col) * 10) + padding + xOrigin;
            const y = (@intCast(c_int, row) * 10) + padding + yOrigin;

            const idx = (cols * row) + col;
            //std.log.info("rect: {d}", .{idx});
            if (idx >= vars.len) {
                c.DrawRectangle(x, y, width, width, noDataColor);
                continue;
            }
            const varValue = vars[idx];
            const color = if (varValue > 0) hlp.col(varValue, varValue, varValue, 255) else falseColor;
            c.DrawRectangle(x, y, width, width, color);
        }
    }
}

fn debugDrawFlags(flags: []bool) void {
    const xOrigin = 1360 + 4;
    const yOrigin = 500;
    const padding = 4;
    const width = 8;

    const cols = 20;
    const rows = 13;

    const trueColor = c.GREEN;
    const falseColor = c.GRAY;
    const noDataColor = hlp.col(128, 128, 128, 80);

    //std.log.info("*******", .{});
    var col: usize = 0;
    while (col < cols) : (col += 1) {
        var row: usize = 0;
        while (row < rows) : (row += 1) {
            const x = (@intCast(c_int, col) * 10) + padding + xOrigin;
            const y = (@intCast(c_int, row) * 10) + padding + yOrigin;

            const idx = (cols * row) + col;
            //std.log.info("rect: {d}", .{idx});
            if (idx >= flags.len) {
                c.DrawRectangle(x, y, width, width, noDataColor);
                continue;
            }
            const condition = flags[idx];
            const color = if (condition) trueColor else falseColor;
            c.DrawRectangle(x, y, width, width, color);
        }
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
