const std = @import("std");
const prompt = @import("prompt.zig");
const go = @import("game_object.zig");
const cmds = @import("agi_cmds.zig");
const stmts = @import("agi_statements.zig");
const hlp = @import("raylib_helpers.zig");
const clib = @import("c_defs.zig").c;
const timer = @import("sys_timers.zig");
const rm = @import("resource_manager.zig");
const aw = @import("args.zig");
const assert = std.debug.assert;

const ArrayList = std.ArrayList;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const allocator = arena.allocator();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const tempAllocator = gpa.allocator();

const GLSL_VERSION: i32 = if (@hasDecl(clib, "PLATFORM_RPI")) 100 else 330;
const GLSL_VERSION_STRING = std.fmt.comptimePrint("{d}", .{GLSL_VERSION});

const pathTextures = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/extracted/view/";
const pathPics = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/extracted/pic/";
pub const sampleTexture = pathTextures ++ "43_0_0.png";
const pathShaders = "resources/shaders/glsl" ++ GLSL_VERSION_STRING ++ "/";

const messageDecryptKey = "Avis Durgan";

const TOTAL_VARS: usize = 256;
const TOTAL_FLAGS: usize = 256;
const TOTAL_CONTROLLERS: usize = 256;

// also called screen objs.
pub const TOTAL_GAME_OBJS: usize = 16;

const LOGIC_STACK_SIZE: usize = 255; // Arbitrary size has been chosen of 255, I don't expect to exceed it with tech from 1980s.
const DIR_INDEX_SIZE: usize = 300;

const vm_width = 1280;
const vm_height = 672;

var agiFileList: [7][]const u8 = undefined;

pub const AGIFile = enum(usize) {
    LOGDIR = 0,
    PICDIR = 1,
    SNDDIR = 2,
    VIEWDIR = 3,
    VOL_0 = 4,
    VOL_1 = 5,
    VOL_2 = 6,
};

const DirectoryIndex = struct {
    vol: u32,
    offset: u32,
};

// Needed because Zig can't resolve error unions with recursive function calls.
//const VMError = error{ EndOfStream, OutOfMemory, NoSpaceLeft };

fn buildDirIndex(dirFile: []const u8) ![DIR_INDEX_SIZE]DirectoryIndex {
    var index: [DIR_INDEX_SIZE]DirectoryIndex = std.mem.zeroes([DIR_INDEX_SIZE]DirectoryIndex);

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

            index[i] = DirectoryIndex{
                .vol = vol,
                .offset = offset,
            };
        }
    }
    // Return a copy of the loaded index array.
    return index;
}

fn loadFiles() anyerror!void {
    const files_of_interest = [_][]const u8{
        "LOGDIR",
        "PICDIR",
        "SNDDIR",
        "VIEWDIR",

        // NOTE: Technically we should just stat the file-system to find all vols or iterate the directory I suppose.
        "VOL.0",
        "VOL.1",
        "VOL.2",
    };

    var i: usize = 0;
    for (files_of_interest) |name| {
        var buf: [50]u8 = undefined;
        const result = try std.fmt.bufPrint(&buf, "test-agi-game/{s}", .{name});
        agiFileList[i] = try std.fs.cwd().readFileAlloc(allocator, result, 1024 * 1024);
        i += 1;
    }
}

