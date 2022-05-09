const std = @import("std");
const ArrayList = std.ArrayList;

const go = @import("game_object.zig");
const cmds = @import("agi_cmds.zig");
const hlp = @import("raylib_helpers.zig");

const clib = @import("c_defs.zig").c;

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
const VMError = error{
    EndOfStream,
    OutOfMemory,
};

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

pub const VM = struct {
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

    logicIndex: [DIR_INDEX_SIZE]DirectoryIndex,
    picIndex: [DIR_INDEX_SIZE]DirectoryIndex,
    viewIndex: [DIR_INDEX_SIZE]DirectoryIndex,

    // init creates a new instance of an AGI VM.
    pub fn init() VM {
        var myVM = VM{ .logicIndex = undefined, .picIndex = undefined, .viewIndex = undefined, .logicStack = std.mem.zeroes([LOGIC_STACK_SIZE]u8), .logicStackPtr = 0, .activeLogicNo = 0, .newroom = 0, .horizon = 0, .allowInput = false, .haveKey = false, .programControl = false, .vars = std.mem.zeroes([TOTAL_VARS]u8), .flags = std.mem.zeroes([TOTAL_FLAGS]bool), .gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject) };
        return myVM;
    }

    pub fn vm_bootstrap(self: *VM) !void {
        // Seed directory index data, not worried about sound DIR for now.
        self.logicIndex = try buildDirIndex(logDirFile);
        self.picIndex = try buildDirIndex(picDirFile);
        self.viewIndex = try buildDirIndex(viewDirFile);
    }

    pub fn vm_start(self: *VM) void {
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

    pub fn vm_reset(self: *VM) void {
        std.log.info("reset_vm invoked with: {s}", .{self});
    }

    pub fn vm_cycle(self: *VM) !void {
        self.flags[2] = false; // The player has entered a command
        self.flags[4] = false; // said accepted user input

        while (true) {
            try self.agi_call(0);
            self.flags[11] = false; // Logic 0 executed for the first time.

            // TODO: figure out what these are supposed to represent.
            //this.gameObjects[0].direction = this.variables[6];
            self.vars[5] = 0;
            self.vars[4] = 0;
            self.flags[5] = false;
            self.flags[6] = false;
            self.flags[12] = false;

            // for (var j = 0; j < this.gameObjects.length; j++) {
            //     var obj = this.gameObjects[j];
            //     if (obj.update) {
            //         if (j == 0)
            //             obj.direction = egoDir;
            //         //else
            //         //    obj.updateDirection(this);
            //         this.updateObject(obj, j);
            //     }
            // }

            if (self.newroom != 0) {
                // need to start handling this logic next, since new room is changed.
                //self.agi_stop_update(0);
                self.agi_unanimate_all();
                // RC: Not sure what to do with this line.
                //self.loadedLogics = self.loadedLogics.slice(0, 1);
                //self.agi_player_control();
                //self.agi_unblock();
                self.agi_set_horizon(36);

                self.vars[1] = self.vars[0];
                self.vars[0] = self.newroom;
                self.vars[4] = 0;
                self.vars[5] = 0;
                self.vars[9] = 0;
                self.vars[16] = self.gameObjects[0].viewNo;

                // switch (this.variables[2]) {
                //     case 0: // Touched nothing
                //         break;
                //     case 1: // Top edge or horizon
                //         this.gameObjects[0].y = 168;
                //         break;
                //     case 2:
                //         this.gameObjects[0].x = 1;
                //         break;
                //     case 3:
                //         this.gameObjects[0].y = this.horizon;
                //         break;
                //     case 4:
                //         this.gameObjects[0].x = 160;
                //         break;
                //     default:
                // }

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

    pub fn vm_exec_logic(self: *VM, idx: usize, vol: usize, offset: u32) VMError!void {
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

        std.log.info("idx => {d}, sig => {d}, vol/volNo => {d}/{d}, resLength => {d}", .{ idx, sig, vol, volNo, resLength });

        const newStartOffset = offset + 5;
        const newEndOffset = newStartOffset + resLength;

        // Parse volume part.
        // std.log.info("[{d}..{d}] - max size: {d}", .{ newStartOffset, newEndOffset, fbs.getEndPos() });
        var volPartFbs = switch (volNo) {
            0 => std.io.fixedBufferStream(vol0[newStartOffset..newEndOffset]),
            1 => std.io.fixedBufferStream(vol1[newStartOffset..newEndOffset]),
            2 => std.io.fixedBufferStream(vol2[newStartOffset..newEndOffset]),
            else => unreachable,
        };

        // Parse message strings first.

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
            std.log.info("activeLogicNo => {d}", .{self.activeLogicNo});
            // TODO: (DELETE ME) Safety to prevent runaway..
            if (maxIters > 1200) {
                std.log.info("max iterations MET!!!", .{});
                std.os.exit(9);
            }
            maxIters += 1;

            const opCodeNR = volPartFbs.reader().readByte() catch |e| {
                switch (e) {
                    error.EndOfStream => {
                        std.log.info("end of logic script({d}) encountered so BREAKing...", .{idx});
                        break;
                    },
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
                            if ((opCodeNR - 1) >= cmds.agi_tests.len) {
                                std.log.info("FATAL: trying to fetch a test from index: {d}", .{opCodeNR - 1});
                                return;
                            }
                            const testFunc = cmds.agi_tests[opCodeNR - 1];
                            var testCallResult = false;

                            std.log.info("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, testFunc.name, testFunc.arity });
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
                                    std.log.info("test_greatern({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "isset")) {
                                    const a = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_isset(a);
                                    std.log.info("isset({d})", .{a});
                                } else if (std.mem.eql(u8, testFunc.name, "controller")) {
                                    const a = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_controller(a);
                                    std.log.info("test_controller({d})", .{a});
                                } else if (std.mem.eql(u8, testFunc.name, "equaln")) {
                                    const a = try volPartFbs.reader().readByte();
                                    const b = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_equaln(a, b);
                                    std.log.info("test_equaln({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "equalv")) {
                                    const a = try volPartFbs.reader().readByte();
                                    const b = try volPartFbs.reader().readByte();
                                    testCallResult = self.agi_test_equalv(a, b);
                                    std.log.info("test_equalv({d}, {d})", .{ a, b });
                                } else if (std.mem.eql(u8, testFunc.name, "have_key")) {
                                    testCallResult = self.agi_test_have_key();
                                    std.log.info("agi_test_have_key()", .{});
                                } else {
                                    std.log.info("test op:{d}(0x{X:0>2}) not handled!", .{ opCodeNR - 1, opCodeNR - 1 });
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
                            self.agi_load_view_v(a);
                        } else if (std.mem.eql(u8, statementFunc.name, "load_view")) {
                            const a = try volPartFbs.reader().readByte();
                            self.agi_load_view(a);
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
                            std.log.info("new.room opcode special handling (BREAKS)...", .{});
                            try volPartFbs.seekTo(0);
                            break;
                        }
                    }
                },
            }
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

                std.log.info("IGNOR-STMT: agi_{s}() with {d} args...", .{ ignoreName, arity });
                return;
            }
        }

        std.log.info("NOT IMPLEMENTED: agi statement: {s}(<args>), opCode:{d}, (arg_count => {d})...", .{ ignoreName, opCodeNR, arity });
        self.vm_op_not_implemented(35);
    }

    pub fn vm_push_logic_stack(self: *VM, logicNo: u8) void {
        if (self.logicStackPtr == LOGIC_STACK_SIZE - 1) {
            std.os.exit(9);
            std.log.info("OH NO: stack over flow beyatch!", .{});
        }
        self.logicStack[self.logicStackPtr] = logicNo;
        self.logicStackPtr += 1;
    }

    pub fn vm_pop_logic_stack(self: *VM) u8 {
        if (self.logicStackPtr == 0) {
            std.log.info("OH NO: stack under flow beyatch!", .{});
            std.os.exit(9);
        }

        const logicNo = self.logicStack[self.logicStackPtr];
        self.logicStackPtr -= 1;
        return logicNo;
    }

    pub fn vm_op_not_implemented(_: *VM, statusCode: u8) void {
        std.log.info("vm_op_not_implemented({d}) exited...", .{statusCode});
        std.os.exit(statusCode);
    }

    // AGI Test invocations.
    pub fn agi_test_equaln(self: *VM, varNo: usize, val: u8) bool {
        return self.vars[varNo] == val;
    }

    pub fn agi_test_equalv(self: *VM, varNo1: usize, varNo2: usize) bool {
        return self.agi_test_equaln(varNo1, self.vars[varNo2]);
    }

    pub fn agi_test_greatern(self: *VM, varNo: usize, val: u8) bool {
        return self.vars[varNo] > val;
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

    fn agi_test_said(_: *VM, args: []const u16) bool {
        std.log.info("agi_test_said({any}) invoked...", .{args});
        return false;
    }

    // AGI Statement invocations.
    pub fn agi_new_room(self: *VM, roomNo: u8) void {
        std.log.info("NEW_ROOM {d}", .{roomNo});
        self.newroom = roomNo;
    }

    pub fn agi_new_room_v(self: *VM, varNo: usize) void {
        agi_new_room(self.vars[varNo]);
    }

    pub fn agi_assignn(self: *VM, varNo: u8, num: u8) void {
        self.vars[varNo] = num;
        std.log.info("agi_assignn({d}:varNo, {d}:num);", .{ varNo, num });
    }

    pub fn agi_assignv(self: *VM, varNo1: u8, varNo2: u8) void {
        self.agi_assignn(varNo1, self.vars[varNo2]);
        std.log.info("agi_assignv({d}:varNo, {d}:num);", .{ varNo1, varNo2 });
    }

    pub fn agi_call(self: *VM, logicNo: u8) !void {
        std.log.info("api_call({d})...", .{logicNo});

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
            std.log.info("a NON-EXISTENT logic script was requested: {d}", .{logicNo});
            std.os.exit(9);
        }
        std.log.info("vm_exec_logic @ logicNo:{d}, vol:{d}, offset:{d}", .{ logicNo, dirIndex.vol, dirIndex.offset });
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
        try self.agi_call(self.vars[varNo]);
    }

    pub fn agi_quit(_: *VM, statusCode: u8) void {
        std.log.info("agi_quit({d}) exited..", .{statusCode});
        std.os.exit(statusCode);
    }

    pub fn agi_load_logic(self: *VM, logNo: usize) void {
        std.log.info("agi_load_logic({s}, {d}", .{ self, logNo });
        //self.loadedLogics[logNo] = new LogicParser(this, logNo);
    }

    pub fn agi_load_logic_v(self: *VM, varNo: u8) void {
        self.agi_load_logic(self.vars[varNo]);
    }

    pub fn agi_increment(self: *VM, varNo: usize) void {
        if (self.vars[varNo] < 255) {
            self.vars[varNo] += 1;
        }
        std.log.info("increment({d}:varNo) invoked to val: {d}", .{ varNo, self.vars[varNo] });
    }

    pub fn agi_decrement(self: *VM, varNo: usize) void {
        if (self.vars[varNo] > 0) {
            self.vars[varNo] -= 1;
        }
    }

    pub fn agi_set(self: *VM, flagNo: u8) void {
        self.flags[flagNo] = true;
        std.log.info("agi_set(flagNo:{d});", .{flagNo});
    }

    pub fn agi_setv(self: *VM, varNo: u8) void {
        self.agi_set(self.vars[varNo]);
        std.log.info("agi_set(varNo:{d});", .{varNo});
    }

    pub fn agi_reset(self: *VM, flagNo: u8) void {
        self.flags[flagNo] = false;
    }

    pub fn agi_reset_v(self: *VM, varNo: u8) void {
        self.agi_reset(self.vars[varNo]);
    }

    pub fn agi_addn(self: *VM, varNo: usize, num: u8) void {
        self.vars[varNo] += num;
    }

    pub fn agi_addv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_addn(varNo1, self.vars[varNo2]);
    }

    pub fn agi_subn(self: *VM, varNo: usize, num: u8) void {
        self.vars[varNo] -= num;
    }

    pub fn agi_subv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_subn(varNo1, self.vars[varNo2]);
    }

    pub fn agi_muln(self: *VM, varNo: usize, val: u8) void {
        self.vars[self.vars[varNo]] *= val;
    }

    pub fn agi_mulv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_muln(varNo1, self.vars[varNo2]);
    }

    pub fn agi_divn(self: *VM, varNo: usize, val: u8) void {
        self.vars[self.vars[varNo]] /= val;
    }

    pub fn agi_divv(self: *VM, varNo1: usize, varNo2: usize) void {
        agi_divn(varNo1, self.vars[varNo2]);
    }

    pub fn agi_force_update(self: *VM, objNum: u8) void {
        self.gameObjects[objNum].update = true;
        // this.agi_draw(objNo);
    }

    pub fn agi_clear_lines(_: *VM, a: u8, b: u8, c: u8) void {
        // for (var y = fromRow; y < row + 1; y++) {
        //         this.screen.bltText(y, 0, "                                        ");
        //     }
        std.log.info("agi_clear_lines({d},{d},{d})", .{ a, b, c });
    }

    pub fn agi_prevent_input(self: *VM) void {
        self.allowInput = false;
    }

    pub fn agi_accept_input(self: *VM) void {
        self.allowInput = true;
    }

    pub fn agi_unanimate_all(self: *VM) void {
        self.gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject);
    }

    pub fn agi_animate_obj(_: *VM, objNo: u8) void {
        //self.gameObjects[objNo] = new GameObject();
        std.log.info("agi_animate_obj({d}) invoked", .{objNo});
    }

    pub fn agi_step_size(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].stepSize = self.vars[varNo];
    }

    pub fn agi_step_time(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].stepTime = self.vars[varNo];
    }

    pub fn agi_cycle_time(self: *VM, objNo: u8, varNo: u8) void {
        self.gameObjects[objNo].cycleTime = self.vars[varNo];
    }

    pub fn agi_get_posn(self: *VM, objNo: u8, varNo1: u8, varNo2: u8) void {
        self.vars[varNo1] = self.gameObjects[objNo].x;
        self.vars[varNo2] = self.gameObjects[objNo].y;
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
        self.vars[self.vars[varNo]] = val;
    }

    pub fn agi_set_view(self: *VM, objNo: u8, viewNo: u8) void {
        self.gameObjects[objNo].viewNo = viewNo;
        self.gameObjects[objNo].loop = 0;
        self.gameObjects[objNo].cel = 0;
        self.gameObjects[objNo].celCycling = true;
    }

    pub fn agi_set_view_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_view(objNo, self.vars[varNo]);
    }

    pub fn agi_load_view(_: *VM, viewNo: u8) void {
        //self.loadedViews[viewNo] = new View(Resources.readAgiResource(Resources.AgiResource.View, viewNo));
        std.log.info("agi_load_view({d}) invoked...", .{viewNo});

        // TODO: since views are extracted as .png in the format of: 39_1_0.png.
        // I need to load all .png files in the view set: 39_*_*.png and show the relevant one based on the animation loop/cycle.
    }

    pub fn agi_load_view_v(self: *VM, varNo: u8) void {
        self.agi_load_view(self.vars[varNo]);
    }

    pub fn agi_set_horizon(self: *VM, y: u8) void {
        self.horizon = y;
    }

    pub fn agi_load_sound(_: *VM, soundNo: u8) void {
        std.log.info("agi_load_sound({d}) invoked...", .{soundNo});
    }

    pub fn agi_sound(_: *VM, soundNo: u8, flagNo: u8) void {
        std.log.info("agi_sound({d}, {d}) invoked...", .{ soundNo, flagNo });
    }

    pub fn agi_stop_sound(_: *VM) void {
        std.log.info("agi_stop_sound() invoked...", .{});
    }

    pub fn agi_load_pic(self: *VM, varNo: u8) void {
        const picNo = self.vars[varNo];
        std.log.info("agi_load_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        // this.loadedPics[picNo] = new Pic(Resources.readAgiResource(Resources.AgiResource.Pic, picNo));
    }

    pub fn agi_draw_pic(self: *VM, varNo: u8) void {
        // this.visualBuffer.clear(0x0F);
        // this.priorityBuffer.clear(0x04);
        self.agi_overlay_pic(varNo);
        std.log.info("agi_draw_pic({d})", .{varNo});
    }

    pub fn agi_overlay_pic(self: *VM, varNo: u8) void {
        const picNo = self.vars[varNo];
        std.log.info("agi_overlay_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        //this.loadedPics[picNo].draw(this.visualBuffer, this.priorityBuffer);
    }

    pub fn agi_discard_pic(self: *VM, varNo: u8) void {
        const picNo = self.vars[varNo];
        std.log.info("agi_discard_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
        //this.loadedPics[picNo] = null;
    }

    pub fn agi_add_to_pic(_: *VM, viewNo: u8, loopNo: u8, celNo: u8, x: u8, y: u8, priority: u8, margin: u8) void {
        // TODO: Add margin
        //this.screen.bltView(viewNo, loopNo, celNo, x, y, priority);
        std.log.info("agi_add_to_pic({d},{d},{d},{d},{d},{d},{d})", .{ viewNo, loopNo, celNo, x, y, priority, margin });
    }

    pub fn agi_add_to_pic_v(self: *VM, varNo1: u8, varNo2: u8, varNo3: u8, varNo4: u8, varNo5: u8, varNo6: u8, varNo7: u8) void {
        self.agi_add_to_pic(self.vars[varNo1], self.vars[varNo2], self.vars[varNo3], self.vars[varNo4], self.vars[varNo5], self.vars[varNo6], self.vars[varNo7]);
    }

    pub fn agi_show_pic(_: *VM) void {
        std.log.info("agi_show_pic()", .{});
        // this.screen.bltPic();
        // this.gameObjects.forEach(obj => {
        //     obj.redraw = true;
        // });
    }

    pub fn agi_set_loop(self: *VM, objNo: u8, loopNo: u8) void {
        self.gameObjects[objNo].loop = loopNo;
    }

    pub fn agi_set_loop_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_loop(objNo, self.vars[varNo]);
    }

    pub fn agi_position(self: *VM, objNo: u8, x: u8, y: u8) void {
        self.gameObjects[objNo].x = x;
        self.gameObjects[objNo].y = y;
    }

    pub fn agi_position_v(self: *VM, objNo: u8, varNo1: u8, varNo2: u8) void {
        self.agi_position(objNo, self.vars[varNo1], self.vars[varNo2]);
    }

    pub fn agi_set_cel(self: *VM, objNo: u8, celNo: u8) void {
        self.gameObjects[objNo].nextCycle = 1;
        self.gameObjects[objNo].cel = celNo;
    }

    pub fn agi_set_cel_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_cel(objNo, self.vars[varNo]);
    }

    pub fn agi_set_priority(self: *VM, objNo: u8, priority: u8) void {
        self.gameObjects[objNo].priority = priority;
        self.gameObjects[objNo].fixedPriority = true;
    }

    pub fn agi_set_priority_v(self: *VM, objNo: u8, varNo: u8) void {
        self.agi_set_priority(objNo, self.vars[varNo]);
    }

    pub fn agi_stop_cycling(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].celCycling = false;
    }

    pub fn agi_start_cycling(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].celCycling = true;
    }

    pub fn agi_normal_cycle(self: *VM, objNo: u8) void {
        self.gameObjects[objNo].reverseCycle = false;
    }

    pub fn agi_currentview(self: *VM, objNo: u8, varNo: u8) void {
        self.vars[varNo] = self.gameObjects[objNo].viewNo;
    }

    fn agi_program_control(self: *VM) void {
        self.programControl = true;
    }

    fn agi_player_control(self: *VM) void {
        self.programControl = false;
    }
};
