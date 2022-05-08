pub const agi_test_tuple = struct {
    name: []const u8,
    arity: i8,
};

// TODO: turn these into usable enum definitions from Zig-land.

// /**
//  * AGI variables. (VM dedicated Vars Pulled from ScummVM)
//  */
// enum {
// 	VM_VAR_CURRENT_ROOM = 0,        // 0
// 	VM_VAR_PREVIOUS_ROOM,           // 1
// 	VM_VAR_BORDER_TOUCH_EGO,        // 2
// 	VM_VAR_SCORE,                   // 3
// 	VM_VAR_BORDER_CODE,             // 4
// 	VM_VAR_BORDER_TOUCH_OBJECT,     // 5
// 	VM_VAR_EGO_DIRECTION,           // 6
// 	VM_VAR_MAX_SCORE,               // 7
// 	VM_VAR_FREE_PAGES,              // 8
// 	VM_VAR_WORD_NOT_FOUND,          // 9
// 	VM_VAR_TIME_DELAY,              // 10
// 	VM_VAR_SECONDS,                 // 11
// 	VM_VAR_MINUTES,                 // 12
// 	VM_VAR_HOURS,                   // 13
// 	VM_VAR_DAYS,                    // 14
// 	VM_VAR_JOYSTICK_SENSITIVITY,    // 15
// 	VM_VAR_EGO_VIEW_RESOURCE,       // 16
// 	VM_VAR_AGI_ERROR_CODE,          // 17
// 	VM_VAR_AGI_ERROR_INFO,          // 18
// 	VM_VAR_KEY,                     // 19
// 	VM_VAR_COMPUTER,                // 20
// 	VM_VAR_WINDOW_AUTO_CLOSE_TIMER, // 21
// 	VM_VAR_SOUNDGENERATOR,          // 22
// 	VM_VAR_VOLUME,                  // 23
// 	VM_VAR_MAX_INPUT_CHARACTERS,    // 24
// 	VM_VAR_SELECTED_INVENTORY_ITEM, // 25
// 	VM_VAR_MONITOR = 26,            // 26
// 	VM_VAR_MOUSE_BUTTONSTATE = 27,  // 27
// 	VM_VAR_MOUSE_X = 28,            // 28
// 	VM_VAR_MOUSE_Y = 29             // 29
// };

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

// Test/Statement commands also cross-referenced with:
// * https://github.com/r1sc/agi.js/blob/master/Interpreter.ts
// * https://github.com/sonneveld/nagi/blob/master/src/logic/cmd_table.c (more complete reference it would seem)

pub const agi_tests = [_]agi_test_tuple{
    agi_test_tuple{ .name = "equaln", .arity = 2 },
    agi_test_tuple{ .name = "equalv", .arity = 2 },
    agi_test_tuple{ .name = "lessn", .arity = 2 },
    agi_test_tuple{ .name = "lessv", .arity = 2 },
    agi_test_tuple{ .name = "greatern", .arity = 2 },
    agi_test_tuple{ .name = "greaterv", .arity = 2 },
    agi_test_tuple{ .name = "isset", .arity = 1 },
    agi_test_tuple{ .name = "issetv", .arity = 1 },
    agi_test_tuple{ .name = "has", .arity = 1 },
    agi_test_tuple{ .name = "obj_in_room", .arity = 2 },
    agi_test_tuple{ .name = "posn", .arity = 5 },
    agi_test_tuple{ .name = "controller", .arity = 1 },
    agi_test_tuple{ .name = "have_key", .arity = 0 },
    agi_test_tuple{ .name = "said", .arity = -1 }, // NOTE: this is dynamic args.
    agi_test_tuple{ .name = "compare_strings", .arity = 2 },
    agi_test_tuple{ .name = "obj_in_box", .arity = 5 },
    agi_test_tuple{ .name = "center_posn", .arity = 5 },
    agi_test_tuple{ .name = "right_posn", .arity = 5 },
    agi_test_tuple{ .name = "unknown.19", .arity = 5 },
};

pub const agi_statement_tuple = struct {
    name: []const u8,
    arity: i8,
};

