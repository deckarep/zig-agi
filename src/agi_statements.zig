const std = @import("std");
const assert = std.debug.assert;
const vm = @import("vm.zig");
const aw = @import("args.zig");
const go = @import("game_object.zig");
const rm = @import("resource_manager.zig");
const hlp = @import("raylib_helpers.zig");
const pmpt = @import("prompt.zig");
const vms = @import("vm_state.zig");

const clib = @import("c_defs.zig").c;

// NOTE

// 1. Since these functions are not technically bound to the VM instance we pass "self" on dynamic dispatch as the first arg.
// 2. All functions return anyerror!void even if they can't possibly return an error in order to have a uniform function pointer syntax. Implication is they must all have "try" syntax.
// 3. All functions take a *aw.Args object (backed by a slice) for getting/setting arguments dynamically
// 4. For functions that don't utilize arguments, they still take an *aw.Args object for uniformity.
// 5. Functions that should consume their respective args but be skipped are assigned: agi_nop and will not halt the interpreter.
// 6. Functions that are yet to be implemented are assigned as default: agi_unimplemented and will halt the interpreter.

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

    if (roomNo == 6) {
        self.newroom = 11;
        // Room 6 = Age Test (boring)
        // Room 11 = Outside bar.
        std.log.info("INTERCEPTED NEW_ROOM OF {d} -> {d}", .{ roomNo, 11 });
    } else {
        self.newroom = roomNo;
        self.vm_log("NEW_ROOM {d}", .{roomNo});
    }
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
    var logicNo = args.get.a();

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

pub fn agi_load_logic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const logNo = args.get.a();
    self.vm_log("agi_load_logic({s}, {d}", .{ self, logNo });
    //self.loadedLogics[logNo] = new LogicParser(this, logNo);
}

pub fn agi_load_logic_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));

    try agi_load_logic(self, args.pack());
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

pub fn agi_toggle(self: *vm.VM, args: *aw.Args) anyerror!void {
    const flagNo = args.get.a();
    self.set_flag(flagNo, !self.get_flag(flagNo));
}

pub fn agi_toggle_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));
    try agi_toggle(self, args.pack());
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
    self.state.gameObjects[objNum].update = true;
    // this.agi_draw(objNo);
}

pub fn agi_clear_lines(self: *vm.VM, args: *aw.Args) anyerror!void {
    const fromRow = args.get.a();
    const toRow = args.get.b();

    // Note: for this zig implementation we're not doing anything with color at the moment.
    // const color = args.get.c();

    var y: usize = @intCast(usize, fromRow);
    while (y < @intCast(usize, toRow) + 1) : (y += 1) {
        self.textGrid[y] = std.mem.zeroes([40]u8);
    }
}

pub fn agi_prevent_input(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.allowInput = false;
}

pub fn agi_accept_input(self: *vm.VM, _: *aw.Args) anyerror!void {
    self.allowInput = true;
}

pub fn agi_unanimate_all(self: *vm.VM) anyerror!void {
    var i: usize = 0;
    while (i < vms.TOTAL_GAME_OBJS) : (i += 1) {
        self.state.gameObjects[i] = go.GameObject.init();
    }
}

pub fn agi_stop_update(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    self.state.gameObjects[objNo].update = false;
}

pub fn agi_stop_motion(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    if (objNo == 0) {
        try agi_program_control(self, args);
    }

    self.state.gameObjects[objNo].motion = false;
    self.state.gameObjects[objNo].direction = go.Direction.Stopped;
}

pub fn agi_start_motion(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    if (objNo == 0) {
        try agi_player_control(self, args);
    }

    self.state.gameObjects[objNo].motion = true;
}

pub fn agi_animate_obj(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    self.state.gameObjects[objNo] = go.GameObject.init();
    self.vm_log("agi_animate_obj({d}) invoked", .{objNo});
}

pub fn agi_step_size(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.state.gameObjects[objNo].stepSize = self.read_var(varNo);
}

pub fn agi_step_time(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.state.gameObjects[objNo].stepTime = self.read_var(varNo);
}

