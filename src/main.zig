const std = @import("std");
const ArrayList = std.ArrayList;
const c = @import("c_defs.zig").c;

const go = @import("game_object.zig");
const hlp = @import("raylib_helpers.zig");
const cmds = @import("agi_cmds.zig");
const agi_vm = @import("vm.zig");

// HACK zone, just doing a quick and dirty comptime embed file.
const rootPath = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/";
const logDirFile = @embedFile(rootPath ++ "LOGDIR");
const picDirFile = @embedFile(rootPath ++ "PICDIR");
const viewDirFile = @embedFile(rootPath ++ "VIEWDIR");
const sndDirFile = @embedFile(rootPath ++ "SNDDIR");
const vol0 = @embedFile(rootPath ++ "VOL.0");
const vol1 = @embedFile(rootPath ++ "VOL.1");
const vol2 = @embedFile(rootPath ++ "VOL.2");

var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

const TOTAL_FLAGS: usize = 255;
const TOTAL_VARS: usize = 255;
const TOTAL_GAME_OBJS: usize = 16; // also called screen objs.

const messageDecryptKey = "Avis Durgan";

var programControl: bool = false;
var newroom: u8 = 0;
var horizon: u8 = 0;

var vars: [TOTAL_VARS]u8 = std.mem.zeroes([TOTAL_VARS]u8);
var flags: [TOTAL_FLAGS]bool = std.mem.zeroes([TOTAL_FLAGS]u8);
var gameObjects: [TOTAL_GAME_OBJS]go.GameObject = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject);

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

    // Background texture.
    const bg = c.LoadTexture("test-agi-game/extracted/pic/11_pic.png");
    defer c.UnloadTexture(bg);

    // Character.
    const larry = c.LoadTexture("test-agi-game/extracted/view/0_1_2.png");
    defer c.UnloadTexture(larry);

    while (!c.WindowShouldClose()) {
        updateRaylib();
        drawwRaylib(&bg, &larry);
    }

    std.log.info("logic dir:", .{});
    try readDir(logDirFile);
    // std.log.info("pic dir:", .{});
    // try readDir(picDirFile);
    // std.log.info("view dir:", .{});
    // try readDir(viewDirFile);
    //testAGI();
}

fn updateRaylib() void {
    // TODO: updates here.
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

fn readDir(dirFile: []const u8) !void {
    var fbs = std.io.fixedBufferStream(dirFile);
    var rdr = fbs.reader();

    const len: usize = dirFile.len / 3;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const aByte: u32 = try rdr.readByte();
        const bByte: u32 = try rdr.readByte();
        const cByte: u32 = try rdr.readByte();

        if (aByte != 255 and bByte != 255 and cByte != 255) {
            const vol = (aByte & 0b11110000) >> 4;
            var offset: u32 = (aByte & 0b00001111) << 16;
            offset = offset + (bByte << 8);
            offset = offset + cByte;

            //std.log.info("idx => {d}, volNo => {d}, volOffset => {d}", .{ i, vol, offset });
            try loadLogic(i, vol, offset);

            // NOTE: JUST DO ONE THING.
            return;
        }
    }
}

