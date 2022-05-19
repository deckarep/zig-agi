const std = @import("std");
const ArrayList = std.ArrayList;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const allocator = arena.allocator();

const prompt = @import("prompt.zig");
const go = @import("game_object.zig");
const cmds = @import("agi_cmds.zig");
const stmts = @import("agi_statements.zig");
const hlp = @import("raylib_helpers.zig");

const clib = @import("c_defs.zig").c;
const timer = @import("sys_timers.zig");
const rm = @import("resource_manager.zig");

const aw = @import("args.zig");

const pathTextures = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/extracted/view/";
pub const sampleTexture = pathTextures ++ "43_0_0.png";

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

pub const TOTAL_GAME_OBJS: usize = 16; // also called screen objs.

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

        self.write_var(0, 0);
        self.write_var(26, 3); // EGA
        self.write_var(8, 255); // Pages of free memory
        self.write_var(23, 15); // Sound volume
        self.write_var(24, 41); // Input buffer size
        self.set_flag(9, true); // Sound enabled
        self.set_flag(11, true); // Logic 0 executed for the first time
        self.set_flag(5, true); // Room script executed for the first time

        try stmts.agi_unanimate_all(self);
        //self.agi_load_logic(0);
    }

    pub fn deinit(self: *VM) void {
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
        self.write_var(6, if (egoDir == newEgoDir) 0 else newEgoDir);
    }

    pub fn vm_cycle(self: *VM) !void {
        self.set_flag(2, false); // The player has entered a command
        self.set_flag(4, false); // said accepted user input

        var egoObj = &self.gameObjects[0];

        var egoDir = self.read_var(6);
        // NOTE: re: self.programControl in other implementations (scummvm, nagi) the boolean flag tracked is playerControl so it's OPPOSITE!!!!
        if (self.programControl) {
            self.write_var(6, @enumToInt(egoObj.direction));
            //egoDir = self.read_var(6);
        } else {
            //egoObj.direction = @intToEnum(go.Direction, egoDir);
            egoObj.direction = @intToEnum(go.Direction, egoDir);
            //self.write_var(6, egoDir);
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
            self.set_flag(11, false); // Logic 0 executed for the first time.

            // TODO: figure out what these are supposed to represent.
            self.write_var(@enumToInt(cmds.VM_VARS.BORDER_TOUCH_OBJECT), 0);
            self.write_var(@enumToInt(cmds.VM_VARS.BORDER_CODE), 0);
            self.set_flag(5, false);
            self.set_flag(6, false);
            self.set_flag(12, false);

            var i: usize = 0;
            while (i < self.gameObjects.len) : (i += 1) {
                var obj = &self.gameObjects[(self.gameObjects.len - 1) - i];
                if (obj.update) {
                    if (i == 0) {
                        obj.direction = @intToEnum(go.Direction, egoDir);
                    }
                    try self.vm_updateObject(i, obj);
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

                self.write_var(1, self.read_var(0));
                self.write_var(0, self.newroom);
                self.write_var(4, 0);
                self.write_var(5, 0);
                self.write_var(9, 0);
                self.write_var(16, self.gameObjects[0].viewNo);

                switch (self.read_var(2)) {
                    // 0 => Touched nothing
                    // Top edge or horizon
                    1 => self.gameObjects[0].y = 168,
                    2 => self.gameObjects[0].x = 1,
                    3 => self.gameObjects[0].y = self.horizon,
                    4 => self.gameObjects[0].x = 160,
                    else => {},
                }

                self.write_var(2, 0);
                self.set_flag(2, false);

                //this.agi_load_logic_v(0);
                self.set_flag(5, true);
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
                        self.write_var(2, 4);
                    } else {
                        self.write_var(4, @intCast(u8, idx));
                        self.write_var(5, 4);
                    }
                } else if (obj.x + try self.vm_cel_width(obj.viewNo, obj.loop, obj.cel) >= 160) {
                    if (idx == 0) {
                        self.write_var(2, 2);
                    } else {
                        self.write_var(4, @intCast(u8, idx));
                        self.write_var(5, 2);
                    }
                } else if (!obj.ignoreHorizon and obj.y <= self.horizon) {
                    if (idx == 0) {
                        self.write_var(2, 1);
                    } else {
                        self.write_var(4, @intCast(u8, idx));
                        self.write_var(5, 1);
                    }
                } else if (obj.y >= 168) {
                    if (idx == 0) {
                        self.write_var(2, 3);
                    } else {
                        self.write_var(4, @intCast(u8, idx));
                        self.write_var(5, 3);
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
            // 1. need to draw the correct sizing/x,y placement for higher resolution assets (factor of 4 times bigger)
            // 2. still need to handle mirror states somehow.

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

                            self.vm_log("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, predicateFunc.name, predicateFunc.arity });

                            // buf for statement args, which gets sliced as needed.
                            var buf: [30]u8 = undefined;
                            var myArgs = &aw.Args.init(&buf);

                            if (opCodeNR == 0x0E) { //Said (uses variable num of 16-bit args, within bytecode!)
                                const saidArgLen = try volPartFbs.reader().readByte();

                                // Times 2 because said requires 16-bit args so we need to consume double the amount.
                                const actualArgLen = saidArgLen * 2;
                                predicateCallResult = try predicateFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, actualArgLen)));
                            } else {
                                predicateCallResult = try predicateFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, predicateFunc.arity)));
                            }

                            if (invertMode) {
                                predicateCallResult = !predicateCallResult;
                                invertMode = false;
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

                        errdefer std.log.warn("statement UNIMPLEMENTED: \"{s}\"", .{statementFunc.name});
                        try statementFunc.func(self, try myArgs.eat(&volPartFbs, @intCast(usize, statementFunc.arity)));

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
                cmds.VM_VARS.SECONDS => return self.vmTimer.secs(),
                cmds.VM_VARS.MINUTES => return self.vmTimer.mins(),
                cmds.VM_VARS.HOURS => return self.vmTimer.hrs(),
                cmds.VM_VARS.DAYS => return self.vmTimer.days(),
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

    // TODO: we should gate all reads and writes to better control vm state.
    // TODO: write_var
    //fn write_var(self: *VM, varNo: usize) void {}

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