pub fn agi_cycle_time(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();

    self.state.gameObjects[objNo].cycleTime = self.read_var(varNo);
    self.vm_log("agi_cycle_time({d}:objNo, {d}:varNo) invoked", .{ objNo, self.read_var(varNo) });
}

pub fn agi_get_posn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo1 = args.get.b();
    const varNo2 = args.get.c();

    self.write_var(varNo1, self.state.gameObjects[objNo].x);
    self.write_var(varNo2, self.state.gameObjects[objNo].y);
    self.vm_log("agi_get_posn({d}:objNo, {d}:varNo1, {d}:varNo2", .{ objNo, varNo1, varNo2 });
    //self.breakpoint() catch unreachable;
}

pub fn agi_observe_blocks(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreBlocks = false;
}

pub fn agi_ignore_blocks(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreBlocks = true;
}

pub fn agi_observe_objs(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreObjs = false;
}

pub fn agi_ignore_objs(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreObjs = true;
}

pub fn agi_observe_horizon(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreHorizon = false;
}

pub fn agi_ignore_horizon(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].ignoreHorizon = true;
}

pub fn agi_lindirectn(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();
    const val = args.get.b();

    self.write_var(self.read_var(varNo), val);
}

pub fn agi_set_view(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const viewNo = args.get.b();

    self.state.gameObjects[objNo].viewNo = viewNo;
    self.state.gameObjects[objNo].loop = 0;
    self.state.gameObjects[objNo].cel = 0;
    self.state.gameObjects[objNo].celCycling = true;
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

    var buf: [100]u8 = undefined;
    const fmtStr = try vm.VM.vm_pic_key(&buf, picNo);

    // Oh! already loaded so just skip over.
    const texture = self.resMan.ref_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));
    if (texture) |_| {
        std.log.debug("texture: {s} was previously loaded so doing nothing!", .{fmtStr});
        return;
    }

    _ = try self.resMan.add_texture(rm.WithKey(rm.ResourceTag.Texture, fmtStr));

    // this.loadedPics[picNo] = new Pic(Resources.readAgiResource(Resources.AgiResource.Pic, picNo));
}

pub fn agi_draw_pic(self: *vm.VM, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    clib.BeginTextureMode(self.picTex);
    defer clib.EndTextureMode();
    clib.ClearBackground(hlp.col(0, 0, 0, 255));
    // this.visualBuffer.clear(0x0F);
    // this.priorityBuffer.clear(0x04);
    try agi_overlay_pic(self, varNo);
    std.log.info("agi_draw_pic({d})", .{varNo});
}

pub fn agi_end_of_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const flagNo = args.get.b();

    self.state.gameObjects[objNo].callAtEndOfLoop = true;
    self.state.gameObjects[objNo].flagToSetWhenFinished = flagNo;
    // self.state.gameObjects[objNo].celCycling = true;
}

pub fn agi_overlay_pic(self: *vm.VM, varNo: u8) anyerror!void {
    const picNo = self.read_var(varNo);

    self.vm_log("agi_overlay_pic({d}) (picNo:{d})invoked...", .{ varNo, picNo });
    //this.loadedPics[picNo].draw(this.visualBuffer, this.priorityBuffer);
    try self.vm_draw_pic(picNo);
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
    const margin = args.get.g(); // Original source calls this "box priority".

    try self.vm_add_view_to_pic_at(viewNo, loopNo, celNo, x, y, priority, margin);
    // clib.BeginTextureMode(self.picTex);
    // defer clib.EndTextureMode();
    // clib.DrawTexturePro(txt, hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.rect(0, 0, @intToFloat(f32, txt.width), @intToFloat(f32, txt.height)), hlp.vec2(0, 0), 0, clib.WHITE);

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
    args.set.b(self.read_var(varNo2));
    args.set.c(self.read_var(varNo3));
    args.set.d(self.read_var(varNo4));
    args.set.e(self.read_var(varNo5));
    args.set.f(self.read_var(varNo6));
    args.set.g(self.read_var(varNo7));

    try agi_add_to_pic(self, args.pack());
}