// https://wiki.scummvm.org/index.php?title=AGI/Specifications/Resources#LogicFormat
fn loadLogic(idx: usize, vol: usize, offset: u32) !void {
    var fbs = switch (vol) {
        0 => std.io.fixedBufferStream(vol0),
        1 => std.io.fixedBufferStream(vol1),
        2 => std.io.fixedBufferStream(vol2),
        else => unreachable,
    };

    try fbs.seekTo(offset);

    // PARSE HEADER.

    // Arbitrary endian-ness...FU Sierra.
    // Signature is always: 0x1234. (Big End..)
    const sig: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Big);
    const volNo: u8 = try fbs.reader().readByte();
    // Lil End..
    const resLength: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Little);

    std.log.info("idx => {d}, sig => {d}, vol/volNo => {d}/{d}, resLength => {d}", .{ idx, sig, vol, volNo, resLength });

    const newStartOffset = offset + 5;
    const newEndOffset = newStartOffset + resLength;

    // PARSE VOL PART.

    //std.log.info("[{d}..{d}] - max size: {d}", .{ newStartOffset, newEndOffset, fbs.getEndPos() });
    // This area of the volPart is purely the logic.
    var volPartFbs = switch (volNo) {
        0 => std.io.fixedBufferStream(vol0[newStartOffset..newEndOffset]),
        1 => std.io.fixedBufferStream(vol1[newStartOffset..newEndOffset]),
        2 => std.io.fixedBufferStream(vol2[newStartOffset..newEndOffset]),
        else => unreachable,
    };

    // PARSE MESSAGES FIRST

    // TODO: finish parsing messages and if it works it should XOR with the encryption key: "Avis Durgan" defined above.
    const messageOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
    //std.log.info("messageOffset => {d}", .{messageOffset});

    try volPartFbs.seekBy(messageOffset);
    const pos = try volPartFbs.getPos();
    //this.messageStartOffset = pos;
    const numMessages = try volPartFbs.reader().readByte();
    //std.log.info("no. messages => {d}", .{numMessages});
    _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);

    var decryptIndex: usize = 0;
    var i: usize = 0;
    while (i < numMessages) : (i += 1) {
        const msgPtr = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
        if (msgPtr == 0) {
            continue;
        }

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var msgStr = ArrayList(u8).init(allocator);
        defer msgStr.deinit();

        const mPos = try volPartFbs.getPos();
        try volPartFbs.seekTo(pos + msgPtr + 1);
        while (true) {
            const currentChar = try volPartFbs.reader().readByte();
            const decryptedChar = currentChar ^ messageDecryptKey[decryptIndex];
            try msgStr.append(decryptedChar);
            decryptIndex += 1;
            if (decryptIndex >= messageDecryptKey.len) {
                decryptIndex = 0;
            }
            if (decryptedChar == 0) {
                // Forget empty strings which would have a len of 1 but \0 inside them.
                if (msgStr.items.len > 1) {
                    std.log.info("msgStr => \"{s}\"", .{msgStr.items[0 .. msgStr.items.len - 1]});
                }
                break;
            }
        }
        try volPartFbs.seekTo(mPos);
    }

    // PARSE actual VOL PART (after messages extracted)
    // NOTE: I think I should rip out messages section now that it's been parsed, this way the slice is clean and sectioned off.
    try volPartFbs.seekTo(pos - messageOffset);

    // Interpreter local vars
    var orMode: bool = false;
    var invertMode: bool = false;
    var testMode: bool = false;
    var testResult: bool = true;
    //var debugLine: string = "";
    var orResult: bool = false;
    //var funcName: string;
    //var test: ITest;
    //var statement: IStatement;
    //var args: number[];
    var maxIters: u32 = 0;

    while (true) {

        // TODO: (DELETE ME) Safety to prevent runaway..
        if (maxIters > 200) {
            std.log.info("max iterations MET!!!", .{});
            break;
        }
        maxIters += 1;

        const opCodeNR = volPartFbs.reader().readByte() catch |e| {
            switch (e) {
                error.EndOfStream => break,
            }
        };
        //std.log.info("opCodeNR => {X:0>2}", .{opCodeNR});
        switch (opCodeNR) {
            0x00 => {
                std.log.info("{X:0>2} => return", .{opCodeNR});
                break;
            },
            0x91 => std.log.info("{X:0>2} => set.scan.start", .{opCodeNR}),
            0x92 => std.log.info("{X:0>2} => reset.scan.start", .{opCodeNR}),
            0xFE => {
                const n1: u32 = try volPartFbs.reader().readByte();
                const n2: u32 = try volPartFbs.reader().readByte();
                const gotoOffset = (((n2 << 8) | n1) << 16) >> 16;
                std.log.info("{X:0>2} => goto, offset: {d}", .{ opCodeNR, gotoOffset });
                // NOTE: doing a RELATIVE jump: seekBy NOT seekTo (absolute)
                try volPartFbs.seekBy(gotoOffset);
            },
            0xFF => {
                std.log.info("{X:0>2} => if", .{opCodeNR});
                if (testMode) {
                    testMode = false;
                    const elseOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
                    if (!testResult) {
                        // False conditional block. (jump over true block).
                        std.log.info("doing a false test jump over true!!!", .{});
                        // NOTE: doing a RELATIVE jump: seekBy NOT seekTo (absolute)
                        try volPartFbs.seekBy(elseOffset);
                    } else {
                        // True conditional block (do nothing).
                    }
                } else {
                    invertMode = false;
                    orMode = false;
                    testResult = true;
                    orResult = false;
                    testMode = true;
                }
            },
            else => {
                if (testMode) {
                    std.log.info("{X:0>2} ELSE", .{opCodeNR});
                    if (opCodeNR == 0xFC) {
                        orMode = !orMode;
                        if (orMode) {
                            orResult = false;
                        } else {
                            testResult = testResult and orResult;
                        }
                    } else if (opCodeNR == 0xFD) {
                        invertMode = !invertMode;
                    } else {
                        var testCallResult = false;

                        if ((opCodeNR - 1) >= cmds.agi_tests.len) {
                            std.log.info("FATAL: trying to fetch a test from index: {d}", .{opCodeNR - 1});
                            return;
                        }
                        const testFunc = cmds.agi_tests[opCodeNR - 1];

                        std.log.info("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, testFunc.name, testFunc.arity });
                        if (opCodeNR == 0x0E) { //Said (uses variable num of 16-bit args, within bytecode!)
                            const saidArgLen = try volPartFbs.reader().readByte();
                            var iSaidCount: usize = 0;
                            while (iSaidCount < saidArgLen) : (iSaidCount += 1) {
                                _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
                            }
                        } else {
                            if (std.mem.eql(u8, testFunc.name, "greatern")) {
                                const a = try volPartFbs.reader().readByte();
                                const b = try volPartFbs.reader().readByte();
                                testCallResult = vmInstance.agi_test_greatern(a, b);
                                std.log.info("test_greatern({d}, {d})", .{ a, b });
                            } else if (std.mem.eql(u8, testFunc.name, "isset")) {
                                const a = try volPartFbs.reader().readByte();
                                testCallResult = vmInstance.agi_test_isset(a);
                                std.log.info("isset({d})", .{a});
                            } else if (std.mem.eql(u8, testFunc.name, "equaln")) {
                                const a = try volPartFbs.reader().readByte();
                                const b = try volPartFbs.reader().readByte();
                                testCallResult = vmInstance.agi_test_equaln(a, b);
                                std.log.info("test_equaln({d}, {d})", .{ a, b });
                            } else {
                                std.log.info("test op:{d}(0x{X:0>2}) not handled!", .{ opCodeNR - 1, opCodeNR - 1 });
                                return;
                            }
                        }

                        // Here, actually invoke relevant TEST func with correct args.
                        // ie, var result = equaln(args);

                        if (invertMode) {
                            testCallResult = !testCallResult;
                            invertMode = false;
                        }

                        if (orMode) {
                            orResult = orResult or testCallResult;
                        } else {
                            testResult = testResult and testCallResult;
                        }
                    }
                } else {
                    const statementFunc = cmds.agi_statements[opCodeNR];

                    // TODO: don't do allocator in-line.
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();

                    const allocator = arena.allocator();
                    // TODO: iterate and collect args.
                    var argList = ArrayList(u8).init(allocator);
                    defer argList.deinit();

                    var arityCount: usize = 0;
                    while (arityCount < statementFunc.arity) : (arityCount += 1) {
                        // Need to collect all args and pass into relevant function!
                        const currentArg = try volPartFbs.reader().readByte();
                        const myStr = try std.fmt.allocPrint(allocator, "{d},", .{currentArg});
                        try argList.appendSlice(myStr);
                        std.log.info("component => {s}", .{myStr});
                    }

                    const joinedArgs = try std.mem.join(allocator, ",", &.{argList.items}); //&[_][]const u8{argList.items});

                    // TODO: execute agi_statement(args);
                    if (std.mem.eql(u8, statementFunc.name, "new_room")) {
                        const a = try volPartFbs.reader().readByte();
                        vmInstance.agi_new_room(a);
                    } else if (std.mem.eql(u8, statementFunc.name, "quit")) {
                        const a = try volPartFbs.reader().readByte();
                        vmInstance.agi_quit(a);
                    } else if (std.mem.eql(u8, statementFunc.name, "script_size")) {
                        const a = try volPartFbs.reader().readByte();
                        vmInstance.agi_script_size(a);
                    } else {
                        std.log.info("NOT IMPLEMENTED: agi statement: opCode:{d}, {s}({s}) (arg_count => {d})...", .{ opCodeNR, statementFunc.name, joinedArgs, statementFunc.arity });
                        //vmInstance.vm_op_not_implemented(35);
                    }

                    // Finally, special handling for new.room opcode.
                    if (opCodeNR == 0x12) {
                        try volPartFbs.seekTo(0);
                        break;
                    }
                }
            },
        }
    }
}

