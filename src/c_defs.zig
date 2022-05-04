pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/time.h");

    @cInclude("math.h");
});
