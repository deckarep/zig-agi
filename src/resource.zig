const std = @import("std");
const ArrayList = std.ArrayList;
const cmds = @import("agi_cmds.zig");

// HACK zone, just doing a quick and dirty comptime embed file.
const rootPath = "/Users/deckarep/Desktop/ralph-agi/test-agi-game/";
const logDirFile = @embedFile(rootPath ++ "LOGDIR");
const picDirFile = @embedFile(rootPath ++ "PICDIR");
const viewDirFile = @embedFile(rootPath ++ "VIEWDIR");
const sndDirFile = @embedFile(rootPath ++ "SNDDIR");
const vol0 = @embedFile(rootPath ++ "VOL.0");
const vol1 = @embedFile(rootPath ++ "VOL.1");
const vol2 = @embedFile(rootPath ++ "VOL.2");

const messageDecryptKey = "Avis Durgan";

var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

pub fn buildDirIndex(dirFile: []const u8) !void {
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

            std.log.info("idx => {d}, volNo => {d}, volOffset => {d}", .{ i, vol, offset });
            //try loadLogic(i, vol, offset);

            // NOTE: JUST DO ONE THING.
            //return;
        }
    }
}

// https://wiki.scummvm.org/index.php?title=AGI/Specifications/Resources#LogicFormat
// fn loadLogic(idx: usize, vol: usize, offset: u32) !void {
//     var fbs = switch (vol) {
//         0 => std.io.fixedBufferStream(vol0),
//         1 => std.io.fixedBufferStream(vol1),
//         2 => std.io.fixedBufferStream(vol2),
//         else => unreachable,
//     };

//     try fbs.seekTo(offset);

//     // PARSE HEADER.

//     // Arbitrary endian-ness...FU Sierra.
//     // Signature is always: 0x1234. (Big End..)
//     const sig: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Big);
//     const volNo: u8 = try fbs.reader().readByte();
//     // Lil End..
//     const resLength: u16 = try fbs.reader().readInt(u16, std.builtin.Endian.Little);

//     std.log.info("idx => {d}, sig => {d}, vol/volNo => {d}/{d}, resLength => {d}", .{ idx, sig, vol, volNo, resLength });

//     const newStartOffset = offset + 5;
//     const newEndOffset = newStartOffset + resLength;

//     // PARSE VOL PART.

//     //std.log.info("[{d}..{d}] - max size: {d}", .{ newStartOffset, newEndOffset, fbs.getEndPos() });
//     // This area of the volPart is purely the logic.
//     var volPartFbs = switch (volNo) {
//         0 => std.io.fixedBufferStream(vol0[newStartOffset..newEndOffset]),
//         1 => std.io.fixedBufferStream(vol1[newStartOffset..newEndOffset]),
//         2 => std.io.fixedBufferStream(vol2[newStartOffset..newEndOffset]),
//         else => unreachable,
//     };

//     // PARSE MESSAGES FIRST

//     // TODO: finish parsing messages and if it works it should XOR with the encryption key: "Avis Durgan" defined above.
//     const messageOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
//     //std.log.info("messageOffset => {d}", .{messageOffset});

//     try volPartFbs.seekBy(messageOffset);
//     const pos = try volPartFbs.getPos();
//     //this.messageStartOffset = pos;
//     const numMessages = try volPartFbs.reader().readByte();
//     //std.log.info("no. messages => {d}", .{numMessages});
//     _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);

//     var decryptIndex: usize = 0;
//     var i: usize = 0;
//     while (i < numMessages) : (i += 1) {
//         const msgPtr = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
//         if (msgPtr == 0) {
//             continue;
//         }

//         var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//         defer arena.deinit();
//         const allocator = arena.allocator();

//         var msgStr = ArrayList(u8).init(allocator);
//         defer msgStr.deinit();

