const predicates = @import("agi_predicates.zig");
const statements = @import("agi_statements.zig");
const vm = @import("vm.zig");
const aw = @import("args.zig");

// /**
//  * AGI variables. (VM dedicated Vars Pulled from ScummVM)
//  */
pub const VM_VARS = enum(usize) {
    CURRENT_ROOM = 0, // 0
    PREVIOUS_ROOM, // 1
    BORDER_TOUCH_EGO, // 2
    SCORE, // 3
    BORDER_CODE, // 4
    BORDER_TOUCH_OBJECT, // 5
    EGO_DIRECTION, // 6
    MAX_SCORE, // 7
    FREE_PAGES, // 8
    WORD_NOT_FOUND, // 9
    TIME_DELAY, // 10
    SECONDS, // 11
    MINUTES, // 12
    HOURS, // 13
    DAYS, // 14
    JOYSTICK_SENSITIVITY, // 15
    EGO_VIEW_RESOURCE, // 16
    AGI_ERROR_CODE, // 17
    AGI_ERROR_INFO, // 18
    KEY, // 19
    COMPUTER, // 20
    WINDOW_AUTO_CLOSE_TIMER, // 21
    SOUNDGENERATOR, // 22
    VOLUME, // 23
    MAX_INPUT_CHARACTERS, // 24
    SELECTED_INVENTORY_ITEM, // 25
    MONITOR = 26, // 26
    MOUSE_BUTTONSTATE = 27, // 27
    MOUSE_X = 28, // 28
    MOUSE_Y = 29, // 29
};

// TODO: turn these into usable enum definitions from Zig-land.

// /**
//  * AGI flags (VM flags pulled from ScummVM)
//  */
// enum {
// 	VM_FLAG_EGO_WATER = 0,  // 0
// 	VM_FLAG_EGO_INVISIBLE,  // 1
// 	VM_FLAG_ENTERED_CLI,    // 2
// 	VM_FLAG_EGO_TOUCHED_P2,    // 3
// 	VM_FLAG_SAID_ACCEPTED_INPUT,    // 4
// 	VM_FLAG_NEW_ROOM_EXEC,  // 5
// 	VM_FLAG_RESTART_GAME, // 6
// 	VM_FLAG_SCRIPT_BLOCKED, // 7
// 	VM_FLAG_JOY_SENSITIVITY, //8
// 	VM_FLAG_SOUND_ON, // 9
// 	VM_FLAG_DEBUGGER_ON,        // 10
// 	VM_FLAG_LOGIC_ZERO_FIRST_TIME, //11
// 	VM_FLAG_RESTORE_JUST_RAN, //12
// 	VM_FLAG_STATUS_SELECTS_ITEMS, //13
// 	VM_FLAG_MENUS_ACCESSIBLE, //14
// 	VM_FLAG_OUTPUT_MODE,        // 15
// 	VM_FLAG_AUTO_RESTART //16
// };

// Predicate/Statement commands also cross-referenced with:
// * https://github.com/r1sc/agi.js/blob/master/Interpreter.ts
// * https://github.com/sonneveld/nagi/blob/master/src/logic/cmd_table.c (more complete reference it would seem)

pub const agi_predicate_tuple = struct {
    name: []const u8,
    func: fn (self: *vm.VM, args: *aw.Args) anyerror!bool,
    arity: i8,
    bitSize: usize,
};

pub const agi_predicates = [_]agi_predicate_tuple{
    agi_predicate_tuple{ .name = "equaln", .func = predicates.agi_test_equaln, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "equalv", .func = predicates.agi_test_equalv, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "lessn", .func = predicates.agi_nop, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "lessv", .func = predicates.agi_nop, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "greatern", .func = predicates.agi_test_greatern, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "greaterv", .func = predicates.agi_nop, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "isset", .func = predicates.agi_test_isset, .arity = 1, .bitSize = 8 },
    agi_predicate_tuple{ .name = "issetv", .func = predicates.agi_nop, .arity = 1, .bitSize = 8 },
    agi_predicate_tuple{ .name = "has", .func = predicates.agi_nop, .arity = 1, .bitSize = 8 },
    agi_predicate_tuple{ .name = "obj_in_room", .func = predicates.agi_nop, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "posn", .func = predicates.agi_nop, .arity = 5, .bitSize = 8 },
    agi_predicate_tuple{ .name = "controller", .func = predicates.agi_test_controller, .arity = 1, .bitSize = 8 },
    agi_predicate_tuple{ .name = "have_key", .func = predicates.agi_test_have_key, .arity = 0, .bitSize = 8 },
    agi_predicate_tuple{ .name = "said", .func = predicates.agi_test_said, .arity = -1, .bitSize = 16 }, // NOTE: this is dynamic args.
    agi_predicate_tuple{ .name = "compare_strings", .func = predicates.agi_nop, .arity = 2, .bitSize = 8 },
    agi_predicate_tuple{ .name = "obj_in_box", .func = predicates.agi_nop, .arity = 5, .bitSize = 8 },
    agi_predicate_tuple{ .name = "center_posn", .func = predicates.agi_nop, .arity = 5, .bitSize = 8 },
    agi_predicate_tuple{ .name = "right_posn", .func = predicates.agi_nop, .arity = 5, .bitSize = 8 },
    agi_predicate_tuple{ .name = "unknown.19", .func = predicates.agi_nop, .arity = 5, .bitSize = 8 },
};

