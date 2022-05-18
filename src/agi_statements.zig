const std = @import("std");
const assert = std.debug.assert;
const vm = @import("vm.zig");
const aw = @import("args.zig");
const go = @import("game_object.zig");
const rm = @import("resource_manager.zig");

const clib = @import("c_defs.zig").c;

// NOTE

// 1. Since these functions are not technically bound to the VM instance we pass "self" on dynamic dispatch as the first arg.
// 2. All functions return anyerror!void even if they can't possibly return an error in order to have a uniform function pointer syntax. Implication is they must all have "try" syntax.
// 3. All functions take a *aw.Args object (backed by a slice) for getting/setting arguments dynamically
// 4. For functions that don't utilize arguments, they still take an *aw.Args object for uniformity.
// 5. Functions that should consume their respective args but be skipped are assigned: agi_nop
// 6. Functions that are yet to be implemented are assigned as default: agi_unimplemented

// AGI Statement invocations.

// nop is for a known command that we just consume it's args but ignore.
pub fn agi_nop(self: *vm.VM, args: *aw.Args) anyerror!void {
    self.vm_log("agi_nop({any})...SKIPPING.", .{args.buf});
}

// unimplemented is to set everything to first unknown so we can catch unimplemented calls.
pub fn agi_unimplemented(_: *vm.VM, args: *aw.Args) anyerror!void {
    std.log.warn("agi_unimplemented({any})...UNIMPLEMENTED", .{args.buf});
    return error.Error;
}

pub fn agi_new_room(self: *vm.VM, args: *aw.Args) anyerror!void {
    const roomNo = args.get.a();
    self.newroom = roomNo;
    self.vm_log("NEW_ROOM {d}", .{roomNo});
}

pub fn agi_new_room_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));

    try agi_new_room(self, args.pack());
}

pub fn agi_assignn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const num = args.get.b();

    self.write_var(varNo, num);
    self.vm_log("agi_assignn({d}:varNo, {d}:num);", .{ varNo, num });
}

pub fn agi_assignv(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    try agi_assignn(self, args.pack());
    self.vm_log("agi_assignv({d}:varNo, {d}:num);", .{ varNo1, varNo2 });
}

pub fn agi_call(self: *vm.VM, args: *aw.Args) anyerror!void {
    const logicNo = args.get.a();
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

pub fn agi_call_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));

    try agi_call(self, args.pack());
}

pub fn agi_quit(self: *vm.VM, args: *aw.Args) anyerror!void {
    const statusCode = args.get.a();
    self.vm_log("agi_quit({d}) exited..", .{statusCode});
    std.os.exit(statusCode);
}

pub fn agi_load_logic(self: *vm.VM, logNo: usize) anyerror!void {
    self.vm_log("agi_load_logic({s}, {d}", .{ self, logNo });
    //self.loadedLogics[logNo] = new LogicParser(this, logNo);
}

pub fn agi_load_logic_v(self: *vm.VM, varNo: u8) anyerror!void {
    self.agi_load_logic(self.read_var(varNo));
}

pub fn agi_increment(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    if (self.read_var(varNo) < 255) {
        self.mut_var(varNo, "+=", 1);
    }
    self.vm_log("increment({d}:varNo) invoked to val: {d}", .{ varNo, self.read_var(varNo) });
}

pub fn agi_decrement(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    if (self.read_var(varNo) > 0) {
        self.mut_var(varNo, "-=", 1);
    }
}

pub fn agi_set(self: *vm.VM, args: *aw.Args) anyerror!void {
    const flagNo = args.get.a();
    self.set_flag(flagNo, true);
    self.vm_log("agi_set(flagNo:{d});", .{flagNo});
}

pub fn agi_setv(self: *vm.VM, varNo: u8) anyerror!void {
    self.agi_set(self.read_var(varNo));
    self.vm_log("agi_set(varNo:{d});", .{varNo});
}