//         const mPos = try volPartFbs.getPos();
//         try volPartFbs.seekTo(pos + msgPtr + 1);
//         while (true) {
//             const currentChar = try volPartFbs.reader().readByte();
//             const decryptedChar = currentChar ^ messageDecryptKey[decryptIndex];
//             try msgStr.append(decryptedChar);
//             decryptIndex += 1;
//             if (decryptIndex >= messageDecryptKey.len) {
//                 decryptIndex = 0;
//             }
//             if (decryptedChar == 0) {
//                 // Forget empty strings which would have a len of 1 but \0 inside them.
//                 if (msgStr.items.len > 1) {
//                     std.log.info("msgStr => \"{s}\"", .{msgStr.items[0 .. msgStr.items.len - 1]});
//                 }
//                 break;
//             }
//         }
//         try volPartFbs.seekTo(mPos);
//     }

//     // PARSE actual VOL PART (after messages extracted)
//     // NOTE: I think I should rip out messages section now that it's been parsed, this way the slice is clean and sectioned off.
//     try volPartFbs.seekTo(pos - messageOffset);

//     // Interpreter local vars
//     var orMode: bool = false;
//     var invertMode: bool = false;
//     var testMode: bool = false;
//     var testResult: bool = true;
//     //var debugLine: string = "";
//     var orResult: bool = false;
//     //var funcName: string;
//     //var test: ITest;
//     //var statement: IStatement;
//     //var args: number[];
//     var maxIters: u32 = 0;

//     while (true) {

//         // TODO: (DELETE ME) Safety to prevent runaway..
//         if (maxIters > 200) {
//             std.log.info("max iterations MET!!!", .{});
//             break;
//         }
//         maxIters += 1;

//         const opCodeNR = volPartFbs.reader().readByte() catch |e| {
//             switch (e) {
//                 error.EndOfStream => break,
//             }
//         };
//         //std.log.info("opCodeNR => {X:0>2}", .{opCodeNR});
//         switch (opCodeNR) {
//             0x00 => {
//                 std.log.info("{X:0>2} => return", .{opCodeNR});
//                 break;
//             },
//             0x91 => std.log.info("{X:0>2} => set.scan.start", .{opCodeNR}),
//             0x92 => std.log.info("{X:0>2} => reset.scan.start", .{opCodeNR}),
//             0xFE => {
//                 const n1: u32 = try volPartFbs.reader().readByte();
//                 const n2: u32 = try volPartFbs.reader().readByte();
//                 const gotoOffset = (((n2 << 8) | n1) << 16) >> 16;
//                 std.log.info("{X:0>2} => goto, offset: {d}", .{ opCodeNR, gotoOffset });
//                 // NOTE: doing a RELATIVE jump: seekBy NOT seekTo (absolute)
//                 try volPartFbs.seekBy(gotoOffset);
//             },
//             0xFF => {
//                 std.log.info("{X:0>2} => if", .{opCodeNR});
//                 if (testMode) {
//                     testMode = false;
//                     const elseOffset = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
//                     if (!testResult) {
//                         // False conditional block. (jump over true block).
//                         std.log.info("doing a false test jump over true!!!", .{});
//                         // NOTE: doing a RELATIVE jump: seekBy NOT seekTo (absolute)
//                         try volPartFbs.seekBy(elseOffset);
//                     } else {
//                         // True conditional block (do nothing).
//                     }
//                 } else {
//                     invertMode = false;
//                     orMode = false;
//                     testResult = true;
//                     orResult = false;
//                     testMode = true;
//                 }
//             },
//             else => {
//                 if (testMode) {
//                     std.log.info("{X:0>2} ELSE", .{opCodeNR});
//                     if (opCodeNR == 0xFC) {
//                         orMode = !orMode;
//                         if (orMode) {
//                             orResult = false;
//                         } else {
//                             testResult = testResult and orResult;
//                         }
//                     } else if (opCodeNR == 0xFD) {
//                         invertMode = !invertMode;
//                     } else {
//                         var testCallResult = false;

//                         if ((opCodeNR - 1) >= cmds.agi_tests.len) {
//                             std.log.info("FATAL: trying to fetch a test from index: {d}", .{opCodeNR - 1});
//                             return;
//                         }
//                         const testFunc = cmds.agi_tests[opCodeNR - 1];

