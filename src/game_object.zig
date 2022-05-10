pub const MovementFlags = enum { Normal, ChaseEgo, Wander, MoveTo };

pub const Direction = enum(u8) { Stopped = 0, Up = 1, UpRight = 2, Right = 3, DownRight = 4, Down = 5, DownLeft = 6, Left = 7, UpLeft = 8 };

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
    // callAtEndOfLoop: bool,
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
};