pub fn agi_reset(self: *vm.VM, args: *aw.Args) anyerror!void {
    const flagNo = args.get.a();
    self.set_flag(flagNo, false);
}

pub fn agi_reset_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));
    try agi_reset(self, args.pack());
}

pub fn agi_addn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const num = args.get.b();
    // may overflow...might need to do a wrapping %
    self.mut_var(varNo, "+=", num);
}

pub fn agi_addv(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    try agi_addn(self, args.pack());
}

pub fn agi_subn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const num = args.get.b();
    self.mut_var(varNo, "-=", num);
}

pub fn agi_subv(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    try agi_subn(self, args.pack());
}

pub fn agi_muln(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const num = args.get.b();

    self.mut_var(self.read_var(varNo), "*=", num);
}

pub fn agi_mulv(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    try agi_muln(self, args.pack());
}

pub fn agi_divn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const num = args.get.b();

    self.mut_var(self.read_var(varNo), "/=", num);
}

pub fn agi_divv(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();

    args.set.a(varNo1);
    args.set.b(self.read_var(varNo2));

    try agi_divn(self, args.pack());
}

pub fn agi_force_update(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNum = args.get.a();
    self.gameObjects[objNum].update = true;
    // this.agi_draw(objNo);
}

pub fn agi_clear_lines(self: *vm.VM, args: *aw.Args) anyerror!void {
    // for (var y = fromRow; y < row + 1; y++) {
    //         this.screen.bltText(y, 0, "                                        ");
    //     }
    self.vm_log("agi_clear_lines({d},{d},{d})", .{ args.get.a(), args.get.b(), args.get.c() });
}

pub fn agi_prevent_input(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.allowInput = false;
}

pub fn agi_accept_input(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.allowInput = true;
}

pub fn agi_unanimate_all(self: *vm.VM) anyerror!void {
    var i: usize = 0;
    while (i < vm.TOTAL_GAME_OBJS) : (i += 1) {
        self.gameObjects[i] = go.GameObject.init();
    }
}

pub fn agi_stop_update(self: *vm.VM, objNo: u8) anyerror!void {
    self.gameObjects[objNo].update = false;
}

pub fn agi_animate_obj(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    self.gameObjects[objNo] = go.GameObject.init();
    self.vm_log("agi_animate_obj({d}) invoked", .{objNo});
}

pub fn agi_step_size(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.gameObjects[objNo].stepSize = self.read_var(varNo);
}

pub fn agi_step_time(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.gameObjects[objNo].stepTime = self.read_var(varNo);
}

pub fn agi_cycle_time(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.gameObjects[objNo].cycleTime = self.read_var(varNo);
    self.vm_log("agi_cycle_time({d}:objNo, {d}:varNo) invoked", .{ objNo, self.read_var(varNo) });
}

pub fn agi_get_posn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo1 = args.get.b();
    const varNo2 = args.get.c();

    self.write_var(varNo1, self.gameObjects[objNo].x);
    self.write_var(varNo2, self.gameObjects[objNo].y);
    self.vm_log("agi_get_posn({d}:objNo, {d}:varNo1, {d}:varNo2", .{ objNo, varNo1, varNo2 });
    //self.breakpoint() catch unreachable;
}

pub fn agi_observe_blocks(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].ignoreBlocks = false;
}

pub fn agi_observe_objs(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].ignoreObjs = false;
}

pub fn agi_ignore_objs(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].ignoreObjs = true;
}

pub fn agi_observe_horizon(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].ignoreHorizon = false;
}

pub fn agi_lindirectn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const val = args.get.b();

    self.write_var(self.read_var(varNo), val);
}

pub fn agi_set_view(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const viewNo = args.get.b();

    self.gameObjects[objNo].viewNo = viewNo;
    self.gameObjects[objNo].loop = 0;
    self.gameObjects[objNo].cel = 0;
    self.gameObjects[objNo].celCycling = true;
}

