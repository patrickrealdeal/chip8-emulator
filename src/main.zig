const std = @import("std");
const c = @import("c.zig");
const process = std.process;
const Chip8 = @import("chip8.zig");

var window: ?*c.SDL_Window = null;
var renderer: ?*c.SDL_Renderer = null;
var texture: ?*c.SDL_Texture = null;

var cpu: *Chip8 = undefined;

const keymap: [16]c_int = [_]c_int{
    c.SDL_SCANCODE_X,
    c.SDL_SCANCODE_1,
    c.SDL_SCANCODE_2,
    c.SDL_SCANCODE_3,
    c.SDL_SCANCODE_Q,
    c.SDL_SCANCODE_W,
    c.SDL_SCANCODE_E,
    c.SDL_SCANCODE_A,
    c.SDL_SCANCODE_S,
    c.SDL_SCANCODE_D,
    c.SDL_SCANCODE_Z,
    c.SDL_SCANCODE_C,
    c.SDL_SCANCODE_4,
    c.SDL_SCANCODE_R,
    c.SDL_SCANCODE_F,
    c.SDL_SCANCODE_V,
};

pub fn init() !void {
    if (c.SDL_Init(1) < 0) { // SLD_VIDEO | SDL_AUDIO
        @panic("Failed to initialize SDL.");
    }

    // Window setup
    window = c.SDL_CreateWindow("CHIP8-EMULATOR", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 1024, 512, 0);
    if (window == null) {
        @panic("Failed to create window.");
    }

    renderer = c.SDL_CreateRenderer(window, -1, 0);
    if (renderer == null) {
        @panic("Failed to create renderer.");
    }

    // This represents our screen
    texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, 64, 32);
    if (texture == null) {
        @panic("Failed to create texture.");
    }
}

pub fn deinit() void {
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

pub fn loadRom(filename: []const u8) !void {
    var input_file = try std.fs.cwd().openFile(filename, .{});
    defer input_file.close();

    const size = try input_file.getEndPos();
    const reader = input_file.reader();

    var i: usize = 0;
    while (i < size) : (i += 1) {
        cpu.memory[i + 0x200] = try reader.readByte();
    }

    std.debug.print("Loading ROM Succeeded!\n", .{});
}

pub fn buildTexture(system: *Chip8) void {
    var bytes: ?*anyopaque = null;
    var pitch: c_int = 0;
    if (c.SDL_LockTexture(texture, null, &bytes, &pitch) != 0) {
        c.SDL_Log("Failed to Lock texture: .{s}\n", c.SDL_GetError());
        return;
    }

    var bytes_c: [*]u32 = @ptrCast(@alignCast(bytes.?));

    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x: usize = 0;
        while (x < 64) : (x += 1) {
            bytes_c[y * 64 + x] = if (system.graphics[y * 64 + x] == 1) 0x3BD6C6FF else 0xB3ECECFF;
        }
    }
    c.SDL_UnlockTexture(texture);
}

pub fn main() !void {
    const slow_factor = 1;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    cpu = try allocator.create(Chip8);
    try cpu.init();
    defer allocator.destroy(cpu);

    // Load  Rom
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const filename = args.next() orelse {
        std.debug.print("\rProvide a ROM for the CHIP8!\n", .{});
        process.exit(1);
    };

    try loadRom(filename);

    try init();
    defer deinit();

    var open = true;
    while (open) {
        // Emulator cycle
        try cpu.cycle();

        // Poll Events
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            switch (e.type) {
                c.SDL_QUIT => open = false,
                c.SDL_KEYDOWN => {
                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 1;
                        }
                    }
                    if (e.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                        open = false;
                    }
                },
                c.SDL_KEYUP => {
                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 0;
                        }
                    }
                },
                else => {},
            }
        }

        // Rendering
        _ = c.SDL_RenderClear(renderer);

        // TODO: Build Texture
        buildTexture(cpu);

        var dest = c.SDL_Rect{ .x = 0, .y = 0, .w = 1024, .h = 512 };

        _ = c.SDL_RenderCopy(renderer, texture, null, &dest);
        _ = c.SDL_RenderPresent(renderer);

        std.time.sleep(16 * 1000 * 1000 * slow_factor); // 60 hz
    }
}
