const std = @import("std");
const Allocator = std.mem.Allocator;
const test_allocator = std.testing.allocator;

const c = @import("c_defs.zig").c;

pub const soundSetSize = 4;

pub const ResourceTag = enum {
    Font,
    MusicStream,
    Shader,
    Sound,
    SoundSet,
    Texture,
};

pub const Resource = union(ResourceTag) {
    Texture: c.Texture,
    Sound: c.Sound,
    SoundSet: [soundSetSize]c.Sound,
    Font: c.Font,
    Shader: c.Shader,
    MusicStream: c.Music,
};

pub const ResourceEntity = struct {
    resource: Resource,
};

pub const ResourceKey = struct {
    file_type: ResourceTag,
    file_path: []const u8,
};

pub fn WithKey(file_type: ResourceTag, file_path: []const u8) ResourceKey {
    return ResourceKey{
        .file_type = file_type,
        .file_path = file_path,
    };
}

pub const ResourceManager = struct {
    allocator: Allocator,
    internal2: std.StringHashMap(ResourceEntity),

    pub fn init(allocator: Allocator) ResourceManager {
        const map2 = std.StringHashMap(ResourceEntity).init(allocator);

        return ResourceManager{
            .allocator = allocator,
            .internal2 = map2,
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        var iter = self.internal2.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*.resource) {
                .Texture => {
                    std.log.info("About to unload texture {s}", .{@TypeOf(entry.value_ptr)});
                    c.UnloadTexture(entry.value_ptr.*.resource.Texture);
                },
                .Sound => {
                    std.log.info("About to unload sound {s}", .{@TypeOf(entry.value_ptr)});
                    c.UnloadSound(entry.value_ptr.*.resource.Sound);
                },
                .Font => {
                    std.log.info("About to unload font {s}", .{@TypeOf(entry.value_ptr)});
                    c.UnloadFont(entry.value_ptr.*.resource.Font);
                },
                .Shader => {
                    std.log.info("About to unload shader {s}", .{@TypeOf(entry.value_ptr)});
                    c.UnloadShader(entry.value_ptr.*.resource.Shader);
                },
                .MusicStream => {
                    std.log.info("About to unload music stream {s}", .{@TypeOf(entry.value_ptr)});
                    c.UnloadMusicStream(entry.value_ptr.*.resource.MusicStream);
                },
                .SoundSet => {
                    std.log.info("About to unload sound set {s}", .{@TypeOf(entry.value_ptr)});
                    for (entry.value_ptr.*.resource.SoundSet) |snd, idx| {
                        std.log.info("unloading sound set:{d} {s}", .{ idx, @TypeOf(entry.value_ptr) });
                        c.UnloadSound(snd);
                    }
                },
            }
        }

        // Lastly deinit the map itself.
        self.internal2.deinit();
    }

    pub fn add_shader(self: *ResourceManager, key: ResourceKey) anyerror!c.Shader {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);

        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            const shd = c.LoadShader(0, cstr);
            gop.value_ptr.* = ResourceEntity{ .resource = Resource{ .Shader = shd } };
            return shd;
        }

        return gop.value_ptr.resource.Shader;
    }

    pub fn add_texture(self: *ResourceManager, key: ResourceKey) anyerror!c.Texture {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);

        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            const texture = c.LoadTexture(cstr);
            gop.value_ptr.* = ResourceEntity{ .resource = Resource{ .Texture = texture } };
            return texture;
        }

        return gop.value_ptr.resource.Texture;
    }

    pub fn add_sound(self: *ResourceManager, key: ResourceKey) anyerror!c.Sound {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);

        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            const snd = c.LoadSound(cstr);
            gop.value_ptr.* = ResourceEntity{ .resource = Resource{ .Sound = snd } };
            return snd;
        }

        return gop.value_ptr.resource.Sound;
    }

    pub fn add_soundset(self: *ResourceManager, key: ResourceKey) anyerror![]c.Sound {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);
        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            // Create a single ResourceEntity for all sounds in a set.
            var re = ResourceEntity{ .resource = Resource{
                .SoundSet = undefined,
            } };

            var i: usize = 0;
            while (i < soundSetSize) : (i += 1) {
                const snd = c.LoadSound(cstr);
                re.resource.SoundSet[i] = snd;
            }

            gop.value_ptr.* = re;

            return re.resource.SoundSet[0..];
        }

        return gop.value_ptr.resource.SoundSet[0..];
    }

    pub fn add_font(self: *ResourceManager, key: ResourceKey, size: usize) anyerror!c.Font {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);

        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            const font = c.LoadFontEx(cstr, @intCast(c_int, size), 0, 0);
            gop.value_ptr.* = ResourceEntity{ .resource = Resource{ .Font = font } };
            return font;
        }

        return gop.value_ptr.resource.Font;
    }

    pub fn add_musicstream(self: *ResourceManager, key: ResourceKey) anyerror!c.Music {
        var tempString = [_]u8{0} ** 300;
        const fmtStr = try std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path });

        const gop = try self.internal2.getOrPut(fmtStr);

        if (!gop.found_existing) {
            errdefer _ = self.internal2.remove(fmtStr);
            gop.key_ptr.* = try self.allocator.dupe(u8, fmtStr);

            // Need to pass a null-terminated proper c-string.
            const cstr = try self.allocator.dupeZ(u8, key.file_path);
            defer self.allocator.free(cstr);

            const ms = c.LoadMusicStream(cstr);
            gop.value_ptr.* = ResourceEntity{ .resource = Resource{ .MusicStream = ms } };
            std.log.info("music stream added...!!!!", .{});
            return ms;
        }

        return gop.value_ptr.resource.MusicStream;
    }

    pub fn ref_texture(self: *ResourceManager, key: ResourceKey) ?c.Texture {
        var buf: [300]u8 = undefined;
        const k = std.fmt.bufPrint(&buf, "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |*foundTexture| {
            return foundTexture.resource.Texture;
        } else {
            //std.log.warn("texture file: {s} is missing!", .{key.file_path});
        }

        return null;
    }

    pub fn updateMusicStream(self: *ResourceManager, key: ResourceKey) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            c.UpdateMusicStream(foundMusicStream.resource.MusicStream);
        }
    }

    pub fn stopMusicStream(self: *ResourceManager, key: ResourceKey) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            c.StopMusicStream(foundMusicStream.resource.MusicStream);
        }
    }

    pub fn playMusicStream(self: *ResourceManager, key: ResourceKey) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            c.PlayMusicStream(foundMusicStream.resource.MusicStream);
        }
    }

    pub fn isMusicStreamPlaying(self: *ResourceManager, key: ResourceKey) bool {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            return (c.IsMusicStreamPlaying(foundMusicStream.resource.MusicStream));
        }
        return false;
    }

    pub fn setMusicStreamVolume(self: *ResourceManager, key: ResourceKey, vol: f32) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            c.SetMusicVolume(foundMusicStream.resource.MusicStream, vol);
        }
    }

    pub fn setMusicStreamPitch(self: *ResourceManager, key: ResourceKey, pitch: f32) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |foundMusicStream| {
            c.SetMusicPitch(foundMusicStream.resource.MusicStream, pitch);
        }
    }

    // Do we really need two different play methods? Why can't we just detect if it's a soundset or not?
    pub fn play_soundset(self: *ResourceManager, key: ResourceKey) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |*foundSoundSet| {
            self.channelPlay(foundSoundSet.resource.SoundSet[0..]);
        } else {
            std.log.warn("sound set file: {s} is missing!", .{key.file_path});
        }
    }

    pub fn play_sound(self: *ResourceManager, key: ResourceKey) void {
        var tempString = [_]u8{0} ** 300;
        const k = std.fmt.bufPrint(tempString[0..], "{d} : {s}", .{ key.file_type, key.file_path }) catch unreachable;

        if (self.internal2.get(k)) |*foundSound| {
            _ = self.singlePlay(&foundSound.resource.Sound);
        } else {
            std.log.warn("sound file: {s} is missing!", .{key.file_path});
        }
    }

    fn channelPlay(self: *ResourceManager, sounds: []c.Sound) void {
        std.log.info("channelPlay...", .{});
        var i: usize = 0;
        while (i < soundSetSize) : (i += 1) {
            if (self.singlePlay(&sounds[i])) {
                std.log.info("singlePlay()...", .{});
                return;
            }
        }
    }

    fn singlePlay(_: *ResourceManager, sound: *c.Sound) bool {
        if (!c.IsSoundPlaying(sound.*)) {
            std.log.info("playing some shiz...", .{});
            c.PlaySound(sound.*);
            return true;
        }
        std.log.info("NOT playing...", .{});
        return false;
    }
};