pub fn agi_set_view_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo));

    try agi_set_view(self, args.pack());
}

pub fn agi_load_view(self: *vm.VM, args: *aw.Args) anyerror!void {
    const viewNo = args.get.a();
    //self.loadedViews[viewNo] = new View(Resources.readAgiResource(Resources.AgiResource.View, viewNo));
    std.log.debug("agi_load_view({d}) invoked...(sampleTexture => {s})", .{ viewNo, vm.sampleTexture });

    // TODO: since views are extracted as .png in the format of: 39_1_0.png. (view, loop, cell)
    // I need to load all .png files in the view set: 39_*_*.png and show the relevant one based on the animation loop/cycle.
    // Since all related files are now separate .png, one strategy is to just iterate with a loop and do a file exists check.

    const maxLoops = 15;
    const maxCels = 15;

    var loopIndex: usize = 0;
    var celIndex: usize = 0;

    // Total file exists brute force approach...not the cleanest...but...good enough for now.
    while (loopIndex < maxLoops) : (loopIndex += 1) {
        while (celIndex < maxCels) : (celIndex += 1) {
            var buf: [100]u8 = undefined;
            const fmtStr = try vm.VM.vm_view_key(&buf, viewNo, @intCast(u8, loopIndex), @intCast(u8, celIndex));

            // Oh! already loaded so just skip over.
            const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));
            if (texture) |_| {
                std.log.debug("texture: {s} was previously loaded so doing nothing!", .{fmtStr});
                continue;
            }

            const cstr = try vm.allocator.dupeZ(u8, fmtStr);
            defer vm.allocator.free(cstr);

            if (clib.FileExists(cstr)) {
                _ = try self.resMan.add_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));
                self.vm_log("located view file: {s}", .{fmtStr});

                // Poor mans record of view/loop/cel entries, so we can easily query loop counts or cel counts per view.
                self.viewDB[viewNo][@intCast(u8, loopIndex)] += 1;
            } else {
                //self.vm_log("view file NOT found: {s}", .{fmtStr});
            }
        }
        celIndex = 0;
    }
}

pub fn agi_load_view_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));

    try agi_load_view(self, args.pack());
}

// fn vm_reset_viewDB(self: *vm.VM) anyerror!void {
//     self.viewDB = std.mem.zeroes([1000][20]u8);
// }

// fn vm_view_loop_count(self: *vm.VM, viewNo: usize) usize {
//     var i: usize = 0;
//     var counter: usize = 0;
//     while (i < self.viewDB[viewNo].len) : (i += 1) {
//         if (self.viewDB[viewNo][i] > 0) {
//             counter += 1;
//         }
//     }
//     return counter;
// }

// fn vm_view_loop_cel_count(self: *vm.VM, viewNo: usize, loopNo: usize) usize {
//     return self.viewDB[viewNo][loopNo];
// }

pub fn agi_block(self: *vm.VM, x1: u8, y1: u8, x2: u8, y2: u8) anyerror!void {
    self.blockX1 = x1;
    self.blockY1 = y1;
    self.blockX2 = x2;
    self.blockY2 = y2;
}

pub fn agi_unblock(self: *vm.VM) anyerror!void {
    self.blockX1 = 0;
    self.blockY1 = 0;
    self.blockX2 = 0;
    self.blockY2 = 0;
}

pub fn agi_set_horizon(self: *vm.VM, args: *aw.Args) anyerror!void {
    const y = args.get.a();
    self.horizon = y;
}

pub fn agi_load_sound(self: *vm.VM, args: *aw.Args) anyerror!void {
    const soundNo = args.get.a();
    self.vm_log("agi_load_sound({d}) invoked...", .{soundNo});
}

pub fn agi_sound(self: *vm.VM, args: *aw.Args) anyerror!void {
    const soundNo = args.get.a();
    const flagNo = args.get.b();
    self.vm_log("agi_sound({d}, {d}) invoked...", .{ soundNo, flagNo });
}