pub fn agi_show_pic(self: *vm.VM, _: *aw.Args) anyerror!void {
    // TODO: find a spot to set this back to false when a room change occurs probably.
    self.show_background = true;
    self.vm_log("agi_show_pic()", .{});
    // this.screen.bltPic();
    // this.gameObjects.forEach(obj => {
    //     obj.redraw = true;
    // });
}

pub fn agi_draw(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].draw = true;
}

pub fn agi_set_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const loopNo = args.get.b();
    self.state.gameObjects[objNo].loop = loopNo;
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

    self.state.gameObjects[objNo].x = x;
    self.state.gameObjects[objNo].y = y;
}

pub fn agi_position_v(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo1 = args.get.b();
    const varNo2 = args.get.c();

    args.set.a(objNo);
    args.set.b(self.read_var(varNo1));
    args.set.c(self.read_var(varNo2));

    try agi_position(self, args.pack());
}

fn agi_set_dir(self: *vm.VM, objNo: u8, varNo: u8) anyerror!void {
    self.state.gameObjects[objNo].direction = self.read_var(varNo);
}

fn agi_get_dir(self: *vm.VM, objNo: u8, varNo: u8) anyerror!void {
    self.write_var(varNo, self.state.gameObjects[objNo].direction);
}

pub fn agi_set_cel(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const celNo = args.get.b();

    self.state.gameObjects[objNo].nextCycle = 1;
    self.state.gameObjects[objNo].cel = celNo;
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

    self.state.gameObjects[objNo].priority = priority;
    self.state.gameObjects[objNo].fixedPriority = true;
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
    self.state.gameObjects[objNo].celCycling = false;
    self.vm_log("stop_cycling({d}:objNo)...", .{objNo});
}

pub fn agi_start_cycling(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].celCycling = true;
    self.vm_log("start_cycling({d}:objNo)...", .{objNo});
}

pub fn agi_normal_cycle(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].reverseCycle = false;
}

pub fn agi_normal_motion(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].motion = true;
}

pub fn agi_currentview(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();
    self.write_var(varNo, self.state.gameObjects[objNo].viewNo);
}

pub fn agi_current_cel(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const varNo = args.get.b();
    self.write_var(varNo, self.state.gameObjects[objNo].cel);
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

    var obj = &self.state.gameObjects[objNo];

    obj.moveToX = x;
    obj.moveToY = y;
    obj.moveToStep = stepSpeed;
    obj.movementFlag = go.MovementFlags.MoveTo;
    obj.flagToSetWhenFinished = flagNo;
}

pub fn agi_distance(self: *vm.VM, args: *aw.Args) anyerror!void {
    const obj1 = args.get.a();
    const obj2 = args.get.b();
    const varNo = args.get.c();

    var ob1 = &self.state.gameObjects[obj1];
    var ob2 = &self.state.gameObjects[obj2];

    if (ob1.draw and ob2.draw) {
        const first = try std.math.absInt(@intCast(i32, ob1.x - ob2.x));
        const second = try std.math.absInt(@intCast(i32, ob1.y - ob2.y));
        const result = first + second;
        self.write_var(varNo, @intCast(u8, result));
    } else {
        self.write_var(varNo, 255);
    }
}