pub const agi_statement_tuple = struct {
    name: []const u8,
    func: fn (self: *vm.VM, args: *aw.Args) anyerror!void,
    arity: i8,
};

pub const agi_statements = [_]agi_statement_tuple{
    agi_statement_tuple{ .name = "return", .func = statements.agi_nop, .arity = 0 },
    agi_statement_tuple{ .name = "increment", .func = statements.agi_increment, .arity = 1 },
    agi_statement_tuple{ .name = "decrement", .func = statements.agi_decrement, .arity = 1 },
    agi_statement_tuple{ .name = "assignn", .func = statements.agi_assignn, .arity = 2 },
    agi_statement_tuple{ .name = "assignv", .func = statements.agi_assignv, .arity = 2 },

    agi_statement_tuple{ .name = "addn", .func = statements.agi_addn, .arity = 2 },
    agi_statement_tuple{ .name = "addv", .func = statements.agi_addv, .arity = 2 },

    agi_statement_tuple{ .name = "subn", .func = statements.agi_subn, .arity = 2 },
    agi_statement_tuple{ .name = "subv", .func = statements.agi_subv, .arity = 2 },

    agi_statement_tuple{ .name = "lindirectv", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "rindirect", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "lindirectn", .func = statements.agi_lindirectn, .arity = 2 },

    agi_statement_tuple{ .name = "set", .func = statements.agi_set, .arity = 1 },
    agi_statement_tuple{ .name = "reset", .func = statements.agi_reset, .arity = 1 },

    agi_statement_tuple{ .name = "toggle", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "set_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "reset_v", .func = statements.agi_reset_v, .arity = 1 },
    agi_statement_tuple{ .name = "toggle_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "new_room", .func = statements.agi_new_room, .arity = 1 },
    agi_statement_tuple{ .name = "new_room_v", .func = statements.agi_new_room_v, .arity = 1 },
    agi_statement_tuple{ .name = "load_logic", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "load_logic_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "call", .func = statements.agi_call, .arity = 1 },
    agi_statement_tuple{ .name = "call_v", .func = statements.agi_call_v, .arity = 1 },
    agi_statement_tuple{ .name = "load_pic", .func = statements.agi_load_pic, .arity = 1 },
    agi_statement_tuple{ .name = "draw_pic", .func = statements.agi_draw_pic, .arity = 1 },
    agi_statement_tuple{ .name = "show_pic", .func = statements.agi_show_pic, .arity = 0 },
    agi_statement_tuple{ .name = "discard_pic", .func = statements.agi_discard_pic, .arity = 1 },
    agi_statement_tuple{ .name = "overlay_pic", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "show_pri_screen", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "load_view", .func = statements.agi_load_view, .arity = 1 },
    agi_statement_tuple{ .name = "load_view_v", .func = statements.agi_load_view_v, .arity = 1 },
    agi_statement_tuple{ .name = "discard_view", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "animate_obj", .func = statements.agi_animate_obj, .arity = 1 },
    agi_statement_tuple{ .name = "unanimate_all", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "draw", .func = statements.agi_draw, .arity = 1 },
    agi_statement_tuple{ .name = "erase", .func = statements.agi_erase, .arity = 1 },
    agi_statement_tuple{ .name = "position", .func = statements.agi_position, .arity = 3 },
    agi_statement_tuple{ .name = "position_v", .func = statements.agi_unimplemented, .arity = 3 },
    agi_statement_tuple{ .name = "get_posn", .func = statements.agi_get_posn, .arity = 3 },
    agi_statement_tuple{ .name = "reposition", .func = statements.agi_unimplemented, .arity = 3 },
    agi_statement_tuple{ .name = "set_view", .func = statements.agi_set_view, .arity = 2 },
    agi_statement_tuple{ .name = "set_view_v", .func = statements.agi_set_view_v, .arity = 2 },
    agi_statement_tuple{ .name = "set_loop", .func = statements.agi_set_loop, .arity = 2 },
    agi_statement_tuple{ .name = "set_loop_v", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "fix_loop", .func = statements.agi_fix_loop, .arity = 1 },
    agi_statement_tuple{ .name = "release_loop", .func = statements.agi_release_loop, .arity = 1 },
    agi_statement_tuple{ .name = "set_cel", .func = statements.agi_set_cel, .arity = 2 },
    agi_statement_tuple{ .name = "set_cel_v", .func = statements.agi_set_cel_v, .arity = 2 },
    agi_statement_tuple{ .name = "last_cel", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "current_cel", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "current_loop", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "current_view", .func = statements.agi_currentview, .arity = 2 },
    agi_statement_tuple{ .name = "number_of_loops", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "set_priority", .func = statements.agi_set_priority, .arity = 2 },
    agi_statement_tuple{ .name = "set_priority_v", .func = statements.agi_set_priority_v, .arity = 2 },
    agi_statement_tuple{ .name = "release_priority", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "get_priority", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "stop_update", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "start_update", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "force_update", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "ignore_horizon", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "observe_horizon", .func = statements.agi_observe_horizon, .arity = 1 },
    agi_statement_tuple{ .name = "set_horizon", .func = statements.agi_set_horizon, .arity = 1 },
    agi_statement_tuple{ .name = "object_on_water", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "object_on_land", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "object_on_anything", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "ignore_objs", .func = statements.agi_ignore_objs, .arity = 1 },
    agi_statement_tuple{ .name = "observe_objs", .func = statements.agi_observe_objs, .arity = 1 },
    agi_statement_tuple{ .name = "distance", .func = statements.agi_unimplemented, .arity = 3 },
    agi_statement_tuple{ .name = "stop_cycling", .func = statements.agi_stop_cycling, .arity = 1 },
    agi_statement_tuple{ .name = "start_cycling", .func = statements.agi_start_cycling, .arity = 1 },
    agi_statement_tuple{ .name = "normal_cycle", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "end_of_loop", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "reverse_cycle", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "reverse_loop", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "cycle_time", .func = statements.agi_cycle_time, .arity = 2 },
    agi_statement_tuple{ .name = "stop_motion", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "start_motion", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "step_size", .func = statements.agi_step_size, .arity = 2 },
    agi_statement_tuple{ .name = "step_time", .func = statements.agi_step_time, .arity = 2 },
    agi_statement_tuple{ .name = "move_obj", .func = statements.agi_move_obj, .arity = 5 },
    agi_statement_tuple{ .name = "move_obj_v", .func = statements.agi_unimplemented, .arity = 5 },
    agi_statement_tuple{ .name = "follow_ego", .func = statements.agi_unimplemented, .arity = 3 },
    agi_statement_tuple{ .name = "wander", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "normal_motion", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "set_dir", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "get_dir", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "ignore_blocks", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "observe_blocks", .func = statements.agi_observe_blocks, .arity = 1 },
    agi_statement_tuple{ .name = "block", .func = statements.agi_unimplemented, .arity = 4 },
    agi_statement_tuple{ .name = "unblock", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "get", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "get_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "drop", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "put", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "put_v", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "get_room_v", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "load_sound", .func = statements.agi_load_sound, .arity = 1 },
    agi_statement_tuple{ .name = "sound", .func = statements.agi_sound, .arity = 2 },
    agi_statement_tuple{ .name = "stop_sound", .func = statements.agi_stop_sound, .arity = 0 },
    agi_statement_tuple{ .name = "print", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "print_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "display", .func = statements.agi_display, .arity = 3 },
    agi_statement_tuple{ .name = "display_v", .func = statements.agi_display_v, .arity = 3 },
    agi_statement_tuple{ .name = "clear_lines", .func = statements.agi_clear_lines, .arity = 3 },
    agi_statement_tuple{ .name = "text_screen", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "graphics", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "set_cursor_char", .func = statements.agi_nop, .arity = 1 },
    agi_statement_tuple{ .name = "set_text_attribute", .func = statements.agi_nop, .arity = 2 },
    agi_statement_tuple{ .name = "shake_screen", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "configure_screen", .func = statements.agi_nop, .arity = 3 },
    agi_statement_tuple{ .name = "status_line_on", .func = statements.agi_nop, .arity = 0 },
    agi_statement_tuple{ .name = "status_line_off", .func = statements.agi_nop, .arity = 0 },
    agi_statement_tuple{ .name = "set_string", .func = statements.agi_nop, .arity = 2 },
    agi_statement_tuple{ .name = "get_string", .func = statements.agi_unimplemented, .arity = 5 },
    agi_statement_tuple{ .name = "word_to_string", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "parse", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "get_num", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "prevent_input", .func = statements.agi_prevent_input, .arity = 0 },
    agi_statement_tuple{ .name = "accept_input", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "set_key", .func = statements.agi_nop, .arity = 3 },
    agi_statement_tuple{ .name = "add_to_pic", .func = statements.agi_add_to_pic, .arity = 7 },
    agi_statement_tuple{ .name = "add_to_pic_v", .func = statements.agi_add_to_pic_v, .arity = 7 },
    agi_statement_tuple{ .name = "status", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "save_game", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "restore_game - do nothing", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "init_disk - do nothing", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "restart_game", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "show_obj", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "random", .func = statements.agi_unimplemented, .arity = 3 },
    agi_statement_tuple{ .name = "program_control", .func = statements.agi_program_control, .arity = 0 },
    agi_statement_tuple{ .name = "player_control", .func = statements.agi_player_control, .arity = 0 },
    agi_statement_tuple{ .name = "obj_status_v - do nothing", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "quit", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "show_mem - do nothing", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "pause", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "echo_line", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "cancel_line", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "init_joy - do nothing", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "toggle_monitor", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "version", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "script_size", .func = statements.agi_nop, .arity = 1 },
    agi_statement_tuple{ .name = "set_game_id", .func = statements.agi_nop, .arity = 1 },
    agi_statement_tuple{ .name = "log", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "set_scan_start", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "reset_scan_start", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "reposition_to", .func = statements.agi_reposition_to, .arity = 3 },
    agi_statement_tuple{ .name = "reposition_to_v", .func = statements.agi_reposition_to_v, .arity = 3 },
    agi_statement_tuple{ .name = "trace_on", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "trace_info", .func = statements.agi_nop, .arity = 3 },
    agi_statement_tuple{ .name = "print_at", .func = statements.agi_unimplemented, .arity = 4 },
    agi_statement_tuple{ .name = "print_at_v", .func = statements.agi_unimplemented, .arity = 4 },
    agi_statement_tuple{ .name = "discard_view_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "clear_text_rect", .func = statements.agi_unimplemented, .arity = 5 },
    agi_statement_tuple{ .name = "set_upper_left", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "set_menu", .func = statements.agi_nop, .arity = 1 },
    agi_statement_tuple{ .name = "set_menu_member", .func = statements.agi_nop, .arity = 2 }, // set_menu_item (aka)
    agi_statement_tuple{ .name = "submit_menu", .func = statements.agi_nop, .arity = 0 },
    agi_statement_tuple{ .name = "enable_member", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "disable_member", .func = statements.agi_nop, .arity = 1 },
    agi_statement_tuple{ .name = "menu_input", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "show_obj_v", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "open_dialogue", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "close_dialogue", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "mul_n", .func = statements.agi_muln, .arity = 2 },
    agi_statement_tuple{ .name = "mul_v", .func = statements.agi_mulv, .arity = 2 },
    agi_statement_tuple{ .name = "div_n", .func = statements.agi_divn, .arity = 2 },
    agi_statement_tuple{ .name = "div_v", .func = statements.agi_divv, .arity = 2 },
    agi_statement_tuple{ .name = "close_window", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "set_simple", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "push_script", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "pop_script", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "hold_key", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "set_pri_base", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "discard_sound", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "hide_mouse", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "allow_menu", .func = statements.agi_unimplemented, .arity = 1 },
    agi_statement_tuple{ .name = "show_mouse", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "fence_mouse", .func = statements.agi_unimplemented, .arity = 4 },
    agi_statement_tuple{ .name = "mouse_posn", .func = statements.agi_unimplemented, .arity = 2 },
    agi_statement_tuple{ .name = "release_key", .func = statements.agi_unimplemented, .arity = 0 },
    agi_statement_tuple{ .name = "adj_ego_move_to_xy", .func = statements.agi_unimplemented, .arity = 0 },
};