fn testAGI() void {
    agi_assignn(0, 3);
    agi_assignn(1, 4);
    agi_assignn(2, 6);
    agi_assignn(3, 12);
    agi_assignn(4, 8);
    std.log.info("", .{});

    dump();

    std.log.info("", .{});
    //var[x] @= NUM
    agi_lindirectn(2, 3);

    //var[x] @= var[y]
    agi_lindirectv(1, 4);

    // var[x] =@ var[y]
    agi_rindirect(3, 3);

    gameObjects[3].x = 15;
    gameObjects[3].y = 17;

    agi_get_posn(3, 200, 201);

    std.log.info("go[3] => {s}", .{gameObjects[3]});
    agi_unanimate_all();
    std.log.info("go[3] => {s}", .{gameObjects[3]});

    dump();
}

fn updateObject(obj: *go.GameObject, objNo: usize) void {
    std.log.info("updateObject(obj:{s}, objNo:{d}", .{ obj, objNo });
}

fn dump() void {
    var i: usize = 0;
    while (i < vars.len) : (i += 1) {
        if (vars[i] != 0) {
            std.log.info("v[{d}] => {d}", .{ i, vars[i] });
        }
    }
}

fn agi_player_control() void {
    programControl = false;
}

fn agi_program_control() void {
    programControl = true;
}

