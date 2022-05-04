const std = @import("std");
const go = @import("game_object.zig");

const TOTAL_VARS: usize = 255;
const TOTAL_FLAGS: usize = 255;
const TOTAL_GAME_OBJS: usize = 16; // also called screen objs.

const LOGIC_STACK_SIZE: usize = 255; // Arbitrary size has been chose of 255, I don't expect to exceed it with tech from 1980s.

pub const VM = struct {
    newroom: u8,
    vars: [TOTAL_VARS]u8,
    flags: [TOTAL_FLAGS]bool,
    gameObjects: [TOTAL_GAME_OBJS]go.GameObject,

    logicStack: [LOGIC_STACK_SIZE]u8,
    logicStackPtr: usize,
    activeLogicNo: u8,

    // init creates a new instance of an AGI VM.
    pub fn init() VM {
        var myVM = VM{ .logicStack = std.mem.zeroes([LOGIC_STACK_SIZE]u8), .logicStackPtr = 0, .activeLogicNo = 0, .newroom = 0, .vars = std.mem.zeroes([TOTAL_VARS]u8), .flags = std.mem.zeroes([TOTAL_FLAGS]bool), .gameObjects = std.mem.zeroes([TOTAL_GAME_OBJS]go.GameObject) };
        return myVM;
    }

    pub fn vm_reset(self: *VM) void {
        std.log.info("reset_vm invoked with: {s}", .{self});
    }

    pub fn vm_cycle(self: *VM) void {
        std.log.info("cycle_vm invoked with: {s}", .{self});
    }

    pub fn vm_push_logic_stack(self: *VM, logicNo: u8) void {
        if (self.logicStackPtr == LOGIC_STACK_SIZE - 1) {
            std.log.info("OH NO: stack over flow beyatch!");
            return;
        }
        self.logicStack[self.logicStackPtr] = logicNo;
        self.logicStackPtr += 1;
    }

    pub fn vm_pop_logic_stack(self: *VM) u8 {
        if (self.logicStackPtr == 0) {
            std.log.info("OH NO: stack under flow beyatch!");
            return;
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
        return self.agi_test_equaln(self, varNo1, self.vars[varNo2]);
    }

    pub fn agi_test_greatern(self: *VM, varNo: usize, val: u8) bool {
        return self.vars[varNo] > val;
    }

    pub fn agi_test_isset(self: *VM, flagNo: usize) bool {
        return self.flags[flagNo];
    }

    // AGI Statement invocations.
    pub fn agi_new_room(self: *VM, roomNo: u8) void {
        std.log.info("NEW_ROOM {d}", .{roomNo});
        self.newroom = roomNo;
    }

    pub fn agi_new_room_v(self: *VM, varNo: usize) void {
        agi_new_room(self.vars[varNo]);
    }

    pub fn agi_call(self: *VM, logicNo: usize) void {
        self.vm_push_logic_stack(self.activeLogicNo);
        self.activeLogicNo = logicNo;

        // PSEUDO: if (LOGIC_ALREADY_LOADED):
        // INTERPRET IT.
        // else:
        // LOAD IT.
        // INTERPRET IT.
        // UNLOADED IT.

        //if (this.loadedLogics[logicNo] != null) {
        //    this.loadedLogics[logicNo].parseLogic();
        //} else {
        //    this.agi_load_logic(logicNo);
        //    this.loadedLogics[logicNo].parseLogic();
        //    this.loadedLogics[logicNo] = null;
        //}

        self.activeLogicNo = self.vm_pop_logic_stack();
    }

    pub fn agi_quit(_: *VM, statusCode: u8) void {
        std.log.info("agi_quit({d}) exited..", .{statusCode});
        std.os.exit(statusCode);
    }

    pub fn agi_script_size(_: *VM, a: u8) void {
        std.log.info("agi_script_size({d}) IGNORED..", .{a});
    }

    pub fn agi_load_logic(self: *VM, logNo: usize) void {
        std.log.info("agi_load_logic({s}, {d}", .{ self, logNo });
        //self.loadedLogics[logNo] = new LogicParser(this, logNo);
    }

    pub fn agi_load_logic_v(self: *VM, varNo: u8) void {
        self.agi_load_logic(self.vars[varNo]);
    }

    pub fn agi_call_v(self: *VM, varNo: usize) void {
        self.agi_call(self.vars[varNo]);
    }

    pub fn agi_increment(self: *VM, varNo: usize) void {
        if (self.vars[varNo] < 255) {
            self.vars[varNo] += 1;
        }
    }

    pub fn agi_decrement(self: *VM, varNo: usize) void {
        if (self.vars[varNo] > 0) {
            self.vars[varNo] -= 1;
        }
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
};
