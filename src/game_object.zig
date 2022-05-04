pub const MovementFlags = enum { Normal, ChaseEgo, Wander, MoveTo };

pub const Direction = enum(u8) { Stopped = 0, Up = 1, UpRight = 2, Right = 3, DownRight = 4, Down = 5, DownLeft = 6, Left = 7, UpLeft = 8 };

pub const GameObject = struct {
    x: u8,
    y: u8,
    draw: bool,
    // redraw: bool,
    // direction: Direction = Direction.Stopped;
    // viewNo: number = 0;
    // loop: number = 0;
    // cel: number = 0;
    // fixedLoop: bool,
    // priority: number = 0;
    // fixedPriority: bool,
    // reverseCycle: bool,
    // cycleTime: number = 1;
    // celCycling: bool,
    // callAtEndOfLoop: bool,
    // flagToSetWhenFinished: number = 0;
    // ignoreHorizon: bool,
    // ignoreBlocks: bool,
    // ignoreObjs: bool,
    // motion: bool,
    // stepSize: number = 1;
    // stepTime: number = 0;

    // moveToX: number = 0;
    // moveToY: number = 0;
    // moveToStep: number = 0;

    // movementFlag: MovementFlags = MovementFlags.Normal;
    // allowedSurface: number = 0;
    update: bool,
    // reverseLoop: boolean = false;
    // nextCycle: number = 1;

    // oldX: number = 0;
    // oldY: number = 0;
    // nextLoop: number = 0;
    // nextCel: number = 0;
    // oldLoop: number = 0;
    // oldCel: number = 0;
    // oldView: number = 0;
    // oldPriority: number = 0;
    // oldDrawX: number = 0;
    // oldDrawY: number = 0;
};