fn agi_set_horizon(y: u8) void {
    horizon = y;
}

fn agi_get_posn(objNo: usize, varNo1: usize, varNo2: usize) void {
    vars[varNo1] = gameObjects[objNo].x;
    vars[varNo2] = gameObjects[objNo].y;
}

fn agi_stop_update(objNo: usize) void {
    gameObjects[objNo].update = false;
}

fn agi_draw(objNo: usize) void {
    gameObjects[objNo].draw = true;
}

fn agi_random(min: u8, max: u8) u8 {
    return rand.intRangeAtMost(u8, min, max);
}

fn agi_unanimate_all() void {
    // TODO: this might not be good enough, might also need to clear the array and therefore use a Vector type.
    // zeroes out all game objects, (perhaps the lazy way).
    gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject);
}

fn agi_lindirectn(varNo: usize, val: u8) void {
    vars[vars[varNo]] = val;
}

fn agi_lindirectv(varNo1: usize, varNo2: usize) void {
    agi_lindirectn(varNo1, vars[varNo2]);
}

fn agi_rindirect(varNo1: usize, varNo2: usize) void {
    vars[varNo1] = vars[vars[varNo2]];
}

// Flag commands
fn agi_set(flagNo: usize) void {
    flags[flagNo] = true;
}

fn agi_reset(flagNo: usize) void {
    flags[flagNo] = false;
}

fn agi_toggle(flagNo: usize) void {
    flags[flagNo] = !flags[flagNo];
}

fn agi_setv(varNo: usize) void {
    agi_set(vars[varNo]);
}

fn agi_reset_v(varNo: usize) void {
    agi_reset(vars[varNo]);
}

fn agi_togglev(varNo: usize) void {
    agi_toggle(vars[varNo]);
}

// fn agi_call(logicNo: number) void {
//             this.logicStack.push(this.logicNo);
//             this.logicNo = logicNo;
//             if (this.loadedLogics[logicNo] != null) {
//                 this.loadedLogics[logicNo].parseLogic();
//             } else {
//                 this.agi_load_logic(logicNo);
//                 this.loadedLogics[logicNo].parseLogic();
//                 this.loadedLogics[logicNo] = null;
//             }
//             this.logicNo = this.logicStack.pop();
//         }

// fn agi_call_v(varNo: number) void {
//     this.agi_call(this.variables[varNo]);
// }

fn agi_assignn(varNo: u8, num: u8) void {
    vars[varNo] = num;
}

fn agi_assignv(varNo1: usize, varNo2: usize) void {
    agi_assignn(varNo1, vars[varNo2]);
}

fn agi_increment(varNo: usize) void {
    if (vars[varNo] < 255) {
        vars[varNo] += 1;
    }
}