pub fn agi_display(_: *vm.VM, args: *aw.Args) anyerror!void {
    const row = args.get.a();
    const col = args.get.b();
    const msgNo = args.get.c();

    // TODO: let's tackle this next! Display messages in the console window.
    // From the original source of RM1.MSG (huh? what source?):
    //      Display( 23, 3, 2); (row, col, msgNo) where msg 2 == "Adventure Game Development System"
    //      Display( 24, 4, 3);                   where msg 3 == "(C) 1987 by Sierra On-Line, Inc."

    //const msg = self.messageList.items[msgNo];
    // for (self.messageList.items) |x| {
    //     std.log.info("x => {s}", .{x});
    // }
    //std.log.info("activeMessages: {any}", .{self.activeMessages});
    std.log.info("agi_display(row:{d}, col:{d}, msgNo:{d})", .{ row, col, msgNo });

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

pub fn agi_display_ctx(self: *vm.VM, ctx: *const aw.Context, args: *aw.Args) anyerror!void {
    const row = args.get.a();
    const col = args.get.b();
    const msgNo = args.get.c();

    // TODO: let's tackle this next! Display messages in the console window.
    // From the original source of RM1.MSG (huh? what source?):
    //      Display( 23, 3, 2); (row, col, msgNo) where msg 2 == "Adventure Game Development System"
    //      Display( 24, 4, 3);                   where msg 3 == "(C) 1987 by Sierra On-Line, Inc."
    const msg = ctx.messageMap.get(@intCast(usize, msgNo)).?;

    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        self.textGrid[row][col + i] = msg[i];
    }

    //std.log.info("agi_display(row:{d}, col:{d}, msgNo:{d}) => {s}", .{ row, col, msgNo, msg });
}

pub fn agi_display_v_ctx(self: *vm.VM, ctx: *const aw.Context, args: *aw.Args) anyerror!void {
    const varNo1 = args.get.a();
    const varNo2 = args.get.b();
    const varNo3 = args.get.c();

    args.set.a(self.read_var(varNo1));
    args.set.b(self.read_var(varNo2));
    args.set.c(self.read_var(varNo3));

    try agi_display_ctx(self, ctx, args.pack());
}

pub fn agi_print_ctx(_: *vm.VM, ctx: *const aw.Context, args: *aw.Args) anyerror!void {
    const msgNo = args.get.a();
    const msg = ctx.messageMap.get(@intCast(usize, msgNo)).?;

    std.log.info("print_ctx msgNo:{d} and message: \n{s}", .{ msgNo, msg });
}

pub fn agi_print_v_ctx(self: *vm.VM, ctx: *const aw.Context, args: *aw.Args) anyerror!void {
    const varNo = args.get.a();

    args.set.a(self.read_var(varNo));

    try agi_print_ctx(self, ctx, args.pack());
}

pub fn agi_fix_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].fixedLoop = true;
}

pub fn agi_release_loop(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    self.state.gameObjects[objNo].fixedLoop = false;
}

pub fn agi_erase(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    var obj = &self.state.gameObjects[objNo];
    obj.draw = false;
    obj.loop = 0;
    obj.cel = 0;

    std.log.info("erase invoked for objNo: {d}", .{objNo});
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

pub fn agi_follow_ego(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();
    const stepSpeed = args.get.b();
    const flagNo = args.get.c();

    var obj = &self.state.gameObjects[objNo];
    obj.moveToStep = stepSpeed;
    obj.flagToSetWhenFinished = flagNo;
    obj.movementFlag = go.MovementFlags.ChaseEgo;
}

pub fn agi_wander(self: *vm.VM, args: *aw.Args) anyerror!void {
    const objNo = args.get.a();

    self.state.gameObjects[objNo].movementFlag = go.MovementFlags.Wander;
    self.state.gameObjects[objNo].direction = go.Direction.UpRight; // TODO: this.randomBetween(1, 9);

    if (objNo == 0) {
        //self.write_var(6, self.state.gameObjects[objNo].direction);
        //self.agi_program_control();
    }
}

pub fn agi_random(self: *vm.VM, args: *aw.Args) anyerror!void {
    const start = args.get.a();
    const end = args.get.b();
    const varNo = args.get.c();

    self.write_var(varNo, self.vm_random_between(start, end));
}

pub fn agi_get_num_ctx(self: *vm.VM, ctx: *const aw.Context, args: *aw.Args) anyerror!void {
    const msgNo = args.get.a();
    const varNo = args.get.b();

    // TODO: for now, just prompt the message on the command line and read in a value into the variable.
    const msg = ctx.messageMap.get(@intCast(usize, msgNo)).?;
    std.log.info("> {s}", .{msg});
    const userNumber = try pmpt.number();

    std.log.info("user entered: '{d}'", .{userNumber});

    self.write_var(varNo, @intCast(u8, userNumber));
}
