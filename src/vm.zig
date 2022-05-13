const std = @import("std");
const ArrayList = std.ArrayList;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

const prompt = @import("prompt.zig");
const go = @import("game_object.zig");
const cmds = @import("agi_cmds.zig");
const hlp = @import("raylib_helpers.zig");

const clib = @import("c_defs.zig").c;
const timer = @import("sys_timers.zig");
const rm = @import("resource_manager.zig");

const pathTextures = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/extracted/view/";
const sampleTexture = pathTextures ++ "43_0_0.png";

// HACK zone, just doing a quick and dirty comptime embed file.
const rootPath = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/";
const logDirFile = @embedFile(rootPath ++ "LOGDIR");
const picDirFile = @embedFile(rootPath ++ "PICDIR");
const viewDirFile = @embedFile(rootPath ++ "VIEWDIR");
// const sndDirFile = @embedFile(rootPath ++ "SNDDIR");
const vol0 = @embedFile(rootPath ++ "VOL.0");
const vol1 = @embedFile(rootPath ++ "VOL.1");
const vol2 = @embedFile(rootPath ++ "VOL.2");

const messageDecryptKey = "Avis Durgan";

const TOTAL_VARS: usize = 256;
const TOTAL_FLAGS: usize = 256;
const TOTAL_CONTROLLERS: usize = 256;

const TOTAL_GAME_OBJS: usize = 16; // also called screen objs.

const LOGIC_STACK_SIZE: usize = 255; // Arbitrary size has been chosen of 255, I don't expect to exceed it with tech from 1980s.
const DIR_INDEX_SIZE: usize = 300;

const DirectoryIndex = struct {
    vol: u32,
    offset: u32,
};

const vm_width = 1280;
const vm_height = 672;

//pub var visualBuffer = clib.GenImageColor(vm_width, vm_height, hlp.col(255, 255, 255, 255));
// pub var priorityBuffer = clib.GenImageColor(vm_width, vm_height, hlp.col(255, 255, 255, 255));
// pub var framePriorityData = clib.GenImageColor(vm_width, vm_height, hlp.col(255, 255, 255, 255));
// pub var frameData = clib.GenImageColor(vm_width, vm_height, hlp.col(255, 255, 255, 255));

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

// const viewRecord = struct {
//     loopNo: u8,
//     celCount: u8,
// };

