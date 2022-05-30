pub const MovementFlags = enum { Normal, ChaseEgo, Wander, MoveTo };

pub const Direction = enum(u8) { Stopped = 0, Up = 1, UpRight = 2, Right = 3, DownRight = 4, Down = 5, DownLeft = 6, Left = 7, UpLeft = 8 };

// Bit flags from Scummvm
// enum ViewFlags {
// 	fDrawn          = (1 << 0),     // 0x0001
// 	fIgnoreBlocks   = (1 << 1),     // 0x0002
// 	fFixedPriority  = (1 << 2),     // 0x0004
// 	fIgnoreHorizon  = (1 << 3),     // 0x0008
// 	fUpdate         = (1 << 4),     // 0x0010
// 	fCycling        = (1 << 5),     // 0x0020
// 	fAnimated       = (1 << 6),     // 0x0040
// 	fMotion         = (1 << 7),     // 0x0080
// 	fOnWater        = (1 << 8),     // 0x0100
// 	fIgnoreObjects  = (1 << 9),     // 0x0200
// 	fUpdatePos      = (1 << 10),    // 0x0400
// 	fOnLand         = (1 << 11),    // 0x0800
// 	fDontupdate     = (1 << 12),    // 0x1000
// 	fFixLoop        = (1 << 13),    // 0x2000
// 	fDidntMove      = (1 << 14),    // 0x4000
// 	fAdjEgoXY       = (1 << 15)     // 0x8000
// };

pub const GameObject = struct {
    x: u8,
    y: u8,
    draw: bool,
    // redraw: bool,
    direction: Direction, // = Direction.Stopped;
    viewNo: u8,
    loop: u8,
    cel: u8,
    fixedLoop: bool,
    priority: u8,
    fixedPriority: bool,
    reverseCycle: bool,
    cycleTime: u8,
    celCycling: bool,
    callAtEndOfLoop: bool,
    flagToSetWhenFinished: u8,
    ignoreHorizon: bool,
    ignoreBlocks: bool,
    ignoreObjs: bool,
    motion: bool,
    stepSize: u8,
    stepTime: u8,

    moveToX: u8,
    moveToY: u8,
    moveToStep: u8,

    movementFlag: MovementFlags, // = MovementFlags.Normal;

    follow_count: u8 = 0,
    wander_count: u8 = 0,

    // allowedSurface: number = 0;
    update: bool,
    // reverseLoop: boolean = false;
    nextCycle: u8,

    oldX: u8, // number = 0;
    oldY: u8, //number = 0;
    // nextLoop: number = 0;
    // nextCel: number = 0;
    // oldLoop: number = 0;
    // oldCel: number = 0;
    // oldView: number = 0;
    // oldPriority: number = 0;
    // oldDrawX: number = 0;
    // oldDrawY: number = 0;

    pub fn init() GameObject {
        return GameObject{
            .x = 0,
            .y = 0,
            .draw = false,
            .direction = Direction.Stopped,
            .viewNo = 0,
            .loop = 0,
            .cel = 0,
            .fixedLoop = false,
            .priority = 0,
            .fixedPriority = false,
            .reverseCycle = false,
            .cycleTime = 1,
            .celCycling = false,
            .callAtEndOfLoop = false,
            .flagToSetWhenFinished = 0,
            .ignoreHorizon = false,
            .ignoreBlocks = false,
            .ignoreObjs = false,
            .motion = false,
            .stepSize = 1,
            .stepTime = 0, // scumm has this as 1 and another field called: stepTimeCount = 1

            .moveToX = 0,
            .moveToY = 0,
            .moveToStep = 0,

            .movementFlag = MovementFlags.Normal,

            .update = true,
            .nextCycle = 1,

            .oldX = 0,
            .oldY = 0,
        };
    }
};