pub fn agi_stop_sound(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.vm_log("agi_stop_sound() invoked...", .{});
}

pub fn agi_load_pic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const picNo = self.read_var(varNo);
    self.vm_log("agi_load_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
    // this.loadedPics[picNo] = new Pic(Resources.readAgiResource(Resources.AgiResource.Pic, picNo));
}

pub fn agi_draw_pic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    // this.visualBuffer.clear(0x0F);
    // this.priorityBuffer.clear(0x04);
    try agi_overlay_pic(self, varNo);
    self.vm_log("agi_draw_pic({d})", .{varNo});
}

pub fn agi_draw(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].draw = true;
}

pub fn agi_overlay_pic(self: *vm.VM, varNo: u8) anyerror!void {
    const picNo = self.read_var(varNo);

    self.vm_log("agi_overlay_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
    //this.loadedPics[picNo].draw(this.visualBuffer, this.priorityBuffer);
}

pub fn agi_discard_pic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const picNo = self.read_var(varNo);
    self.vm_log("agi_discard_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
    //this.loadedPics[picNo] = null;
}

pub fn agi_add_to_pic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const viewNo = args.get.a();
    const loopNo = args.get.b();
    const celNo = args.get.c();
    const x = args.get.d();
    const y = args.get.e();
    const priority = args.get.f();
    const margin = args.get.g();

    // TODO: Add margin
    //this.screen.bltView(viewNo, loopNo, celNo, x, y, priority);
    self.vm_log("agi_add_to_pic({d},{d},{d},{d},{d},{d},{d})", .{ viewNo, loopNo, celNo, x, y, priority, margin });
}

pub fn agi_add_to_pic_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();
    const varNo3 = args.get.c();
    const varNo4 = args.get.d();
    const varNo5 = args.get.e();
    const varNo6 = args.get.f();
    const varNo7 = args.get.g();

    args.set.a(self.read_var(varNo1));
    args.set.a(self.read_var(varNo2));
    args.set.a(self.read_var(varNo3));
    args.set.a(self.read_var(varNo4));
    args.set.a(self.read_var(varNo5));
    args.set.a(self.read_var(varNo6));
    args.set.a(self.read_var(varNo7));

    try agi_add_to_pic(self, args.pack());
}

pub fn agi_show_pic(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.vm_log("agi_show_pic()", .{});
    // this.screen.bltPic();
    // this.gameObjects.forEach(obj => {
    //     obj.redraw = true;
    // });
}

pub fn agi_set_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const loopNo = args.get.b();
    self.gameObjects[objNo].loop = loopNo;
}

pub fn agi_set_loop_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo));

    self.agi_set_loop(args.pack());
}

pub fn agi_position(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const x = args.get.b();
    const y = args.get.c();

    self.gameObjects[objNo].x = x;
    self.gameObjects[objNo].y = y;
}

pub fn agi_position_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo1 = args.get.b();
    const varNo2 = args.get.c();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo1));
    args.set.c(self.read_var(varNo2));

    self.agi_position(args.pack());
}

fn agi_set_dir(self: *vm.VM, objNo: u8, varNo: u8) anyerror!void {
    self.gameObjects[objNo].direction = self.read_var(varNo);
}

fn agi_get_dir(self: *vm.VM, objNo: u8, varNo: u8) anyerror!void {
    self.write_var(varNo, self.gameObjects[objNo].direction);
}

pub fn agi_set_cel(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const celNo = args.get.b();

    self.gameObjects[objNo].nextCycle = 1;
    self.gameObjects[objNo].cel = celNo;
}

pub fn agi_set_cel_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo));

    try agi_set_cel(self, args.pack());
}

pub fn agi_set_priority(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const priority = args.get.b();

    self.gameObjects[objNo].priority = priority;
    self.gameObjects[objNo].fixedPriority = true;
}