pub const VM = struct {
    debug: bool,
    resMan: rm.ResourceManager,
    viewDB: [1000][20]u8, // backing array to field below.

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

    // init creates a new instance of an AGI VM.
    pub fn init(debugState: bool) VM {
        var myVM = VM{ .debug = debugState, .resMan = undefined, .viewDB = std.mem.zeroes([1000][20]u8), .vmTimer = undefined, .logicIndex = undefined, .picIndex = undefined, .viewIndex = undefined, .logicStack = std.mem.zeroes([LOGIC_STACK_SIZE]u8), .logicStackPtr = 0, .activeLogicNo = 0, .blockX1 = 0, .blockX2 = 0, .blockY1 = 0, .blockY2 = 0, .newroom = 0, .horizon = 0, .allowInput = false, .haveKey = false, .programControl = false, .vars = std.mem.zeroes([TOTAL_VARS]u8), .flags = std.mem.zeroes([TOTAL_FLAGS]bool), .gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject) };
        return myVM;
    }

    pub fn vm_bootstrap(self: *VM) !void {
        self.resMan = rm.ResourceManager.init(allocator);

        // Seed directory index data, not worried about sound DIR for now.
        self.logicIndex = try buildDirIndex(logDirFile);
        self.picIndex = try buildDirIndex(picDirFile);
        self.viewIndex = try buildDirIndex(viewDirFile);
    }

    pub fn vm_start(self: *VM) !void {
        // TODO: perhaps dependency inject the timer into the vmInstance before calling start.
        // TODO: tune the Timer such that it's roughly accurate
        // TODO: upon doing VM VAR reads where the timers redirect to the respective VM_Timer (sec, min, hrs, days) methods.
        self.vmTimer = try timer.VM_Timer.init();
        try self.vmTimer.start();

        // Reset all state here.
        // for (var i = 0; i < 255; i++) {
        //     this.variables[i] = 0;
        //     this.flags[i] = false;
        // }

        self.vars[0] = 0;
        self.vars[26] = 3; // EGA
        self.vars[8] = 255; // Pages of free memory
        self.vars[23] = 15; // Sound volume
        self.vars[24] = 41; // Input buffer size
        self.flags[9] = true; // Sound enabled
        self.flags[11] = true; // Logic 0 executed for the first time
        self.flags[5] = true; // Room script executed for the first time

        self.agi_unanimate_all();
        //self.agi_load_logic(0);
    }

    pub fn deinit(self: *VM) void {
        defer arena.deinit();
        defer self.resMan.deinit();
        defer self.vmTimer.deinit();
    }

    pub fn vm_reset(self: *VM) void {
        self.vm_log("reset_vm invoked with: {s}", .{self});
    }

    fn vm_set_ego_dir(self: *VM, newEgoDir: u8) void {
        const egoDir = self.read_var(6);
        self.vars[6] = if (egoDir == newEgoDir) 0 else newEgoDir;
    }

    pub fn vm_cycle(self: *VM) !void {
        self.flags[2] = false; // The player has entered a command
        self.flags[4] = false; // said accepted user input

        var egoObj = &self.gameObjects[0];

        var egoDir = self.read_var(6);
        if (self.programControl) {
            self.vars[6] = @enumToInt(egoObj.direction);
            std.log.info("vars[6] => {d}", .{self.read_var(6)});
            //egoDir = self.read_var(6);
        } else {
            egoObj.direction = @intToEnum(go.Direction, egoDir);
            //self.vars[6] = egoDir;
        }

        var outer_call_count: usize = 0;
        defer std.log.info("outer_call_count: {d}", .{outer_call_count});

        while (true) {
            defer outer_call_count += 1;
            try self.agi_call(0);
            self.flags[11] = false; // Logic 0 executed for the first time.

            // TODO: figure out what these are supposed to represent.
            self.vars[5] = 0;
            self.vars[4] = 0;
            self.flags[5] = false;
            self.flags[6] = false;
            self.flags[12] = false;

            var i: usize = 0;
            while (i < self.gameObjects.len) : (i += 1) {
                var obj = &self.gameObjects[i];
                if (obj.update) {
                    if (i == 0) {
                        obj.direction = @intToEnum(go.Direction, egoDir);
                    }
                    try self.vm_updateObject(i, obj);
                }
            }

            if (self.newroom != 0) {
                // need to start handling this logic next, since new room is changed.
                self.agi_stop_update(0);
                self.agi_unanimate_all();
                // RC: Not sure what to do with this line.
                //self.loadedLogics = self.loadedLogics.slice(0, 1);
                self.agi_player_control();
                self.agi_unblock();
                self.agi_set_horizon(36);

                self.vars[1] = self.read_var(0);
                self.vars[0] = self.newroom;
                self.vars[4] = 0;
                self.vars[5] = 0;
                self.vars[9] = 0;
                self.vars[16] = self.gameObjects[0].viewNo;

                switch (self.read_var(2)) {
                    // 0 => Touched nothing
                    // Top edge or horizon
                    1 => self.gameObjects[0].y = 168,
                    2 => self.gameObjects[0].x = 1,
                    3 => self.gameObjects[0].y = self.horizon,
                    4 => self.gameObjects[0].x = 160,
                    else => {},
                }

                self.vars[2] = 0;
                self.flags[2] = false;

                //this.agi_load_logic_v(0);
                self.flags[5] = true;
                self.newroom = 0;
                //unreachable;
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

            std.log.info("updating objNo:{d}, gameObj:{any}", .{ idx, obj });

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
                // TODO: use a proper setter func like: self.write_flag(idx) = state;
                self.flags[obj.flagToSetWhenFinished] = true;
                obj.movementFlag = go.MovementFlags.Normal;
            }

            if (obj.x != obj.oldX or obj.y != obj.oldY) {
                if (obj.x <= 0) {
                    if (idx == 0) {
                        self.vars[2] = 4;
                    } else {
                        self.vars[4] = @intCast(u8, idx);
                        self.vars[5] = 4;
                    }
                } else if (obj.x + try self.vm_cel_width(obj.viewNo, obj.loop, obj.cel) >= 160) {
                    if (idx == 0) {
                        self.vars[2] = 2;
                    } else {
                        self.vars[4] = @intCast(u8, idx);
                        self.vars[5] = 2;
                    }
                } else if (!obj.ignoreHorizon and obj.y <= self.horizon) {
                    if (idx == 0) {
                        self.vars[2] = 1;
                    } else {
                        self.vars[4] = @intCast(u8, idx);
                        self.vars[5] = 1;
                    }
                } else if (obj.y >= 168) {
                    if (idx == 0) {
                        self.vars[2] = 3;
                    } else {
                        self.vars[4] = @intCast(u8, idx);
                        self.vars[5] = 3;
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
                        self.flags[obj.flagToSetWhenFinished] = true;
                    }
                    obj.nextCycle = obj.cycleTime;
                } else obj.nextCycle -= 1;
            }

            // NOTE: this code is getting there.
            // 1. need to draw the correct sizing/x,y placement for higher resolution assets (factor of 4 times bigger)

            //std.log.info("larry => \n egoDir => {d}, movementFlag => {s}, dir => {s}", .{ self.read_var(6), obj.movementFlag, obj.direction });
            std.log.info("egoDir => {d}, egoX => {d}, oldEgoX => {d}, egoY => {d}, oldEgoY => {d}", .{ self.read_var(6), self.read_var(38), self.read_var(40), self.read_var(39), self.read_var(41) });
            try self.vm_draw_view(obj.viewNo, obj.loop, obj.cel, @intToFloat(f32, obj.x), @intToFloat(f32, obj.y));
        }
    }

    fn vm_view_key(buffer: []u8, viewNo: u8, loop: u8, cel: u8) ![]u8 {
        var fmtStr = try std.fmt.bufPrint(buffer[0..], "{s}{d}_{d}_{d}.png", .{ pathTextures, viewNo, loop, cel });
        return fmtStr;
    }

    pub fn vm_draw_view(self: *VM, viewNo: u8, loop: u8, cel: u8, x: f32, y: f32) anyerror!void {
        var buf: [100]u8 = undefined;
        const fmtStr = try vm_view_key(&buf, viewNo, loop, cel);
        const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

        if (texture) |txt| {
            std.log.info("FOUND view:{d}, loop:{d}, cel:{d} => {s}", .{ viewNo, loop, cel, fmtStr });
            clib.DrawTexturePro(txt, hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.rect(x, y, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.vec2(0, 0), 0, clib.WHITE);
        } else {
            std.log.warn("NOT FOUND view:{d}, loop:{d}, cel:{d} => {s}", .{ viewNo, loop, cel, fmtStr });
            std.os.exit(39);
        }
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
        // Select volume.
        var fbs = switch (vol) {
            0 => std.io.fixedBufferStream(vol0),
            1 => std.io.fixedBufferStream(vol1),
            2 => std.io.fixedBufferStream(vol2),
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
            0 => std.io.fixedBufferStream(vol0[newStartOffset..newEndOffset]),
            1 => std.io.fixedBufferStream(vol1[newStartOffset..newEndOffset]),
            2 => std.io.fixedBufferStream(vol2[newStartOffset..newEndOffset]),
            else => unreachable,
        };

        // Parse message strings first.

        // TODO: finish parsing messages and if it works it should XOR with the encryption key: "Avis Durgan" defined above.
        const messageOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
        //self.vm_log("messageOffset => {d}", .{messageOffset});

        try volPartFbs.seekBy(messageOffset);
        const pos = try volPartFbs.getPos();
        //this.messageStartOffset = pos;
        const numMessages = try volPartFbs.reader().readByte();
        //self.vm_log("no. messages => {d}", .{numMessages});
        _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);

        var decryptIndex: usize = 0;
        var i: usize = 0;
        while (i < numMessages) : (i += 1) {
            const msgPtr = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
            if (msgPtr == 0) {
                continue;
            }

            // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            // defer arena.deinit();
            // const allocator = arena.allocator();

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
                        self.vm_log("msgStr => \"{s}\"", .{msgStr.items[0 .. msgStr.items.len - 1]});
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

        var exec_logic_count: usize = 0;
        defer std.log.info("exec_logic({d}) inner loop count: {d}", .{ idx, exec_logic_count });
        while (true) {
            defer exec_logic_count += 1;
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
                            if ((opCodeNR - 1) >= cmds.agi_tests.len) {
                                self.vm_log("FATAL: trying to fetch a test from index: {d}", .{opCodeNR - 1});
                                return;
                            }
                            const testFunc = cmds.agi_tests[opCodeNR - 1];
                            var testCallResult = false;

                            self.vm_log("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, testFunc.name, testFunc.arity });
                            if (opCodeNR == 0x0E) { //Said (uses variable num of 16-bit args, within bytecode!)
                                const saidArgLen = try volPartFbs.reader().readByte();
                                var iSaidCount: usize = 0;

                                // Using an array of a fixed 30 size and will slice upon passing (should be plenty big).
                                var argsToPass: [30]u16 = undefined;
                                while (iSaidCount < saidArgLen) : (iSaidCount += 1) {
                                    const val = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
                                    argsToPass[iSaidCount] = val;
                                }
                                // Invocation is hardcoded to nonsense array of: 1,2,3 for now.
                                testResult = self.agi_test_said(argsToPass[0..iSaidCount]);
                            } else {
                                if (std.mem.eql(u8, testFunc.name, "greatern")) {
                                    const a = try volPartFbs.reader().readByte();
                                    const b = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_greatern(a, b);
                                    self.vm_log("test_greatern({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "isset")) {
                                    const a = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_isset(a);
                                    self.vm_log("isset({d})", .{a});
                                } else if (std.mem.eql(u8, testFunc.name, "controller")) {
                                    const a = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_controller(a);
                                    self.vm_log("test_controller({d})", .{a});
                                } else if (std.mem.eql(u8, testFunc.name, "equaln")) {
                                    const a = try volPartFbs.reader().readByte();
                                    const b = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_equaln(a, b);
                                    self.vm_log("test_equaln({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "equalv")) {
                                    const a = try volPartFbs.reader().readByte();
                                    const b = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_equalv(a, b);
                                    self.vm_log("test_equalv({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "have_key")) {
                                    testCallResult = self.agi_test_have_key();
                                    self.vm_log("agi_test_have_key()", .{});
                                } else {
                                    self.vm_log("test op:{d}(0x{X:0>2}) not handled!", .{ opCodeNR - 1, opCodeNR - 1 });
                                    self.vm_op_not_implemented(35);
                                }
                            }

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

                        // Note: can't use a switch on strings in Zig.
                        if (std.mem.eql(u8, statementFunc.name, "new_room")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_new_room(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "quit")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_quit(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "call")) {
                            const a = try volPartFbs.reader().readByte();
                            try self.agi_call(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "call_v")) {
                            const a = try volPartFbs.reader().readByte();
                            try self.agi_call_v(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "force_update")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_force_update(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "assignn")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_assignn(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "assignv")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_assignv(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "clear_lines")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_clear_lines(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "display")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_display(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "display_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_display_v(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "set")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_set(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "prevent_input")) {
                            self.agi_prevent_input();
                        } else if (std.mem.eql(u8, statementFunc.name, "reset")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_reset(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "reset_v")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_reset_v(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "animate_obj")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_animate_obj(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "step_size")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_step_size(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "step_time")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_step_time(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "cycle_time")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_cycle_time(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "get_posn")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_get_posn(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "position")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_position(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "position_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_position_v(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "reposition_to")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_reposition_to(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "reposition_to_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            self.agi_reposition_to_v(a, b, c);
                        } else if (std.mem.eql(u8, statementFunc.name, "observe_blocks")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_observe_blocks(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "observe_objs")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_observe_objs(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "ignore_objs")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_ignore_objs(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "observe_horizon")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_observe_horizon(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "fix_loop")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_fix_loop(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "release_loop")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_release_loop(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "lindirectn")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_lindirectn(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "increment")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_increment(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "decrement")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_decrement(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "load_view_v")) {
                            const a = try volPartFbs.reader().readByte();
                            try self.agi_load_view_v(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "load_view")) {
                            const a = try volPartFbs.reader().readByte();
                            try self.agi_load_view(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_view")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_view(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_view_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_view_v(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_horizon")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_set_horizon(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "load_sound")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_load_sound(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "load_pic")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_load_pic(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "draw_pic")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_draw_pic(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "draw")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_draw(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "discard_pic")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_discard_pic(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "sound")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_sound(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_loop")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_loop(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_loop_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_loop_v(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_cel")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_cel(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_cel_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_cel_v(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_priority")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_priority(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "set_priority_v")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_set_priority_v(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "current_view")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            self.agi_currentview(a, b);
                        } else if (std.mem.eql(u8, statementFunc.name, "stop_sound")) {
                            self.agi_stop_sound();
                        } else if (std.mem.eql(u8, statementFunc.name, "show_pic")) {
                            self.agi_show_pic();
                        } else if (std.mem.eql(u8, statementFunc.name, "program_control")) {
                            self.agi_program_control();
                        } else if (std.mem.eql(u8, statementFunc.name, "player_control")) {
                            self.agi_player_control();
                        } else if (std.mem.eql(u8, statementFunc.name, "start_cycling")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_start_cycling(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "erase")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_erase(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "stop_cycling")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_stop_cycling(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "add_to_pic")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            const d = try volPartFbs.reader().readByte();
                            const e = try volPartFbs.reader().readByte();
                            const f = try volPartFbs.reader().readByte();
                            const g = try volPartFbs.reader().readByte();
                            self.agi_add_to_pic(a, b, c, d, e, f, g);
                        } else if (std.mem.eql(u8, statementFunc.name, "move_obj")) {
                            const a = try volPartFbs.reader().readByte();
                            const b = try volPartFbs.reader().readByte();
                            const c = try volPartFbs.reader().readByte();
                            const d = try volPartFbs.reader().readByte();
                            const e = try volPartFbs.reader().readByte();
                            self.agi_move_obj(a, b, c, d, e);
                        } else if (std.mem.eql(u8, statementFunc.name, "xxx")) {
                            // template.
                        } else {
                            const o = opCodeNR;
                            const n = statementFunc.name;
                            const a = statementFunc.arity;
                            const rdr = &volPartFbs;

                            const ignoreList = [_][]const u8{
                                "set_string",
                                "set_game_id",
                                "trace_info",
                                "set_text_attribute",
                                "set_menu",
                                "set_menu_member",
                                "submit_menu",
                                "set_cursor_char",
                                "script_size",
                                "configure_screen",
                                "disable_member",
                                "status_line_off",
                                "status_line_on",
                                "set_key",
                            };

                            // Anything here shall be ignored (with its respective args consumed);
                            try self.consume_skip_or_not_implemented(&ignoreList, rdr, o, n, a);
                        }
                        // Finally, special handling for new.room opcode.
                        if (opCodeNR == 0x12) {
                            self.vm_log("new.room opcode special handling (BREAKS)...", .{});
                            try volPartFbs.seekTo(0);
                            break;
                        }

                        std.log.info(">>>>>>>>> var[6] => {d}", .{self.read_var(6)});
                    }
                },
            }
        }
    }

    fn breakpoint(self: *VM) !void {
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
                try stdout.print("flag[{d}] => {s}\n", .{ flagIdx, self.flags[flagIdx] });
            } else {
                try stdout.print("??\n", .{});
            }

            try stdout.print("(C:c)ontinue, (Q:q)uit\n", .{});
            try stdout.print("> ", .{});
        }
    }

    fn consume_skip_or_not_implemented(self: *VM, list: []const []const u8, rdr: *std.io.FixedBufferStream([]const u8), opCodeNR: u8, ignoreName: []const u8, arity: i8) !void {
        // If eql, consume the args too and move on.
        for (list) |evalName| {
            if (std.mem.eql(u8, evalName, ignoreName)) {
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    _ = try rdr.reader().readByte();
                }

                self.vm_log("IGNOR-STMT: agi_{s}() with {d} args...", .{ ignoreName, arity });
                return;
            }
        }

        self.vm_log("NOT IMPLEMENTED: agi statement: {s}(<args>), opCode:{d}, (arg_count => {d})...", .{ ignoreName, opCodeNR, arity });
        self.vm_op_not_implemented(35);
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

    fn vm_log(self: *VM, comptime format: []const u8, args: anytype) void {
        if (self.debug) {
            std.log.debug(format, args);
        }
    }

    pub fn read_var(self: *VM, varNo: usize) u8 {
        // We intercept reads to the following declared switch to cope with intrinsic vars such as timers.
        // NOTE: should the values below get set, the VM will still do it...but not return the data since this is intercepted on read.
        if ((varNo > 0) and (varNo <= 29)) {
            switch (@intToEnum(cmds.VM_VARS, varNo)) {
                cmds.VM_VARS.SECONDS => return self.vmTimer.secs(),
                cmds.VM_VARS.MINUTES => return self.vmTimer.mins(),
                cmds.VM_VARS.HOURS => return self.vmTimer.hrs(),
                cmds.VM_VARS.DAYS => return self.vmTimer.days(),
                else => return self.vars[varNo],
            }
        }

        return self.vars[varNo];
    }

    // TODO: we should gate all reads and writes to better control vm state.
    // TODO: write_var
    //fn write_var(self: *VM, varNo: usize) void {}

    // TODO: read_flag
    // TODO: write_flag

    // AGI Test invocations.
    pub fn agi_test_equaln(self: *VM, varNo: usize, val: u8) bool {
        return self.read_var(varNo) == val;
    }

    pub fn agi_test_equalv(self: *VM, varNo1: usize, varNo2: usize) bool {
        return self.agi_test_equaln(varNo1, self.read_var(varNo2));
    }

    pub fn agi_test_greatern(self: *VM, varNo: usize, val: u8) bool {
        return self.read_var(varNo) > val;
    }

    pub fn agi_test_isset(self: *VM, flagNo: usize) bool {
        return self.flags[flagNo];
    }

    pub fn agi_test_controller(_: *VM, _: u8) bool {
        return false;
    }

    fn agi_test_have_key(self: *VM) bool {
        var hk = self.haveKey;
        self.haveKey = false;
        return hk;
    }

    fn agi_test_said(self: *VM, args: []const u16) bool {
        //self.vm_log("agi_test_said({any}) invoked...", .{args});
        self.vm_log("agi_test_said({any}) invoked...", .{args});
        return false;
    }

    // AGI Statement invocations.
    pub fn agi_new_room(self: *VM, roomNo: u8) void {
        self.vm_log("NEW_ROOM {d}", .{roomNo});
        self.newroom = roomNo;
    }

    pub fn agi_new_room_v(self: *VM, varNo: usize) void {
        agi_new_room(self.read_var(varNo));
    }

    pub fn agi_assignn(self: *VM, varNo: u8, num: u8) void {
        self.vars[varNo] = num;
        self.vm_log("agi_assignn({d}:varNo, {d}:num);", .{ varNo, num });
    }

    pub fn agi_assignv(self: *VM, varNo1: u8, varNo2: u8) void {
        self.agi_assignn(varNo1, self.read_var(varNo2));
        self.vm_log("agi_assignv({d}:varNo, {d}:num);", .{ varNo1, varNo2 });
    }

    pub fn agi_call(self: *VM, logicNo: u8) !void {
        self.vm_log("api_call({d})...", .{logicNo});

        self.vm_push_logic_stack(self.activeLogicNo);
        self.activeLogicNo = logicNo;

        // PSEUDO: if (LOGIC_ALREADY_LOADED):
        // INTERPRET IT.
        // else:
        // LOAD IT.
        // INTERPRET IT.
        // UNLOADED IT.

        // TEMP hack: for now just load it on demand.
        const dirIndex = self.logicIndex[logicNo];
        if (dirIndex.offset == 0) {
            self.vm_log("a NON-EXISTENT logic script was requested: {d}", .{logicNo});
            std.os.exit(9);
        }
        self.vm_log("vm_exec_logic @ logicNo:{d}, vol:{d}, offset:{d}", .{ logicNo, dirIndex.vol, dirIndex.offset });
        try self.vm_exec_logic(logicNo, dirIndex.vol, dirIndex.offset);

        //if (this.loadedLogics[logicNo] != null) {
        //    this.loadedLogics[logicNo].parseLogic();
        //} else {
        //    this.agi_load_logic(logicNo);
        //    this.loadedLogics[logicNo].parseLogic();
        //    this.loadedLogics[logicNo] = null;
        //}

        self.activeLogicNo = self.vm_pop_logic_stack();
    }

    pub fn agi_call_v(self: *VM, varNo: usize) !void {
        try self.agi_call(self.read_var(varNo));
    }

    pub fn agi_quit(self: *VM, statusCode: u8) void {
        self.vm_log("agi_quit({d}) exited..", .{statusCode});
        std.os.exit(statusCode);
    }

    pub fn agi_load_logic(self: *VM, logNo: usize) void {
        self.vm_log("agi_load_logic({s}, {d}", .{ self, logNo });
        //self.loadedLogics[logNo] = new LogicParser(this, logNo);
    }

    pub fn agi_load_logic_v(self: *VM, varNo: u8) void {
        self.agi_load_logic(self.read_var(varNo));
    }

    pub fn agi_increment(self: *VM, varNo: usize) void {
        if (self.read_var(varNo) < 255) {
            self.vars[varNo] += 1;
        }
        self.vm_log("increment({d}:varNo) invoked to val: {d}", .{ varNo, self.vars[varNo] });
    }

    pub fn agi_decrement(self: *VM, varNo: usize) void {
        if (self.read_var(varNo) > 0) {
            self.vars[varNo] -= 1;
        }
    }

    pub fn agi_set(self: *VM, flagNo: u8) void {
        self.flags[flagNo] = true;
        self.vm_log("agi_set(flagNo:{d});", .{flagNo});
    }

    pub fn agi_setv(self: *VM, varNo: u8) void {
        self.agi_set(self.read_var(varNo));
        self.vm_log("agi_set(varNo:{d});", .{varNo});
    }

    pub fn agi_reset(self: *VM, flagNo: u8) void {
        self.flags[flagNo] = false;
    }

    pub fn agi_reset_v(self: *VM, varNo: u8) void {
        self.agi_reset(self.read_var(varNo));
    }

    pub fn agi_addn(self: *VM, varNo: usize, num: u8) void {
        // may overflow...might need to do a wrapping %
        self.vars[varNo] += num;
    }

    pub fn agi_addv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_addn(varNo1, self.read_var(varNo2));
    }

    pub fn agi_subn(self: *VM, varNo: usize, num: u8) void {
        self.vars[varNo] -= num;
    }

    pub fn agi_subv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_subn(varNo1, self.read_var(varNo2));
    }

    pub fn agi_muln(self: *VM, varNo: usize, val: u8) void {
        self.vars[self.read_var(varNo)] *= val;
    }

    pub fn agi_mulv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_muln(varNo1, self.read_var(varNo2));
    }

    pub fn agi_divn(self: *VM, varNo: usize, val: u8) void {
        self.vars[self.read_var(varNo)] /= val;
    }

    pub fn agi_divv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_divn(varNo1, self.read_var(varNo2));
    }

    pub fn agi_force_update(self: *VM, objNum: u8) void {
        self.gameObjects[objNum].update = true;
        // this.agi_draw(objNo);
    }

    pub fn agi_clear_lines(self: *VM, a: u8, b: u8, c: u8) void {
        // for (var y = fromRow; y < row + 1; y++) {
        //         this.screen.bltText(y, 0, "                                        ");
        //     }
        self.vm_log("agi_clear_lines({d},{d},{d})", .{ a, b, c });
    }

    pub fn agi_prevent_input(self: *VM) void {
        self.allowInput = false;
    }

    pub fn agi_accept_input(self: *VM) void {
        self.allowInput = true;
    }

    pub fn agi_unanimate_all(self: *VM) void {
        var i: usize = 0;
        while (i < TOTAL_GAME_OBJS) : (i += 1) {
            self.gameObjects[i] = go.GameObject.init();
        }
    }

    fn agi_stop_update(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].update = false;
    }

    pub fn agi_animate_obj(self: *VM, objNo: u8) void {
        self.gameObjects[objNo] = go.GameObject.init();
        std.log.info("agi_animate_obj({d}) invoked", .{objNo});
    }

    pub fn agi_step_size(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].stepSize = self.read_var(varNo);
    }

    pub fn agi_step_time(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].stepTime = self.read_var(varNo);
    }

    pub fn agi_cycle_time(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].cycleTime = self.read_var(varNo);
        std.log.info("agi_cycle_time({d}:objNo, {d}:varNo) invoked", .{ objNo, self.read_var(varNo) });
    }

    pub fn agi_get_posn(self: *VM, objNo: u8, varNo1: u8, varNo2: u8) void {
        self.vars[varNo1] = self.gameObjects[objNo].x;
        self.vars[varNo2] = self.gameObjects[objNo].y;
        std.log.info("agi_get_posn({d}:objNo, {d}:varNo1, {d}:varNo2", .{ objNo, varNo1, varNo2 });
        //self.breakpoint() catch unreachable;
    }

    pub fn agi_observe_blocks(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].ignoreBlocks = false;
    }

    pub fn agi_observe_objs(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].ignoreObjs = false;
    }

    pub fn agi_ignore_objs(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].ignoreObjs = true;
    }

    pub fn agi_observe_horizon(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].ignoreHorizon = false;
    }

    pub fn agi_lindirectn(self: *VM, varNo: u8, val: u8) void {
        self.vars[self.read_var(varNo)] = val;
    }

    pub fn agi_set_view(self: *VM, objNo: u8, viewNo: u8) void {
        self.gameObjects[objNo].viewNo = viewNo;
        self.gameObjects[objNo].loop = 0;
        self.gameObjects[objNo].cel = 0;
        self.gameObjects[objNo].celCycling = true;
    }

    pub fn agi_set_view_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_view(objNo, self.read_var(varNo));
    }

    pub fn agi_load_view(self: *VM, viewNo: u8) anyerror!void {
        //self.loadedViews[viewNo] = new View(Resources.readAgiResource(Resources.AgiResource.View, viewNo));
        self.vm_log("agi_load_view({d}) invoked...(sampleTexture => {s})", .{ viewNo, sampleTexture });

        // TODO: since views are extracted as .png in the format of: 39_1_0.png. (view, loop, cell)
        // I need to load all .png files in the view set: 39_*_*.png and show the relevant one based on the animation loop/cycle.
        // Since all related files are now separate .png, one strategy is to just iterate with a loop and do a file exists check.

        const maxLoops = 15;
        const maxCels = 15;

        var loopIndex: usize = 0;
        var cellIndex: usize = 0;

        // Total file exists brute force approach...not the cleanest...but...good enough for now.
        while (loopIndex < maxLoops) : (loopIndex += 1) {
            while (cellIndex < maxCels) : (cellIndex += 1) {
                var tempString: [100]u8 = undefined;
                var fmtStr = try std.fmt.bufPrint(tempString[0..], "{s}{d}_{d}_{d}.png", .{ pathTextures, viewNo, loopIndex, cellIndex });

                const cstr = try allocator.dupeZ(u8, fmtStr);
                defer allocator.free(cstr);

                if (clib.FileExists(cstr)) {
                    _ = try self.resMan.add_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));
                    self.vm_log("located view file: {s}", .{fmtStr});

                    // Poor mans record of view/loop/cel entries, so we can easily query loop counts or cel counts per view.
                    self.viewDB[viewNo][@intCast(u8, loopIndex)] += 1;
                } else {
                    //std.log.info("view file NOT found: {s}", .{fmtStr});
                }
            }
            cellIndex = 0;
        }
    }

    fn vm_reset_viewDB(self: *VM) void {
        self.viewDB = std.mem.zeroes([1000][20]u8);
    }

    fn vm_view_loop_count(self: *VM, viewNo: usize) usize {
        var i: usize = 0;
        var counter: usize = 0;
        while (i < self.viewDB[viewNo].len) : (i += 1) {
            if (self.viewDB[viewNo][i] > 0) {
                counter += 1;
            }
        }
        return counter;
    }

    fn vm_view_loop_cel_count(self: *VM, viewNo: usize, loopNo: usize) usize {
        return self.viewDB[viewNo][loopNo];
    }

    pub fn agi_load_view_v(self: *VM, varNo: u8) anyerror!void {
        try self.agi_load_view(self.read_var(varNo));
    }

    fn agi_block(self: *VM, x1: u8, y1: u8, x2: u8, y2: u8) void {
        self.blockX1 = x1;
        self.blockY1 = y1;
        self.blockX2 = x2;
        self.blockY2 = y2;
    }

    fn agi_unblock(self: *VM) void {
        self.blockX1 = 0;
        self.blockY1 = 0;
        self.blockX2 = 0;
        self.blockY2 = 0;
    }

    pub fn agi_set_horizon(self: *VM, y: u8) void {
        self.horizon = y;
    }

    pub fn agi_load_sound(self: *VM, soundNo: u8) void {
        self.vm_log("agi_load_sound({d}) invoked...", .{soundNo});
    }

    pub fn agi_sound(self: *VM, soundNo: u8, flagNo: u8) void {
        self.vm_log("agi_sound({d}, {d}) invoked...", .{ soundNo, flagNo });
    }

    pub fn agi_stop_sound(self: *VM) void {
        self.vm_log("agi_stop_sound() invoked...", .{});
    }

    pub fn agi_load_pic(self: *VM, varNo: u8) void {
        const picNo = self.read_var(varNo);
        self.vm_log("agi_load_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        // this.loadedPics[picNo] = new Pic(Resources.readAgiResource(Resources.AgiResource.Pic, picNo));
    }

    pub fn agi_draw_pic(self: *VM, varNo: u8) void {
        // this.visualBuffer.clear(0x0F);
        // this.priorityBuffer.clear(0x04);
        self.agi_overlay_pic(varNo);
        self.vm_log("agi_draw_pic({d})", .{varNo});
    }

    pub fn agi_draw(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].draw = true;
    }

    pub fn agi_overlay_pic(self: *VM, varNo: u8) void {
        const picNo = self.read_var(varNo);
        self.vm_log("agi_overlay_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        //this.loadedPics[picNo].draw(this.visualBuffer, this.priorityBuffer);
    }

    pub fn agi_discard_pic(self: *VM, varNo: u8) void {
        const picNo = self.read_var(varNo);
        self.vm_log("agi_discard_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        //this.loadedPics[picNo] = null;
    }

    pub fn agi_add_to_pic(self: *VM, viewNo: u8, loopNo: u8, celNo: u8, x: u8, y: u8, priority: u8, margin: u8) void {
        // TODO: Add margin
        //this.screen.bltView(viewNo, loopNo, celNo, x, y, priority);
        self.vm_log("agi_add_to_pic({d},{d},{d},{d},{d},{d},{d})", .{ viewNo, loopNo, celNo, x, y, priority, margin });
    }

    pub fn agi_add_to_pic_v(self: *VM, varNo1: u8, varNo2: u8, varNo3: u8, varNo4: u8, varNo5: u8, varNo6: u8, varNo7: u8) void {
        self.agi_add_to_pic(self.read_var(varNo1), self.read_var(varNo2), self.read_var(varNo3), self.read_var(varNo4), self.read_var(varNo5), self.read_var(varNo6), self.read_var(varNo7));
    }

    pub fn agi_show_pic(self: *VM) void {
        self.vm_log("agi_show_pic()", .{});
        // this.screen.bltPic();
        // this.gameObjects.forEach(obj => {
        //     obj.redraw = true;
        // });
    }

    pub fn agi_set_loop(self: *VM, objNo: u8, loopNo: u8) void {
        self.gameObjects[objNo].loop = loopNo;
    }

    pub fn agi_set_loop_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_loop(objNo, self.read_var(varNo));
    }

    pub fn agi_position(self: *VM, objNo: u8, x: u8, y: u8) void {
        self.gameObjects[objNo].x = x;
        self.gameObjects[objNo].y = y;
    }

    pub fn agi_position_v(self: *VM, objNo: u8, varNo1: u8, varNo2: u8) void {
        self.agi_position(objNo, self.read_var(varNo1), self.read_var(varNo2));
    }

    fn agi_set_dir(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].direction = self.read_var(varNo);
    }

    fn agi_get_dir(self: *VM, objNo: u8, varNo: u8) void {
        self.vars[varNo] = self.gameObjects[objNo].direction;
    }

    pub fn agi_set_cel(self: *VM, objNo: u8, celNo: u8) void {
        self.gameObjects[objNo].nextCycle = 1;
        self.gameObjects[objNo].cel = celNo;
    }

    pub fn agi_set_cel_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_cel(objNo, self.read_var(varNo));
    }

    pub fn agi_set_priority(self: *VM, objNo: u8, priority: u8) void {
        self.gameObjects[objNo].priority = priority;
        self.gameObjects[objNo].fixedPriority = true;
    }

    pub fn agi_set_priority_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_priority(objNo, self.read_var(varNo));
    }

    pub fn agi_stop_cycling(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].celCycling = false;
        std.log.info("stop_cycling({d}:objNo)...", .{objNo});
    }

    pub fn agi_start_cycling(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].celCycling = true;
        std.log.info("start_cycling({d}:objNo)...", .{objNo});
    }

    pub fn agi_normal_cycle(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].reverseCycle = false;
    }

    pub fn agi_normal_motion(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].motion = true;
    }

    pub fn agi_currentview(self: *VM, objNo: u8, varNo: u8) void {
        self.vars[varNo] = self.gameObjects[objNo].viewNo;
    }

    fn agi_program_control(self: *VM) void {
        self.programControl = true;
        std.log.info("agi_programControl({s}", .{true});
    }

    fn agi_player_control(self: *VM) void {
        self.programControl = false;
    }

    fn agi_move_obj(self: *VM, objNo: u8, x: u8, y: u8, stepSpeed: u8, flagNo: u8) void {
        self.gameObjects[objNo].moveToX = x;
        self.gameObjects[objNo].moveToY = y;
        self.gameObjects[objNo].moveToStep = stepSpeed;
        self.gameObjects[objNo].movementFlag = go.MovementFlags.MoveTo;
        self.gameObjects[objNo].flagToSetWhenFinished = flagNo;
    }

    fn agi_display(self: *VM, row: u8, col: u8, msg: u8) void {
        self.vm_log("agi_display({d}:row, {d}:col, {d}:msg) invoked...", .{ row, col, msg });
        //this.screen.bltText(row, col, this.loadedLogics[this.logicNo].logic.messages[msg]);
    }

    fn agi_display_v(self: *VM, varNo1: u8, varNo2: u8, varNo3: u8) void {
        self.agi_display(self.read_var(varNo1), self.read_var(varNo2), self.read_var(varNo3));
    }

    fn agi_fix_loop(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].fixedLoop = true;
    }

    fn agi_release_loop(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].fixedLoop = false;
    }

    fn agi_erase(self: *VM, objNo: u8) void {
        var obj = &self.gameObjects[objNo];
        obj.draw = false;
        obj.loop = 0;
        obj.cel = 0;
        //this.screen.clearView(obj.oldView, obj.oldLoop, obj.oldCel, obj.oldDrawX, obj.oldDrawY, obj.oldPriority);
    }

    fn agi_reposition_to(self: *VM, objNo: u8, x: u8, y: u8) void {
        //var obj: GameObject = this.gameObjects[objNo]; (this line is uneeded but in the agi.js implementation)
        self.agi_position(objNo, x, y);
    }

    fn agi_reposition_to_v(self: *VM, objNo: u8, varNo1: u8, varNo2: u8) void {
        self.agi_reposition_to(objNo, self.read_var(varNo1), self.read_var(varNo2));
    }

    fn agi_follow_ego(self: *VM, objNo: u8, stepSpeed: u8, flagNo: u8) void {
        var obj = &self.gameObjects[objNo];
        obj.moveToStep = stepSpeed;
        obj.flagToSetWhenFinished = flagNo;
        obj.movementFlag = go.MovementFlags.ChaseEgo;
    }

    fn agi_wander(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].movementFlag = go.MovementFlags.Wander;
        self.gameObjects[objNo].direction = 5; // TODO: this.randomBetween(1, 9);

        if (objNo == 0) {
            self.vars[6] = self.gameObjects[objNo].direction;
            self.agi_program_control();
        }
    }
};