pub const agi_statements = [_]agi_statement_tuple{
    agi_statement_tuple{ .name = "return", .arity = 0 },
    agi_statement_tuple{ .name = "increment", .arity = 1 },
    agi_statement_tuple{ .name = "decrement", .arity = 1 },
    agi_statement_tuple{ .name = "assignn", .arity = 2 },
    agi_statement_tuple{ .name = "assignv", .arity = 2 },
    agi_statement_tuple{ .name = "addn", .arity = 2 },
    agi_statement_tuple{ .name = "addv", .arity = 2 },
    agi_statement_tuple{ .name = "subn", .arity = 2 },
    agi_statement_tuple{ .name = "subv", .arity = 2 },
    agi_statement_tuple{ .name = "lindirectv", .arity = 2 },
    agi_statement_tuple{ .name = "rindirect", .arity = 2 },
    agi_statement_tuple{ .name = "lindirectn", .arity = 2 },
    agi_statement_tuple{ .name = "set", .arity = 1 },
    agi_statement_tuple{ .name = "reset", .arity = 1 },
    agi_statement_tuple{ .name = "toggle", .arity = 1 },
    agi_statement_tuple{ .name = "set_v", .arity = 1 },
    agi_statement_tuple{ .name = "reset_v", .arity = 1 },
    agi_statement_tuple{ .name = "toggle_v", .arity = 1 },
    agi_statement_tuple{ .name = "new_room", .arity = 1 },
    agi_statement_tuple{ .name = "new_room_v", .arity = 1 },
    agi_statement_tuple{ .name = "load_logic", .arity = 1 },
    agi_statement_tuple{ .name = "load_logic_v", .arity = 1 },
    agi_statement_tuple{ .name = "call", .arity = 1 },
    agi_statement_tuple{ .name = "call_v", .arity = 1 },
    agi_statement_tuple{ .name = "load_pic", .arity = 1 },
    agi_statement_tuple{ .name = "draw_pic", .arity = 1 },
    agi_statement_tuple{ .name = "show_pic", .arity = 0 },
    agi_statement_tuple{ .name = "discard_pic", .arity = 1 },
    agi_statement_tuple{ .name = "overlay_pic", .arity = 1 },
    agi_statement_tuple{ .name = "show_pri_screen", .arity = 0 },
    agi_statement_tuple{ .name = "load_view", .arity = 1 },
    agi_statement_tuple{ .name = "load_view_v", .arity = 1 },
    agi_statement_tuple{ .name = "discard_view", .arity = 1 },
    agi_statement_tuple{ .name = "animate_obj", .arity = 1 },
    agi_statement_tuple{ .name = "unanimate_all", .arity = 0 },
    agi_statement_tuple{ .name = "draw", .arity = 1 },
    agi_statement_tuple{ .name = "erase", .arity = 1 },
    agi_statement_tuple{ .name = "position", .arity = 3 },
    agi_statement_tuple{ .name = "position_v", .arity = 3 },
    agi_statement_tuple{ .name = "get_posn", .arity = 3 },
    agi_statement_tuple{ .name = "reposition", .arity = 3 },
    agi_statement_tuple{ .name = "set_view", .arity = 2 },
    agi_statement_tuple{ .name = "set_view_v", .arity = 2 },
    agi_statement_tuple{ .name = "set_loop", .arity = 2 },
    agi_statement_tuple{ .name = "set_loop_v", .arity = 2 },
    agi_statement_tuple{ .name = "fix_loop", .arity = 1 },
    agi_statement_tuple{ .name = "release_loop", .arity = 1 },
    agi_statement_tuple{ .name = "set_cel", .arity = 2 },
    agi_statement_tuple{ .name = "set_cel_v", .arity = 2 },
    agi_statement_tuple{ .name = "last_cel", .arity = 2 },
    agi_statement_tuple{ .name = "current_cel", .arity = 2 },
    agi_statement_tuple{ .name = "current_loop", .arity = 2 },
    agi_statement_tuple{ .name = "current_view", .arity = 2 },
    agi_statement_tuple{ .name = "number_of_loops", .arity = 2 },
    agi_statement_tuple{ .name = "set_priority", .arity = 2 },
    agi_statement_tuple{ .name = "set_priority_v", .arity = 2 },
    agi_statement_tuple{ .name = "release_priority", .arity = 1 },
    agi_statement_tuple{ .name = "get_priority", .arity = 2 },
    agi_statement_tuple{ .name = "stop_update", .arity = 1 },
    agi_statement_tuple{ .name = "start_update", .arity = 1 },
    agi_statement_tuple{ .name = "force_update", .arity = 1 },
    agi_statement_tuple{ .name = "ignore_horizon", .arity = 1 },
    agi_statement_tuple{ .name = "observe_horizon", .arity = 1 },
    agi_statement_tuple{ .name = "set_horizon", .arity = 1 },
    agi_statement_tuple{ .name = "object_on_water", .arity = 1 },
    agi_statement_tuple{ .name = "object_on_land", .arity = 1 },
    agi_statement_tuple{ .name = "object_on_anything", .arity = 1 },
    agi_statement_tuple{ .name = "ignore_objs", .arity = 1 },
    agi_statement_tuple{ .name = "observe_objs", .arity = 1 },
    agi_statement_tuple{ .name = "distance", .arity = 3 },
    agi_statement_tuple{ .name = "stop_cycling", .arity = 1 },
    agi_statement_tuple{ .name = "start_cycling", .arity = 1 },
    agi_statement_tuple{ .name = "normal_cycle", .arity = 1 },
    agi_statement_tuple{ .name = "end_of_loop", .arity = 2 },
    agi_statement_tuple{ .name = "reverse_cycle", .arity = 1 },
    agi_statement_tuple{ .name = "reverse_loop", .arity = 2 },
    agi_statement_tuple{ .name = "cycle_time", .arity = 2 },
    agi_statement_tuple{ .name = "stop_motion", .arity = 1 },
    agi_statement_tuple{ .name = "start_motion", .arity = 1 },
    agi_statement_tuple{ .name = "step_size", .arity = 2 },
    agi_statement_tuple{ .name = "step_time", .arity = 2 },
    agi_statement_tuple{ .name = "move_obj", .arity = 5 },
    agi_statement_tuple{ .name = "move_obj_v", .arity = 5 },
    agi_statement_tuple{ .name = "follow_ego", .arity = 3 },
    agi_statement_tuple{ .name = "wander", .arity = 1 },
    agi_statement_tuple{ .name = "normal_motion", .arity = 1 },
    agi_statement_tuple{ .name = "set_dir", .arity = 2 },
    agi_statement_tuple{ .name = "get_dir", .arity = 2 },
    agi_statement_tuple{ .name = "ignore_blocks", .arity = 1 },
    agi_statement_tuple{ .name = "observe_blocks", .arity = 1 },
    agi_statement_tuple{ .name = "block", .arity = 4 },
    agi_statement_tuple{ .name = "unblock", .arity = 0 },
    agi_statement_tuple{ .name = "get", .arity = 1 },
    agi_statement_tuple{ .name = "get_v", .arity = 1 },
    agi_statement_tuple{ .name = "drop", .arity = 1 },
    agi_statement_tuple{ .name = "put", .arity = 2 },
    agi_statement_tuple{ .name = "put_v", .arity = 2 },
    agi_statement_tuple{ .name = "get_room_v", .arity = 2 },
    agi_statement_tuple{ .name = "load_sound", .arity = 1 },
    agi_statement_tuple{ .name = "sound", .arity = 2 },
    agi_statement_tuple{ .name = "stop_sound", .arity = 0 },
    agi_statement_tuple{ .name = "print", .arity = 1 },
    agi_statement_tuple{ .name = "print_v", .arity = 1 },
    agi_statement_tuple{ .name = "display", .arity = 3 },
    agi_statement_tuple{ .name = "display_v", .arity = 3 },
    agi_statement_tuple{ .name = "clear_lines", .arity = 3 },
    agi_statement_tuple{ .name = "text_screen", .arity = 0 },
    agi_statement_tuple{ .name = "graphics", .arity = 0 },
    agi_statement_tuple{ .name = "set_cursor_char", .arity = 1 },
    agi_statement_tuple{ .name = "set_text_attribute", .arity = 2 },
    agi_statement_tuple{ .name = "shake_screen", .arity = 1 },
    agi_statement_tuple{ .name = "configure_screen", .arity = 3 },
    agi_statement_tuple{ .name = "status_line_on", .arity = 0 },
    agi_statement_tuple{ .name = "status_line_off", .arity = 0 },
    agi_statement_tuple{ .name = "set_string", .arity = 2 },
    agi_statement_tuple{ .name = "get_string", .arity = 5 },
    agi_statement_tuple{ .name = "word_to_string", .arity = 2 },
    agi_statement_tuple{ .name = "parse", .arity = 1 },
    agi_statement_tuple{ .name = "get_num", .arity = 2 },
    agi_statement_tuple{ .name = "prevent_input", .arity = 0 },
    agi_statement_tuple{ .name = "accept_input", .arity = 0 },
    agi_statement_tuple{ .name = "set_key", .arity = 3 },
    agi_statement_tuple{ .name = "add_to_pic", .arity = 7 },
    agi_statement_tuple{ .name = "add_to_pic_v", .arity = 7 },
    agi_statement_tuple{ .name = "status", .arity = 0 },
    agi_statement_tuple{ .name = "save_game", .arity = 0 },
    agi_statement_tuple{ .name = "restore_game - do nothing", .arity = 0 },
    agi_statement_tuple{ .name = "init_disk - do nothing", .arity = 0 },
    agi_statement_tuple{ .name = "restart_game", .arity = 0 },
    agi_statement_tuple{ .name = "show_obj", .arity = 1 },
    agi_statement_tuple{ .name = "random", .arity = 3 },
    agi_statement_tuple{ .name = "program_control", .arity = 0 },
    agi_statement_tuple{ .name = "player_control", .arity = 0 },
    agi_statement_tuple{ .name = "obj_status_v - do nothing", .arity = 1 },
    agi_statement_tuple{ .name = "quit", .arity = 1 },
    agi_statement_tuple{ .name = "show_mem - do nothing", .arity = 0 },
    agi_statement_tuple{ .name = "pause", .arity = 0 },
    agi_statement_tuple{ .name = "echo_line", .arity = 0 },
    agi_statement_tuple{ .name = "cancel_line", .arity = 0 },
    agi_statement_tuple{ .name = "init_joy - do nothing", .arity = 0 },
    agi_statement_tuple{ .name = "toggle_monitor", .arity = 0 },
    agi_statement_tuple{ .name = "version", .arity = 0 },
    agi_statement_tuple{ .name = "script_size", .arity = 1 },
    agi_statement_tuple{ .name = "set_game_id", .arity = 1 },
    agi_statement_tuple{ .name = "log", .arity = 1 },
    agi_statement_tuple{ .name = "set_scan_start", .arity = 0 },
    agi_statement_tuple{ .name = "reset_scan_start", .arity = 0 },
    agi_statement_tuple{ .name = "reposition_to", .arity = 3 },
    agi_statement_tuple{ .name = "reposition_to_v", .arity = 3 },
    agi_statement_tuple{ .name = "trace_on", .arity = 0 },
    agi_statement_tuple{ .name = "trace_info", .arity = 3 },
    agi_statement_tuple{ .name = "print_at", .arity = 4 },
    agi_statement_tuple{ .name = "print_at_v", .arity = 4 },
    agi_statement_tuple{ .name = "discard_view_v", .arity = 1 },
    agi_statement_tuple{ .name = "clear_text_rect", .arity = 5 },
    agi_statement_tuple{ .name = "set_upper_left", .arity = 2 },
    agi_statement_tuple{ .name = "set_menu", .arity = 1 },
    agi_statement_tuple{ .name = "set_menu_member", .arity = 2 }, // set_menu_item (aka)
    agi_statement_tuple{ .name = "submit_menu", .arity = 0 },
    agi_statement_tuple{ .name = "enable_member", .arity = 1 },
    agi_statement_tuple{ .name = "disable_member", .arity = 1 },
    agi_statement_tuple{ .name = "menu_input", .arity = 0 },
    agi_statement_tuple{ .name = "show_obj_v", .arity = 1 },
    agi_statement_tuple{ .name = "open_dialogue", .arity = 0 },
    agi_statement_tuple{ .name = "close_dialogue", .arity = 0 },
    agi_statement_tuple{ .name = "mul_n", .arity = 2 },
    agi_statement_tuple{ .name = "mul_v", .arity = 2 },
    agi_statement_tuple{ .name = "div_n", .arity = 2 },
    agi_statement_tuple{ .name = "div_v", .arity = 2 },
    agi_statement_tuple{ .name = "close_window", .arity = 0 },

    agi_statement_tuple{ .name = "set_simple", .arity = 1 },
    agi_statement_tuple{ .name = "push_script", .arity = 0 },
    agi_statement_tuple{ .name = "pop_script", .arity = 0 },
    agi_statement_tuple{ .name = "hold_key", .arity = 0 },
    agi_statement_tuple{ .name = "set_pri_base", .arity = 1 },
    agi_statement_tuple{ .name = "discard_sound", .arity = 1 },
    agi_statement_tuple{ .name = "hide_mouse", .arity = 0 },
    agi_statement_tuple{ .name = "allow_menu", .arity = 1 },
    agi_statement_tuple{ .name = "show_mouse", .arity = 0 },
    agi_statement_tuple{ .name = "fence_mouse", .arity = 4 },
    agi_statement_tuple{ .name = "mouse_posn", .arity = 2 },
    agi_statement_tuple{ .name = "release_key", .arity = 0 },
    agi_statement_tuple{ .name = "adj_ego_move_to_xy", .arity = 0 },
};