pub const VM = struct {
    debug: bool,
    resMan: rm.ResourceManager,
    viewDB: [1000][20]u8, // backing array to field below.

    picTex: clib.RenderTexture2D,
    show_background: bool = false,

    textGrid: [25][40]u8 = std.mem.zeroes([25][40]u8),

    newroom: u8,
    horizon: u8,
    allowInput: bool,
    haveKey: bool,
    programControl: bool,
    vars: [TOTAL_VARS]u8,
    flags: [TOTAL_FLAGS]bool,
    gameObjects: [TOTAL_GAME_OBJS]go.GameObject,

    logicStack: [LOGIC_STACK_SIZE]u8,
    logicStackPtr: usize,
    activeLogicNo: u8,

    blockX1: u8,
    blockX2: u8,
    blockY1: u8,
    blockY2: u8,

    logicIndex: [DIR_INDEX_SIZE]DirectoryIndex,
    picIndex: [DIR_INDEX_SIZE]DirectoryIndex,
    viewIndex: [DIR_INDEX_SIZE]DirectoryIndex,

    vmTimer: timer.VM_Timer,

    shaderSeconds: f32 = 0.0,

    // init creates a new instance of an AGI VM.
    pub fn init(debugState: bool) VM {
        var myVM = VM{ .picTex = undefined, .debug = debugState, .resMan = undefined, .viewDB = std.mem.zeroes([1000][20]u8), .vmTimer = undefined, .logicIndex = undefined, .picIndex = undefined, .viewIndex = undefined, .logicStack = std.mem.zeroes([LOGIC_STACK_SIZE]u8), .logicStackPtr = 0, .activeLogicNo = 0, .blockX1 = 0, .blockX2 = 0, .blockY1 = 0, .blockY2 = 0, .newroom = 0, .horizon = 0, .allowInput = false, .haveKey = false, .programControl = false, .vars = std.mem.zeroes([TOTAL_VARS]u8), .flags = std.mem.zeroes([TOTAL_FLAGS]bool), .gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject) };
        return myVM;
    }

    pub fn vm_bootstrap(self: *VM) !void {
        try loadFiles();

        // Seed directory index data, not worried about sound DIR for now.
        self.logicIndex = try buildDirIndex(agiFileList[@enumToInt(AGIFile.LOGDIR)]);
        self.picIndex = try buildDirIndex(agiFileList[@enumToInt(AGIFile.PICDIR)]);
        self.viewIndex = try buildDirIndex(agiFileList[@enumToInt(AGIFile.VIEWDIR)]);

        self.resMan = rm.ResourceManager.init(allocator);

        // Initialize shader (move this to func)
        const swirlShader = try self.resMan.add_shader(rm.WithKey(rm.ResourceTag.Shader, pathShaders ++ "wave.fs"));

        //const secondsLoc = clib.GetShaderLocation(swirlShader, "secondes");
        const freqXLoc = clib.GetShaderLocation(swirlShader, "freqX");
        const freqYLoc = clib.GetShaderLocation(swirlShader, "freqY");
        const ampXLoc = clib.GetShaderLocation(swirlShader, "ampX");
        const ampYLoc = clib.GetShaderLocation(swirlShader, "ampY");
        const speedXLoc = clib.GetShaderLocation(swirlShader, "speedX");
        const speedYLoc = clib.GetShaderLocation(swirlShader, "speedY");
        const freqX: f32 = 25.0;
        const freqY: f32 = 25.0;
        const ampX: f32 = 5.0;
        const ampY: f32 = 5.0;
        const speedX: f32 = 8.0;
        const speedY: f32 = 8.0;
        const screenSize: [2]f32 = [2]f32{ @intToFloat(f32, vm_width), @intToFloat(f32, vm_height) };

        clib.SetShaderValue(swirlShader, clib.GetShaderLocation(swirlShader, "size"), &screenSize, clib.SHADER_UNIFORM_VEC2);
        clib.SetShaderValue(swirlShader, freqXLoc, &freqX, clib.SHADER_UNIFORM_FLOAT);
        clib.SetShaderValue(swirlShader, freqYLoc, &freqY, clib.SHADER_UNIFORM_FLOAT);
        clib.SetShaderValue(swirlShader, ampXLoc, &ampX, clib.SHADER_UNIFORM_FLOAT);
        clib.SetShaderValue(swirlShader, ampYLoc, &ampY, clib.SHADER_UNIFORM_FLOAT);
        clib.SetShaderValue(swirlShader, speedXLoc, &speedX, clib.SHADER_UNIFORM_FLOAT);
        clib.SetShaderValue(swirlShader, speedYLoc, &speedY, clib.SHADER_UNIFORM_FLOAT);

        //var shaderSeconds: f32 = 0.0;
        self.shaderSeconds = 0.0;
    }

    pub fn vm_start(self: *VM) !void {
        // Initialize our picTex
        self.picTex = clib.LoadRenderTexture(1280, 672);

        // TODO: perhaps dependency inject the timer into the vmInstance before calling start.
        // TODO: tune the Timer such that it's roughly accurate 1/20hz
        // TODO: upon doing VM VAR reads where the timers redirect to the respective VM_Timer (sec, min, hrs, days) methods.
        self.vmTimer = try timer.VM_Timer.init();
        try self.vmTimer.start();

        // Reset all state here.
        // for (var i = 0; i < 255; i++) {
        //     this.variables[i] = 0;
        //     this.flags[i] = false;
        // }

        self.write_var(cmds.VM_VARS.CurrentRoom.into(), 0);
        self.write_var(cmds.VM_VARS.Monitor.into(), 3); // EGA
        self.write_var(cmds.VM_VARS.FreePages.into(), 255);
        self.write_var(cmds.VM_VARS.Volume.into(), 15);
        self.write_var(cmds.VM_VARS.MaxInputCharacters.into(), 41); // Input buffer size

        self.set_flag(cmds.VM_FLAGS.SoundOn.into(), true); // Sound enabled
        self.set_flag(cmds.VM_FLAGS.LogicZeroFirstTime.into(), true); // Logic 0 executed for the first time
        self.set_flag(cmds.VM_FLAGS.NewRoomExec.into(), true); // Room script executed for the first time

        try stmts.agi_unanimate_all(self);
        //self.agi_load_logic(0);
    }

    pub fn deinit(self: *VM) void {
        clib.UnloadRenderTexture(self.picTex);
        defer arena.deinit();
        defer self.resMan.deinit();
        defer self.vmTimer.deinit();
    }

    pub fn vm_reset(self: *VM) void {
        // TODO: reset all VM state.
        self.vm_log("reset_vm invoked with: {s}", .{self});
    }

    fn vm_set_ego_dir(self: *VM, newEgoDir: u8) void {
        const egoDir = self.read_var(6);
        self.write_var(cmds.VM_VARS.EgoDirection.into(), if (egoDir == newEgoDir) 0 else newEgoDir);
    }

    pub fn vm_cycle(self: *VM) !void {
        const swirlShader = self.resMan.ref_shader(rm.WithKey(rm.ResourceTag.Shader, pathShaders ++ "wave.fs"));
        self.shaderSeconds += clib.GetFrameTime() / 2.0;

        if (swirlShader) |sh| {
            const secondsLoc = clib.GetShaderLocation(sh, "secondes");
            clib.SetShaderValue(sh, secondsLoc, &self.shaderSeconds, clib.SHADER_UNIFORM_FLOAT);
        }

        self.set_flag(cmds.VM_FLAGS.EnteredCli.into(), false); // The player has entered a command
        self.set_flag(cmds.VM_FLAGS.SaidAcceptedInput.into(), false); // said accepted user input

        var egoObj = &self.gameObjects[0];

        var egoDir = self.read_var(6);
        // NOTE: re: self.programControl in other implementations (scummvm, nagi) the boolean flag tracked is playerControl so it's OPPOSITE!!!!
        if (self.programControl) {
            self.write_var(cmds.VM_VARS.EgoDirection.into(), @enumToInt(egoObj.direction));
            //egoDir = self.read_var(6);
        } else {
            //egoObj.direction = @intToEnum(go.Direction, egoDir);
            egoObj.direction = @intToEnum(go.Direction, egoDir);
            //self.write_var(cmds.VM_VARS.EgoDirection.into(), egoDir);
        }

        while (true) {
            {
                // TODO: clean this shit up.
                // Super ugly hack to pass dynamic args since we need to pass in an *aw.Args type.
                // But we only have to do this in a few spots and I will go back and clean this up.
                var buf: [1]u8 = undefined;
                var myArgs = &aw.Args.init(&buf);
                myArgs.set.a(0);
                try stmts.agi_call(self, myArgs);
            }

            self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 0);
            self.write_var(cmds.VM_VARS.BorderCode.into(), 0);

            self.set_flag(cmds.VM_FLAGS.LogicZeroFirstTime.into(), false); // Logic 0 executed for the first time.
            self.set_flag(cmds.VM_FLAGS.NewRoomExec.into(), false);
            self.set_flag(cmds.VM_FLAGS.RestartGame.into(), false);
            self.set_flag(cmds.VM_FLAGS.RestoreJustRan.into(), false);

            self.vm_draw_background();

            var i: usize = 0;
            while (i < self.gameObjects.len) : (i += 1) {
                var obj = &self.gameObjects[(self.gameObjects.len - 1) - i];
                if (obj.update) {
                    if (i == 0) {
                        obj.direction = @intToEnum(go.Direction, egoDir);
                    }

                    // TODO: updates should not also be drawing...so we need to draw the background + scene objects as a last step probably.
                    try self.vm_updateObject(i, obj);
                }
            }

            // Draw text grid perhaps.
            // TODO: move into a dedicated vm_draw_text func.
            for (self.textGrid) |r, v| {
                // 1. find first non-zero.
                var foundStr = false;
                var ii: usize = 0;
                while (ii < r.len) : (ii += 1) {
                    if (r[ii] != 0) {
                        foundStr = true;
                        break;
                    }
                }

                if (foundStr) {
                    // 2. find end of string.
                    var x: usize = ii;
                    while (x < r.len) : (x += 1) {
                        if (r[x] == 0) {
                            break;
                        }
                    }

                    // 3. Get pointer slice into data and dupe to a cstr.

                    const yUnit = 730 / (24 + 1);
                    const shadowOffset = 2;
                    const fontSize = yUnit;
                    const yOffset = yUnit * @intCast(c_int, v);

                    const word = r[ii..x];
                    var whiteSpace: [40]u8 = undefined;
                    std.mem.set(u8, &whiteSpace, ' ');
                    var buf: [40]u8 = undefined;
                    const result = try std.fmt.bufPrint(&buf, "{s}{s}", .{ whiteSpace[0 .. ii - 1], word });
                    const cstr = try tempAllocator.dupeZ(u8, result);
                    defer tempAllocator.free(cstr);

                    const textWidthSize = clib.MeasureText(cstr, fontSize);
                    const xOffset = (1280 / 2) - @intCast(c_int, (@intCast(u16, textWidthSize) / 2));

                    clib.DrawText(cstr, xOffset - shadowOffset, yOffset - shadowOffset, fontSize, clib.BLACK);
                    clib.DrawText(cstr, xOffset, yOffset, fontSize, clib.WHITE);
                }
            }

            if (self.newroom != 0) {
                // need to start handling this logic next, since new room is changed.
                try stmts.agi_stop_update(self, 0);
                try stmts.agi_unanimate_all(self);
                // RC: Not sure what to do with this line.
                //self.loadedLogics = self.loadedLogics.slice(0, 1);
                {
                    // TODO: clean this shit up.
                    // Super ugly hack to pass dynamic args since we need to pass in an *aw.Args type.
                    // But we only have to do this in a few spots and I will go back and clean this up.
                    var buf: [1]u8 = undefined;
                    var emptyArgs = &aw.Args.init(&buf);
                    try stmts.agi_player_control(self, emptyArgs);
                }

                try stmts.agi_unblock(self);

                {
                    // TODO: clean this shit up.
                    // Super ugly hack to pass dynamic args since we need to pass in an *aw.Args type.
                    // But we only have to do this in a few spots and I will go back and clean this up.
                    var buf: [1]u8 = undefined;
                    var myArgs = &aw.Args.init(&buf);
                    myArgs.set.a(36);
                    try stmts.agi_set_horizon(self, myArgs);
                }

                self.write_var(cmds.VM_VARS.PreviousRoom.into(), self.read_var(0));
                self.write_var(cmds.VM_VARS.CurrentRoom.into(), self.newroom);
                self.write_var(cmds.VM_VARS.BorderCode.into(), 0);
                self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 0);
                self.write_var(cmds.VM_VARS.WordNotFound.into(), 0);
                self.write_var(cmds.VM_VARS.EgoViewResource.into(), self.gameObjects[0].viewNo);

                switch (self.read_var(2)) {
                    // 0 => Touched nothing
                    // Top edge or horizon
                    1 => self.gameObjects[0].y = 168,
                    2 => self.gameObjects[0].x = 1,
                    3 => self.gameObjects[0].y = self.horizon,
                    4 => self.gameObjects[0].x = 160,
                    else => {},
                }

                self.write_var(cmds.VM_VARS.BorderTouchEgo.into(), 0);
                self.set_flag(cmds.VM_FLAGS.EnteredCli.into(), false);

                //this.agi_load_logic_v(0);
                self.set_flag(cmds.VM_FLAGS.NewRoomExec.into(), true);
                self.newroom = 0;
            } else {
                break;
            }
        }

        // TODO: copy frame over.
        // self.bltFrame();
    }

    fn vm_updateObject(self: *VM, idx: usize, obj: *go.GameObject) !void {
        if (obj.draw) {
            obj.oldX = obj.x;
            obj.oldY = obj.y;

            self.vm_log("updating objNo:{d}, gameObj:{any}", .{ idx, obj });

            var xStep = obj.stepSize;
            var yStep = obj.stepSize;

            switch (obj.movementFlag) {
                go.MovementFlags.MoveTo => {
                    if (obj.moveToStep != 0) {
                        xStep = obj.moveToStep;
                        yStep = obj.moveToStep;
                    }
                    if (obj.moveToX > obj.x) {
                        if (obj.moveToY > obj.y) {
                            obj.direction = go.Direction.DownRight;
                        } else if (obj.moveToY < obj.y) {
                            obj.direction = go.Direction.UpRight;
                        } else {
                            obj.direction = go.Direction.Right;
                        }
                    } else if (obj.moveToX < obj.x) {
                        if (obj.moveToY > obj.y) {
                            obj.direction = go.Direction.DownLeft;
                        } else if (obj.moveToY < obj.y) {
                            obj.direction = go.Direction.UpLeft;
                        } else {
                            obj.direction = go.Direction.Left;
                        }
                    } else {
                        if (obj.moveToY > obj.y) {
                            obj.direction = go.Direction.Down;
                        } else if (obj.moveToY < obj.y) {
                            obj.direction = go.Direction.Up;
                        }
                    }

                    // Some ugliness that could potentially be reduced to simpler code but Zig is so strict which is a good thing.
                    const absXStep = @intCast(u32, try std.math.absInt(@intCast(i32, @intCast(i32, obj.x) - @intCast(i32, obj.moveToX))));
                    const absYStep = @intCast(u32, try std.math.absInt(@intCast(i32, @intCast(i32, obj.y) - @intCast(i32, obj.moveToY))));
                    xStep = std.math.min(xStep, @truncate(u8, absXStep));
                    yStep = std.math.min(yStep, @truncate(u8, absYStep));
                },
                else => {
                    //TODO: other Motion Flag Types
                },
            }

            var newX = obj.x;
            var newY = obj.y;

            if (obj.direction == go.Direction.Up or obj.direction == go.Direction.UpRight or obj.direction == go.Direction.UpLeft) {
                newY = obj.y - yStep;
            } else if (obj.direction == go.Direction.Down or obj.direction == go.Direction.DownLeft or obj.direction == go.Direction.DownRight) {
                newY = obj.y + yStep;
            }

            if (obj.direction == go.Direction.Left or obj.direction == go.Direction.UpLeft or obj.direction == go.Direction.DownLeft) {
                newX = obj.x - xStep;
            } else if (obj.direction == go.Direction.Right or obj.direction == go.Direction.UpRight or obj.direction == go.Direction.DownRight) {
                newX = obj.x + xStep;
            }

            obj.x = newX;
            obj.y = newY;

            if ((obj.movementFlag == go.MovementFlags.MoveTo) and (obj.x == obj.moveToX) and (obj.y == obj.moveToY)) {
                obj.direction = go.Direction.Stopped;
                self.set_flag(obj.flagToSetWhenFinished, true);
                obj.movementFlag = go.MovementFlags.Normal;
            }

            if (obj.x != obj.oldX or obj.y != obj.oldY) {
                if (obj.x <= 0) {
                    if (idx == 0) {
                        self.write_var(cmds.VM_VARS.BorderTouchEgo.into(), 4);
                    } else {
                        self.write_var(cmds.VM_VARS.BorderCode.into(), @intCast(u8, idx));
                        self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 4);
                    }
                } else if (obj.x + try self.vm_cel_width(obj.viewNo, obj.loop, obj.cel) >= 160) {
                    if (idx == 0) {
                        self.write_var(cmds.VM_VARS.BorderTouchEgo.into(), 2);
                    } else {
                        self.write_var(cmds.VM_VARS.BorderCode.into(), @intCast(u8, idx));
                        self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 2);
                    }
                } else if (!obj.ignoreHorizon and obj.y <= self.horizon) {
                    if (idx == 0) {
                        self.write_var(cmds.VM_VARS.BorderTouchEgo.into(), 1);
                    } else {
                        self.write_var(cmds.VM_VARS.BorderCode.into(), @intCast(u8, idx));
                        self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 1);
                    }
                } else if (obj.y >= 168) {
                    if (idx == 0) {
                        self.write_var(cmds.VM_VARS.BorderTouchEgo.into(), 3);
                    } else {
                        self.write_var(cmds.VM_VARS.BorderCode.into(), @intCast(u8, idx));
                        self.write_var(cmds.VM_VARS.BorderTouchObject.into(), 3);
                    }
                }
            }

            if (!obj.fixedLoop) {
                const loopLength = self.vm_view_loop_count(obj.viewNo);
                if (loopLength > 1 and loopLength < 4) {
                    if (obj.direction == go.Direction.UpRight or obj.direction == go.Direction.Right or obj.direction == go.Direction.DownRight or
                        obj.direction == go.Direction.DownLeft or obj.direction == go.Direction.Left or obj.direction == go.Direction.UpLeft)
                    {
                        obj.loop = 1;
                    }
                } else if (loopLength >= 4) {
                    if (obj.direction == go.Direction.Up) {
                        obj.loop = 3;
                    } else if (obj.direction == go.Direction.UpRight or obj.direction == go.Direction.Right or obj.direction == go.Direction.DownRight) {
                        obj.loop = 0;
                    } else if (obj.direction == go.Direction.Down) {
                        obj.loop = 2;
                    } else if (obj.direction == go.Direction.DownLeft or obj.direction == go.Direction.Left or obj.direction == go.Direction.UpLeft) {
                        obj.loop = 1;
                    }
                }
            }

            if (obj.celCycling) {
                //std.log.info("view is cycling... v:{d}, l:{d}, c:{d}", .{ obj.viewNo, obj.loop, obj.cel });
                const celLength = @intCast(u8, self.vm_view_loop_cel_count(obj.viewNo, obj.loop));
                if (obj.nextCycle == 1) {
                    if (obj.reverseCycle) {
                        obj.cel -= 1;
                    } else {
                        obj.cel += 1;
                    }
                    var endOfLoop = false;
                    if (obj.cel < 0) {
                        if (obj.callAtEndOfLoop) {
                            obj.cel = 0;
                        } else {
                            obj.cel = celLength - 1;
                        }
                        endOfLoop = true;
                    } else if (obj.cel > celLength - 1) {
                        if (obj.callAtEndOfLoop) {
                            obj.cel = celLength - 1;
                        } else {
                            obj.cel = 0;
                        }
                        endOfLoop = true;
                    }
                    if (endOfLoop and obj.callAtEndOfLoop) {
                        obj.celCycling = false;
                        self.set_flag(obj.flagToSetWhenFinished, true);
                    }
                    obj.nextCycle = obj.cycleTime;
                } else obj.nextCycle -= 1;
            }

            // NOTE: this code is getting there.
            // 1. still need to handle mirror states somehow.
            // 2. I shouldn't be drawing immediately from an update method.

            //std.log.info("larry => \n egoDir => {d}, movementFlag => {s}, dir => {s}", .{ self.read_var(6), obj.movementFlag, obj.direction });
            try self.vm_draw_view(obj.viewNo, obj.loop, obj.cel, @intToFloat(f32, obj.x), @intToFloat(f32, obj.y));
        }
    }

    pub fn vm_view_key(buffer: []u8, viewNo: u8, loop: u8, cel: u8) ![]u8 {
        var fmtStr = try std.fmt.bufPrint(buffer[0..], "{s}{d}_{d}_{d}.png", .{ pathTextures, viewNo, loop, cel });
        return fmtStr;
    }

    pub fn vm_draw_view(self: *VM, viewNo: u8, loop: u8, cel: u8, x: f32, y: f32) anyerror!void {
        var buf: [100]u8 = undefined;
        const fmtStr = try vm_view_key(&buf, viewNo, loop, cel);
        const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

        if (texture) |txt| {
            self.vm_log("FOUND view:{d}, loop:{d}, cel:{d} => {s}", .{ viewNo, loop, cel, fmtStr });

            // Scaling comes from the fact that these assets were upscaled by a factor of 4 with an additional *2 for the x-axis.
            // Additionally, the assets y-origin should is their bottom, so we substract the view height for the y-axis.
            // https://github.com/barryharmsen/ExtractAGI/blob/master/export_view.py
            const scaledX = x * 2 * 4;
            const scaledY = (y * 4) - @intToFloat(f32, txt.height);

            clib.DrawTexturePro(txt, hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.rect(scaledX, scaledY, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.vec2(0, 0), 0, clib.WHITE);
        } else {
            std.log.warn("NOT FOUND view:{d}, loop:{d}, cel:{d} => {s}", .{ viewNo, loop, cel, fmtStr });
            std.os.exit(39);
        }
    }

    pub fn vm_pic_key(buffer: []u8, picNo: u8) ![]u8 {
        var fmtStr = try std.fmt.bufPrint(buffer[0..], "{s}{d}_pic.png", .{ pathPics, picNo });
        return fmtStr;
    }

    // vm_draw_pic draws a primary static background pic to the picTex render texture.
    pub fn vm_draw_pic(self: *VM, picNo: u8) anyerror!void {
        var buf: [100]u8 = undefined;
        const fmtStr = try vm_pic_key(&buf, picNo);
        const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

        if (texture) |txt| {
            self.vm_log("FOUND picNo:{d} => {s}", .{ picNo, fmtStr });
            clib.BeginTextureMode(self.picTex);
            defer clib.EndTextureMode();
            clib.DrawTexturePro(txt, hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.vec2(0, 0), 0, clib.WHITE);
        } else {
            std.log.warn("NOT FOUND picNo:{d} => {s}", .{ picNo, fmtStr });
            std.os.exit(39);
        }
    }

    // vm_add_view_to_pic_at draws an ADDED static view to the background buffer (picTex).
    pub fn vm_add_view_to_pic_at(self: *VM, viewNo: u8, loopNo: u8, celNo: u8, x: u8, y: u8, priority: u8, margin: u8) anyerror!void {
        var buf: [100]u8 = undefined;
        const fmtStr = try vm_view_key(&buf, viewNo, loopNo, celNo);
        const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

        if (texture) |txt| {
            self.vm_log("FOUND viewNo:{d}, {d}:priority, {d}:margin => {s}", .{ viewNo, priority, margin, fmtStr });
            clib.BeginTextureMode(self.picTex);
            defer clib.EndTextureMode();

            // Scaling comes from the fact that these assets were upscaled by a factor of 4 with an additional *2 for the x-axis.
            // Additionally, the assets y-origin should is their bottom, so we substract the view height for the y-axis.
            // https://github.com/barryharmsen/ExtractAGI/blob/master/export_view.py
            const scaledX = @intToFloat(f32, @intCast(u16, x) * 2 * 4);
            const scaledY = @intToFloat(f32, @intCast(u16, y) * 4) - @intToFloat(f32, txt.height);

            clib.DrawTexturePro(txt, hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.rect(scaledX, scaledY, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.vec2(0, 0), 0, clib.WHITE);
            clib.DrawRectangleLines(@floatToInt(c_int, scaledX), @floatToInt(c_int, scaledY), txt.width, txt.height, clib.RED);
        } else {
            std.log.warn("NOT FOUND viewNo:{d}, {d}:priority, {d}:margin=> {s}", .{ viewNo, priority, margin, fmtStr });
            std.os.exit(39);
        }
    }

    // vm_draw_background blits the entire pic+static views (added to pic) to the screen.
    pub fn vm_draw_background(self: *VM) void {
        const swirlShader = self.resMan.ref_shader(rm.WithKey(rm.ResourceTag.Shader, pathShaders ++ "wave.fs")).?;
        clib.BeginShaderMode(swirlShader);
        defer clib.EndShaderMode();

        clib.DrawTextureRec(self.picTex.texture, hlp.rect(0, 0, @intToFloat(f32, self.picTex.texture.width), @intToFloat(f32, -self.picTex.texture.height)), hlp.vec2(0, 0), clib.WHITE);
    }

    fn vm_cel_width(self: *VM, viewNo: u8, loop: u8, cel: u8) !c_int {
        var buf: [100]u8 = undefined;
        const fmtStr = try vm_view_key(&buf, viewNo, loop, cel);
        const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

        if (texture) |txt| {
            return txt.width;
        }
        // TODO: returning a hardcoded texture width for now... ugh.
        return 100;
    }

    pub fn vm_exec_logic(self: *VM, idx: usize, vol: usize, offset: u32) anyerror!void {
        // exec_arena lives for the life of this func: vm_exec_logic call.
        var exec_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const exec_allocator = exec_arena.allocator();
        defer exec_arena.deinit();

        // Select volume.
        var fbs = switch (vol) {
            0 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_0)]),
            1 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_1)]),
            2 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_2)]),
            else => unreachable,
        };

        // Parse header.
        try fbs.seekTo(offset);

        // Signature is always: 0x1234. (Big End..)
        // Arbitrary endian-ness...FU Sierra.
        const sig: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Big);
        const volNo: u8 = try fbs.reader().readByte();
        const resLength: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Little);

        self.vm_log("idx => {d}, sig => {d}, vol/volNo => {d}/{d}, resLength => {d}", .{ idx, sig, vol, volNo, resLength });

        const newStartOffset = offset + 5;
        const newEndOffset = newStartOffset + resLength;

        // Parse volume part.
        // self.vm_log("[{d}..{d}] - max size: {d}", .{ newStartOffset, newEndOffset, fbs.getEndPos() });
        var volPartFbs = switch (volNo) {
            0 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_0)][newStartOffset..newEndOffset]),
            1 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_1)][newStartOffset..newEndOffset]),
            2 => std.io.fixedBufferStream(agiFileList[@enumToInt(AGIFile.VOL_2)][newStartOffset..newEndOffset]),
            else => unreachable,
        };

        // Parse message strings first.
        var messageMap = std.AutoHashMap(usize, []const u8).init(exec_allocator);

        // TODO: finish parsing messages and if it works it should XOR with the encryption key: "Avis Durgan" defined above.
        const messageOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
        //self.vm_log("messageOffset => {d}", .{messageOffset});

        try volPartFbs.seekBy(messageOffset);
        const pos = try volPartFbs.getPos();
        //this.messageStartOffset = pos;
        const numMessages = try volPartFbs.reader().readByte();
        _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);

        var decryptIndex: usize = 0;
        var i: usize = 0;
        while (i < numMessages) : (i += 1) {
            const msgOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
            if (msgOffset == 0) {
                continue;
            }

            var msgStr = ArrayList(u8).init(allocator);
            defer msgStr.deinit();

            const mPos = try volPartFbs.getPos();
            try volPartFbs.seekTo(pos + msgOffset + 1);
            while (true) {
                const currentChar = try volPartFbs.reader().readByte();
                const decryptedChar = currentChar ^ messageDecryptKey[decryptIndex];
                try msgStr.append(decryptedChar);
                decryptIndex += 1;
                if (decryptIndex >= messageDecryptKey.len) {
                    decryptIndex = 0;
                }

                if (decryptedChar == 0) {

                    // IMPORTANT: msgIndex must be whatever i is + 1 to be correct.
                    // BIG TODO: in the game logic loop, no need to keep parsing messages over and over

                    const msgIndex = i + 1;
                    const msgLen = msgStr.items.len - 1;
                    const dupeStr = try exec_allocator.dupe(u8, msgStr.items[0..msgLen]);
                    try messageMap.put(msgIndex, dupeStr);
                    self.vm_log("logicNo:{d} msgLen: {d}, msgStr => \"{s}\"", .{ idx, msgLen, msgStr.items[0..msgLen] });
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
            self.vm_log("activeLogicNo => {d}", .{self.activeLogicNo});
            // TODO: (DELETE ME) Safety to prevent runaway..
            if (maxIters > 1200) {
                self.vm_log("max iterations MET!!!", .{});
                std.os.exit(9);
            }
            maxIters += 1;

            const opCodeNR = volPartFbs.reader().readByte() catch |e| {
                switch (e) {
                    error.EndOfStream => {
                        self.vm_log("end of logic script({d}) encountered so BREAKing...", .{idx});
                        break;
                    },
                }
            };

            //self.vm_log("opCodeNR => {X:0>2}", .{opCodeNR});
            switch (opCodeNR) {
                0x00 => {
                    self.vm_log("{X:0>2} => return", .{opCodeNR});
                    break;
                },
                0x91 => self.vm_log("{X:0>2} => set.scan.start", .{opCodeNR}),
                0x92 => self.vm_log("{X:0>2} => reset.scan.start", .{opCodeNR}),
                0xFE => {
                    const n1: u32 = try volPartFbs.reader().readByte();
                    const n2: u32 = try volPartFbs.reader().readByte();
                    const gotoOffset = (((n2 << 8) | n1) << 16) >> 16;
                    self.vm_log("{X:0>2} => goto, offset: {d}", .{ opCodeNR, gotoOffset });
                    // NOTE: doing a RELATIVE jump: seekBy NOT seekTo (absolute)
                    try volPartFbs.seekBy(gotoOffset);
                },
                0xFF => {
                    self.vm_log("{X:0>2} => if", .{opCodeNR});
                    if (testMode) {
                        testMode = false;
                        const elseOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
                        if (!testResult) {
                            // False conditional block. (jump over true block).
                            self.vm_log("doing a false test jump over true!!!", .{});
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
                        self.vm_log("{X:0>2} ELSE", .{opCodeNR});
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
                            if ((opCodeNR - 1) >= cmds.agi_predicates.len) {
                                self.vm_log("FATAL: trying to fetch a test from index: {d}", .{opCodeNR - 1});
                                return;
                            }

                            var predicateCallResult = false;
                            const predicateFunc = cmds.agi_predicates[opCodeNR - 1];
                            errdefer std.log.warn("predicate ERRORED: \"{s}\"", .{predicateFunc.name});

                            self.vm_log("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, predicateFunc.name, predicateFunc.arity });

                            // buf for statement args, which gets sliced as needed.
                            var buf: [30]u8 = undefined;
                            var myArgs = &aw.Args.init(&buf);

                            if (std.mem.eql(u8, predicateFunc.name, "said")) {
                                // First fetch number of args this op uses.
                                const saidArgLen = try volPartFbs.reader().readByte();

                                // Multiply by 2 because "said" requires 16-bit args so we need to consume double the amount.
                                const actualArgLen = saidArgLen * 2;
                                predicateCallResult = try predicateFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, actualArgLen)));
                            } else {
                                predicateCallResult = try predicateFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, predicateFunc.arity)));
                            }

                            if (invertMode) {
                                invertMode = false;
                                predicateCallResult = !predicateCallResult;
                            }

                            if (orMode) {
                                orResult = orResult or predicateCallResult;
                            } else {
                                testResult = testResult and predicateCallResult;
                            }
                        }
                    } else {
                        const statementFunc = cmds.agi_statements[opCodeNR];

                        // buf for statement args, which gets sliced as needed.
                        var buf: [10]u8 = undefined;
                        var myArgs = &aw.Args.init(&buf);

                        errdefer std.log.warn("statement ERRORED: \"{s}\"", .{statementFunc.name});
                        if (opCodeNR == 103) {
                            const ctx = aw.Context{ .messageMap = &messageMap };
                            try stmts.agi_display_ctx(self, &ctx, try myArgs.eat(&volPartFbs, @intCast(usize, statementFunc.arity)));
                        } else if (opCodeNR == 104) {
                            const ctx = aw.Context{ .messageMap = &messageMap };
                            try stmts.agi_display_v_ctx(self, &ctx, try myArgs.eat(&volPartFbs, @intCast(usize, statementFunc.arity)));
                        } else {
                            try statementFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, statementFunc.arity)));
                        }

                        // Finally, special handling for new.room opcode.
                        if (opCodeNR == 0x12) {
                            self.vm_log("new.room opcode special handling (BREAKS)...", .{});
                            try volPartFbs.seekTo(0);
                            break;
                        }
                    }
                },
            }
        }
    }

    fn vm_breakpoint(self: *VM) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        try stdout.print("(BREAKPOINT HIT): ", .{});

        var buf: [10]u8 = undefined;
        while (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
            if (std.mem.eql(u8, user_input, "c")) {
                break;
            } else if (std.mem.eql(u8, user_input, "q")) {
                try stdout.print("Quitting...\n", .{});
                std.os.exit(0);
            } else if (std.mem.startsWith(u8, user_input, "v")) {
                const varIdx = try std.fmt.parseInt(usize, user_input[1..], 10);
                try stdout.print("var[{d}] => {d}\n", .{ varIdx, self.read_var(varIdx) });
            } else if (std.mem.startsWith(u8, user_input, "f")) {
                const flagIdx = try std.fmt.parseInt(usize, user_input[1..], 10);
                try stdout.print("flag[{d}] => {s}\n", .{ flagIdx, self.get_flag(flagIdx) });
            } else {
                try stdout.print("??\n", .{});
            }

            try stdout.print("(C:c)ontinue, (Q:q)uit\n", .{});
            try stdout.print("> ", .{});
        }
    }

    pub fn vm_push_logic_stack(self: *VM, logicNo: u8) void {
        if (self.logicStackPtr == LOGIC_STACK_SIZE - 1) {
            std.os.exit(9);
            self.vm_log("OH NO: stack over flow beyatch!", .{});
        }
        self.logicStack[self.logicStackPtr] = logicNo;
        self.logicStackPtr += 1;
    }

    pub fn vm_pop_logic_stack(self: *VM) u8 {
        if (self.logicStackPtr == 0) {
            self.vm_log("OH NO: stack under flow beyatch!", .{});
            std.os.exit(9);
        }

        const logicNo = self.logicStack[self.logicStackPtr];
        self.logicStackPtr -= 1;
        return logicNo;
    }

    pub fn vm_op_not_implemented(self: *VM, statusCode: u8) void {
        self.vm_log("vm_op_not_implemented({d}) exited...", .{statusCode});
        std.os.exit(statusCode);
    }

    pub fn vm_log(self: *VM, comptime format: []const u8, args: anytype) void {
        if (self.debug) {
            std.log.debug(format, args);
        }
    }

    pub fn read_var(self: *VM, varNo: usize) u8 {
        // We intercept reads to the following declared switch to cope with intrinsic vars such as timers.
        // NOTE: should the values below get set, the VM will still do it...but not return the data since this is intercepted on read.
        if ((varNo > 0) and (varNo <= 29)) {
            switch (@intToEnum(cmds.VM_VARS, varNo)) {
                cmds.VM_VARS.Seconds => return self.vmTimer.secs(),
                cmds.VM_VARS.Minutes => return self.vmTimer.mins(),
                cmds.VM_VARS.Hours => return self.vmTimer.hrs(),
                cmds.VM_VARS.Days => return self.vmTimer.days(),
                else => return self.vars[varNo],
            }
        }

        return self.vars[varNo];
    }

    // Both write_var and mut_var should be the only places allowed to mutate a variable.
    // So these would be the places to gate any variable writing to the VM.
    pub fn write_var(self: *VM, varNo: usize, val: u8) void {
        self.vars[varNo] = val;
    }

    pub fn mut_var(self: *VM, varNo: usize, op: []const u8, by: u8) void {
        if (std.mem.eql(u8, op, "+=")) {
            self.vars[varNo] += by;
        } else if (std.mem.eql(u8, op, "-=")) {
            self.vars[varNo] -= by;
        } else if (std.mem.eql(u8, op, "*=")) {
            self.vars[varNo] *= by;
        } else if (std.mem.eql(u8, op, "/=")) {
            self.vars[varNo] /= by;
        } else {
            std.log.warn("bad mut_var operation of: {s} for varNo: {d}, by: {d}", .{ op, varNo, by });
            unreachable;
        }
    }

    pub fn get_flag(self: *VM, flagNo: usize) bool {
        //HACK to always return the musicDone is true, until we implement audio someday.
        switch (flagNo) {
            52 => return true, // 52 in LSL1 (for other games who knows...)
            else => return self.flags[flagNo],
        }
    }

    pub fn set_flag(self: *VM, flagNo: usize, state: bool) void {
        self.flags[flagNo] = state;
    }

    pub fn vm_reset_viewDB(self: *VM) void {
        self.viewDB = std.mem.zeroes([1000][20]u8);
    }

    pub fn vm_view_loop_count(self: *VM, viewNo: usize) usize {
        var i: usize = 0;
        var counter: usize = 0;
        while (i < self.viewDB[viewNo].len) : (i += 1) {
            if (self.viewDB[viewNo][i] > 0) {
                counter += 1;
            }
        }
        return counter;
    }

    pub fn vm_view_loop_cel_count(self: *VM, viewNo: usize, loopNo: usize) usize {
        return self.viewDB[viewNo][loopNo];
    }
};