pub fn agi_set_priority_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo));

    try agi_set_priority(self, args.pack());
}

pub fn agi_stop_cycling(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].celCycling = false;
    self.vm_log("stop_cycling({d}:objNo)...", .{objNo});
}

pub fn agi_start_cycling(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].celCycling = true;
    self.vm_log("start_cycling({d}:objNo)...", .{objNo});
}

pub fn agi_normal_cycle(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].reverseCycle = false;
}

pub fn agi_normal_motion(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].motion = true;
}

pub fn agi_currentview(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();
    self.write_var(varNo, self.gameObjects[objNo].viewNo);
}

pub fn agi_player_control(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.programControl = false;

    // NOTE: Edge case in scummvm logic only when under playerControl called.
    // https://github.com/scummvm/scummvm/blob/90f2ff2532ca71033b4393b9ce604c9b0e6cafa0/engines/agi/op_cmd.cpp#L1612
}

pub fn agi_program_control(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.programControl = true;
    self.vm_log("agi_programControl({s}", .{true});
}

pub fn agi_move_obj(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const x = args.get.b();
    const y = args.get.c();
    const stepSpeed = args.get.d();
    const flagNo = args.get.e();

    var obj = &self.gameObjects[objNo];

    obj.moveToX = x;
    obj.moveToY = y;
    obj.moveToStep = stepSpeed;
    obj.movementFlag = go.MovementFlags.MoveTo;
    obj.flagToSetWhenFinished = flagNo;
}

pub fn agi_display(self: *vm.VM, args: *aw.Args) anyerror!void {
    const row = args.get.a();
    const col = args.get.b();
    const msg = args.get.c();
    self.vm_log("agi_display({d}:row, {d}:col, {d}:msg) invoked...", .{ row, col, msg });
    //this.screen.bltText(row, col, this.loadedLogics[this.logicNo].logic.messages[msg]);
}

pub fn agi_display_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();
    const varNo3 = args.get.c();

    args.set.a(self.read_var(varNo1));
    args.set.b(self.read_var(varNo2));
    args.set.c(self.read_var(varNo3));

    try agi_display(self, args.pack());
}

pub fn agi_fix_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].fixedLoop = true;
}

pub fn agi_release_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.gameObjects[objNo].fixedLoop = false;
}

pub fn agi_erase(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    var obj = &self.gameObjects[objNo];
    obj.draw = false;
    obj.loop = 0;
    obj.cel = 0;
    //this.screen.clearView(obj.oldView, obj.oldLoop, obj.oldCel, obj.oldDrawX, obj.oldDrawY, obj.oldPriority);
}

pub fn agi_reposition_to(self: *vm.VM, args: *aw.Args) anyerror!void {
    // NOTE: for this call just forward the args as-is.
    //var obj: GameObject = this.gameObjects[objNo]; (this line is uneeded but in the agi.js implementation)
    try agi_position(self, args);
}

pub fn agi_reposition_to_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo1 = args.get.b();
    const varNo2 = args.get.c();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo1));
    args.set.c(self.read_var(varNo2));
    try agi_reposition_to(self, args.pack());
}

pub fn agi_follow_ego(self: *vm.VM, objNo: u8, stepSpeed: u8, flagNo: u8) anyerror!void {
    var obj = &self.gameObjects[objNo];
    obj.moveToStep = stepSpeed;
    obj.flagToSetWhenFinished = flagNo;
    obj.movementFlag = go.MovementFlags.ChaseEgo;
}

pub fn agi_wander(self: *vm.VM, objNo: u8) anyerror!void {
    self.gameObjects[objNo].movementFlag = go.MovementFlags.Wander;
    self.gameObjects[objNo].direction = 5; // TODO: this.randomBetween(1, 9);

    if (objNo == 0) {
        self.write_var(6, self.gameObjects[objNo].direction);
        self.agi_program_control();
    }
}
