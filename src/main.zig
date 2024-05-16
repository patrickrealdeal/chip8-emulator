const std = @import("std");
const c = @import("c.zig");
const Chip8 = @import("chip8.zig");
const process = std.process;

// Window
var window: ?*c.SDL_Window = null;
var renderer: ?*c.SDL_Renderer = null;
var texture: ?*c.SDL_Texture = null;

// AUDIO
const amplitude = 0.5;
const frequency = 440;
const sampleRate = 44100;

var want: c.SDL_AudioSpec = undefined;
var have: c.SDL_AudioSpec = undefined;
var dev: c.SDL_AudioDeviceID = undefined;

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
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        @panic("Failed to initialize SDL.");
    }

    // Window setup
    window = c.SDL_CreateWindow("CHIP8 EMULATOR", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 1024, 512, 0);
    if (window == null) {
        @panic("Failed to create window.");
    }

    // Renderer setup
    renderer = c.SDL_CreateRenderer(window, -1, 0);
    if (renderer == null) {
        @panic("Failed to create renderer.");
    }

    // This represents our screen
    texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, 64, 32);
    if (texture == null) {
        @panic("Failed to create texture.");
    }

    // AUDIO INIT
    if (c.SDL_Init(c.SDL_INIT_AUDIO) != 0) {
        @panic("Failed to initialize SDL.");
    }

    const spec = c.SDL_AudioSpec{
        .freq = sampleRate,
        .format = c.AUDIO_F32SYS,
        .channels = 1,
        .samples = 1024,
        .callback = null,
        .userdata = null,
    };

    dev = c.SDL_OpenAudioDevice(null, 0, &spec, null, 0);
    if (dev == 0) {
        std.debug.print("Failed to open audio: {s}\n", .{c.SDL_GetError()});
        std.process.exit(0);
    }

    std.debug.print("ALL SYSTEMS ARE INITIALIZED!\n", .{});
}

pub fn deinit() void {
    c.SDL_DestroyRenderer(renderer);
    c.SDL_DestroyWindow(window);
    c.SDL_CloseAudioDevice(dev);
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
            bytes_c[y * 64 + x] = if (system.graphics[y * 64 + x] == 1) 0xB3ECECFF else 0x3BD6C6FF;
        }
    }
    c.SDL_UnlockTexture(texture);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    cpu = try allocator.create(Chip8);
    defer allocator.destroy(cpu);

    try cpu.init();

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

    var previous_time = std.time.milliTimestamp();
    const cycle_delay = 5;

    // Generate samples for a simple sine wave
    var data = try allocator.alloc(f32, sampleRate);
    defer allocator.free(data);
    for (0..sampleRate) |i| {
        data[i] = amplitude * @sin(2 * std.math.pi * frequency * @as(f32, @floatFromInt(i)) / sampleRate);
    }

    var open = true;
    while (open) {
        // Emulator cycle
        const current_time = std.time.milliTimestamp();
        const elapsed_time = current_time - previous_time;
        if (elapsed_time >= cycle_delay) {
            previous_time = current_time;

            try cpu.cycle();

            // Rendering
            _ = c.SDL_RenderClear(renderer);

            // Build Texture
            buildTexture(cpu);

            var dest = c.SDL_Rect{ .x = 0, .y = 0, .w = 1024, .h = 512 };

            _ = c.SDL_RenderCopy(renderer, texture, null, &dest);
            _ = c.SDL_RenderPresent(renderer);

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

            if (cpu.delay_timer > 0) {
                cpu.delay_timer -= 1;
            }
            if (cpu.sound_timer > 0) {
                _ = c.SDL_QueueAudio(dev, data.ptr, sampleRate * @sizeOf(f32));
                c.SDL_PauseAudioDevice(dev, 0);
                cpu.sound_timer -= 1;
            } else {
                c.SDL_PauseAudioDevice(dev, 1);
            }
        }

        const target_time = previous_time + (1000 / 60);
        if (current_time < target_time) {
            std.time.sleep(@as(u64, @intCast(target_time - current_time)));
        }
    }
}