//                         std.log.info("agi test (op:{X:0>2}): {s}(args => {d}) here...", .{ opCodeNR - 1, testFunc.name, testFunc.arity });
//                         if (opCodeNR == 0x0E) { //Said (uses variable num of 16-bit args, within bytecode!)
//                             const saidArgLen = try volPartFbs.reader().readByte();
//                             var iSaidCount: usize = 0;
//                             while (iSaidCount < saidArgLen) : (iSaidCount += 1) {
//                                 _ = try volPartFbs.reader().readInt(u16, std.builtin.Endian.Little);
//                             }
//                         } else {
//                             if (std.mem.eql(u8, testFunc.name, "greatern")) {
//                                 const a = try volPartFbs.reader().readByte();
//                                 const b = try volPartFbs.reader().readByte();
//                                 testCallResult = vmInstance.agi_test_greatern(a, b);
//                                 std.log.info("test_greatern({d}, {d})", .{ a, b });
//                             } else if (std.mem.eql(u8, testFunc.name, "isset")) {
//                                 const a = try volPartFbs.reader().readByte();
//                                 testCallResult = vmInstance.agi_test_isset(a);
//                                 std.log.info("isset({d})", .{a});
//                             } else if (std.mem.eql(u8, testFunc.name, "equaln")) {
//                                 const a = try volPartFbs.reader().readByte();
//                                 const b = try volPartFbs.reader().readByte();
//                                 testCallResult = vmInstance.agi_test_equaln(a, b);
//                                 std.log.info("test_equaln({d}, {d})", .{ a, b });
//                             } else {
//                                 std.log.info("test op:{d}(0x{X:0>2}) not handled!", .{ opCodeNR - 1, opCodeNR - 1 });
//                                 return;
//                             }
//                         }

//                         // Here, actually invoke relevant TEST func with correct args.
//                         // ie, var result = equaln(args);

//                         if (invertMode) {
//                             testCallResult = !testCallResult;
//                             invertMode = false;
//                         }

//                         if (orMode) {
//                             orResult = orResult or testCallResult;
//                         } else {
//                             testResult = testResult and testCallResult;
//                         }
//                     }
//                 } else {
//                     const statementFunc = cmds.agi_statements[opCodeNR];

//                     // TODO: don't do allocator in-line.
//                     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//                     defer arena.deinit();

//                     const allocator = arena.allocator();
//                     // TODO: iterate and collect args.
//                     var argList = ArrayList(u8).init(allocator);
//                     defer argList.deinit();

//                     var arityCount: usize = 0;
//                     while (arityCount < statementFunc.arity) : (arityCount += 1) {
//                         // Need to collect all args and pass into relevant function!
//                         const currentArg = try volPartFbs.reader().readByte();
//                         const myStr = try std.fmt.allocPrint(allocator, "{d},", .{currentArg});
//                         try argList.appendSlice(myStr);
//                         std.log.info("component => {s}", .{myStr});
//                     }

//                     const joinedArgs = try std.mem.join(allocator, ",", &.{argList.items}); //&[_][]const u8{argList.items});

//                     // TODO: execute agi_statement(args);
//                     if (std.mem.eql(u8, statementFunc.name, "new_room")) {
//                         const a = try volPartFbs.reader().readByte();
//                         vmInstance.agi_new_room(a);
//                     } else if (std.mem.eql(u8, statementFunc.name, "quit")) {
//                         const a = try volPartFbs.reader().readByte();
//                         vmInstance.agi_quit(a);
//                     } else if (std.mem.eql(u8, statementFunc.name, "script_size")) {
//                         const a = try volPartFbs.reader().readByte();
//                         vmInstance.agi_script_size(a);
//                     } else if (std.mem.eql(u8, statementFunc.name, "call")) {
//                         const a = try volPartFbs.reader().readByte();
//                         vmInstance.agi_call(a);
//                     } else {
//                         std.log.info("NOT IMPLEMENTED: agi statement: opCode:{d}, {s}({s}) (arg_count => {d})...", .{ opCodeNR, statementFunc.name, joinedArgs, statementFunc.arity });
//                         //vmInstance.vm_op_not_implemented(35);
//                     }

//                     // Finally, special handling for new.room opcode.
//                     if (opCodeNR == 0x12) {
//                         try volPartFbs.seekTo(0);
//                         break;
//                     }
//                 }
//             },
//         }
//     }
// }