fn agi_decrement(varNo: usize) void {
    if (vars[varNo] > 0) {
        vars[varNo] -= 1;
    }
}

fn agi_addn(varNo: usize, num: u8) void {
    vars[varNo] += num;
}

fn agi_addv(varNo1: usize, varNo2: usize) void {
    agi_addn(varNo1, vars[varNo2]);
}

fn agi_subn(varNo: usize, num: u8) void {
    vars[varNo] -= num;
}

fn agi_subv(varNo1: usize, varNo2: usize) void {
    agi_subn(varNo1, vars[varNo2]);
}

fn agi_muln(varNo: usize, val: u8) void {
    vars[vars[varNo]] *= val;
}

fn agi_mulv(varNo1: usize, varNo2: usize) void {
    agi_muln(varNo1, vars[varNo2]);
}

fn agi_divn(varNo: usize, val: u8) void {
    vars[vars[varNo]] /= val;
}

fn agi_divv(varNo1: usize, varNo2: usize) void {
    agi_divn(varNo1, vars[varNo2]);
}

fn agi_new_room(roomNo: u8) void {
    std.log.info("NEW_ROOM {d}", .{roomNo});
    newroom = roomNo;
}

fn agi_new_room_v(varNo: usize) void {
    agi_new_room(vars[varNo]);
}

// Tests
fn agi_test_equaln(varNo: usize, val: u8) bool {
    return vars[varNo] == val;
}

fn agi_test_equalv(varNo1: usize, varNo2: usize) bool {
    return agi_test_equaln(varNo1, vars[varNo2]);
}

fn agi_test_lessn(varNo: usize, val: u8) bool {
    return vars[varNo] < val;
}

fn agi_test_lessv(varNo1: usize, varNo2: usize) bool {
    return agi_test_lessn(varNo1, vars[varNo2]);
}

fn agi_test_greatern(varNo: usize, val: u8) bool {
    return vars[varNo] > val;
}

fn agi_test_greaterv(varNo1: usize, varNo2: usize) bool {
    return agi_test_greatern(varNo1, vars[varNo2]);
}

fn agi_test_isset(flagNo: usize) bool {
    return flags[flagNo];
}

fn agi_test_issetv(varNo: usize) bool {
    return agi_test_isset(vars[varNo]);
}

fn agi_test_has(_: u8) bool {
    //fn agi_test_has(itemNo: u8) bool {
    // Like agi.js
    return false;
}

fn agi_test_obj_in_room(_: u8, _: u8) bool {
    //fn agi_test_obj_in_room(itemNo: u8, varNo: u8) bool {
    // Like agi.js
    return false;
}

fn agi_test_posn(_: u8, _: u8, _: u8, _: u8, _: u8) bool {
    //fn agi_test_posn(objNo: u8, x1: u8, y1: u8, x2: u8, y2: u8) bool {
    //var obj = gameObjects[objNo];
    //return x1 <= obj.x && obj.x <= x2 && y1 <= obj.y && obj.y <= y2;
    return false;
}

fn agi_test_controller(_: u8) bool {
    //fn agi_test_controller(ctrNo: u8) bool {
    // Like agi.js
    return false;
}

fn agi_test_have_key() bool {
    //var haveKey: boolean =
    //haveKey = false;
    //return haveKey;
    return false;
}

// fn agi_test_said(wordGroups: u8[]) {
//     //return false;
// }

fn agi_test_compare_strings(_: u8, _: u8) bool {
    //fn agi_test_compare_strings(strNo1: u8, strNo2: u8) bool {
    //return strings[strNo1] == strings[strNo2];
    return false;
}

fn agi_test_obj_in_box() bool {
    //return false;
    return false;
}

//fn agi_distance(objNo1: u8, objNo2: u8, varNo: u8) void {
fn agi_distance(_: u8, _: u8, _: u8) void {
    // var obj1: GameObject = gameObjects[objNo1];
    // var obj2: GameObject = gameObjects[objNo2];
    // if (obj1 != null && obj2 != null && obj1.draw && obj2.draw) {
    //     vars[varNo] = Math.abs(obj1.x - obj2.x) + Math.abs(obj1.y - obj2.y);
    // } else {
    //     vars[varNo] = 255;
    // }
}

fn agi_object_on_water() void {
    // Like agi.js
}
