const std = @import("std");
const cstd = @cImport(@cInclude("stdlib.h"));
const time = @cImport(@cInclude("time.h"));

const Self = @This();

opcode: u16, // 16-bit opcodes
memory: [4096]u8, // 4K bytes of memory
graphics: [64 * 32]u8, // 64x32 monocrome display memory
registers: [16]u8, // 16 8-bit registers
index: u16, // 16-bit index register
program_counter: u16, // 16-bit program counter
delay_timer: u8, // 8-bit delay timer
sound_timer: u8, // 8-bit sound timer
stack: [16]u16, // 16-level stack
sp: u16, // 16-bit stack pointer
keys: [16]u8, // 16 input keys

const chip8_fontset = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pub fn init(self: *Self) !void {
    cstd.srand(@intCast(time.time(0))); // seed
    self.program_counter = 0x200; // start of our memory
    self.opcode = 0x00;
    self.index = 0x00;
    self.sp = 0x00;
    self.delay_timer = 0x00;
    self.sound_timer = 0x00;

    self.graphics = std.mem.zeroes([64 * 32]u8);
    self.memory = std.mem.zeroes([4096]u8);
    self.stack = std.mem.zeroes([16]u16);
    self.keys = std.mem.zeroes([16]u8);
    self.registers = std.mem.zeroes([16]u8);

    for (chip8_fontset, 0..) |c, i| {
        self.memory[i] = c; // loaded in cpu memory space
    }
}

fn incrementPc(self: *Self) void {
    self.program_counter += 2; // intructions are 2 bytes
}

pub fn cycle(self: *Self) !void {
    if (self.program_counter > 0xFFF)
        @panic("OPcode out of range! Your program has an error!");

    self.opcode = @as(u16, @intCast(self.memory[self.program_counter])) << 8 | self.memory[self.program_counter + 1];

    // std.debug.print("{x}\n", .{self.opcode});

    if (self.opcode == 0x00E0) { // clear screen
        self.graphics = std.mem.zeroes([64 * 32]u8);
        self.incrementPc();
    } else if (self.opcode == 0x00EE) { // Return
        self.sp -= 1;
        self.program_counter = self.stack[self.sp];
        self.incrementPc();
    } else {
        // X000
        const first = self.opcode >> 12;
        switch (first) {
            0x0 => {
                std.debug.print("SYS INSTR!\n", .{});
                self.incrementPc();
            }, // Unimplemented system instructions
            0x1 => { // Set program counter to nnn
                self.program_counter = self.opcode & 0x0FFF; // Get the address we need to point to
            },
            // The interpreter increments the stack pointer, then puts the current PC on the top of the stack. The PC is then set to nnn.
            0x2 => {
                self.stack[self.sp] = self.program_counter;
                self.sp += 1;
                self.program_counter = self.opcode & 0x0FFF;
            },
            0x3 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                if (self.registers[x] == self.opcode & 0x00FF) {
                    self.incrementPc();
                }
                self.incrementPc();
            },
            0x4 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                if (self.registers[x] != self.opcode & 0x00FF) {
                    self.incrementPc();
                }
                self.incrementPc();
            },
            0x5 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                const y = (self.opcode & 0x00F0) >> 4;
                if (self.registers[x] == self.registers[y]) {
                    self.incrementPc();
                }
                self.incrementPc();
            },
            0x6 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                self.registers[x] = @truncate(self.opcode & 0x00FF); // ensures kk is loaded in registers
                self.incrementPc();
            },
            0x7 => {
                @setRuntimeSafety(false);
                const x = (self.opcode & 0x0F00) >> 8;
                self.registers[x] += @truncate(self.opcode & 0x00FF);
                self.incrementPc();
            },
            0x8 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                const y = (self.opcode & 0x00F0) >> 4;
                const m = (self.opcode & 0x000F);

                switch (m) {
                    0 => self.registers[x] = self.registers[y],
                    1 => self.registers[x] |= self.registers[y],
                    2 => self.registers[x] &= self.registers[y],
                    3 => self.registers[x] ^= self.registers[y], // xor
                    4 => {
                        @setRuntimeSafety(false);
                        var sum: u16 = self.registers[x];
                        sum += self.registers[y];

                        self.registers[0xF] = if (sum > 255) 1 else 0; // 0xF is the special flag register
                        self.registers[x] = @truncate(sum & 0x00FF); // keep only lowest 8 bits
                    },
                    5 => {
                        @setRuntimeSafety(false);
                        self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1 else 0;
                        self.registers[x] -= self.registers[y];
                    },
                    6 => {
                        self.registers[0xF] = self.registers[x] * 0b00000001; // check least sig bit == 1
                        self.registers[x] >>= 1; // division by 2
                    },
                    7 => {
                        @setRuntimeSafety(false);
                        self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1 else 0;
                        self.registers[x] = self.registers[y] - self.registers[x];
                    },
                    0xE => {
                        self.registers[0xF] = if (self.registers[x] & 0x80 != 0) 1 else 0; // check most sig bit is 1
                        self.registers[x] <<= 1; // mult by 2
                    },
                    else => {
                        std.debug.print("CURRENT ALU OP: {x}\n", .{self.opcode});
                    },
                }

                self.incrementPc();
            },
            0x9 => {
                const x = (self.opcode & 0x0F00) >> 8; // shit it to least significant
                const y = (self.opcode & 0x00F0) >> 4;
                if (self.registers[x] != self.registers[y]) {
                    self.incrementPc();
                }
                self.incrementPc();
            },

            0xA => {
                self.index = self.opcode & 0x0FFF;
                self.incrementPc();
            },
            0xB => {
                const v0: u16 = @intCast(self.registers[0]);
                self.program_counter = (self.opcode & 0x0FFF) + v0;
            },
            0xC => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk = self.opcode & 0x00FF;
                self.registers[x] = @as(u8, @truncate(@as(u32, @bitCast(cstd.rand())) & kk));
                self.incrementPc();
            },
            0xD => {
                self.registers[0xF] = 0;
                const xx = (self.opcode & 0x0F00) >> 8;
                const yy = (self.opcode & 0x00F0) >> 4;
                const nn = (self.opcode & 0x000F);
                const regx = self.registers[xx];
                const regy = self.registers[yy];

                var y: usize = 0;
                while (y < nn) : (y += 1) {
                    const pixel = self.memory[self.index + y];
                    var x: usize = 0;
                    while (x < 8) : (x += 1) {
                        const msb: u8 = 0x80;

                        // check if bit is set if it is xor them to render
                        if (pixel & (msb >> @as(u3, @intCast(x))) != 0) {
                            const tx = (regx + x) % 64;
                            const ty = (regy + y) % 32;
                            const idx = tx + ty * 64;

                            self.graphics[idx] ^= 1;

                            if (self.graphics[idx] == 0) {
                                self.registers[0x0F] = 1;
                            }
                        }
                    }
                }
                self.incrementPc();
            },
            0xE => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk = self.opcode & 0x00FF;

                if (kk == 0x9E) {
                    if (self.keys[self.registers[x]] == 1) { // pressed
                        self.incrementPc();
                    }
                } else if (kk == 0xA1) {
                    if (self.keys[self.registers[x]] != 1) { // not pressed
                        self.incrementPc();
                    }
                }

                self.incrementPc();
            },
            0xF => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk = self.opcode & 0x00FF;

                if (kk == 0x07) {
                    self.registers[x] = self.delay_timer;
                } else if (kk == 0x0A) {
                    var key_pressed = false;
                    for (self.keys, 0..) |k, i| {
                        if (k != 0) {
                            self.registers[x] = @truncate(i);
                            key_pressed = true;
                        }
                    }

                    if (!key_pressed) {
                        return;
                    }
                } else if (kk == 0x15) {
                    self.delay_timer = self.registers[x];
                } else if (kk == 0x18) {
                    self.sound_timer = self.registers[x];
                } else if (kk == 0x1E) {
                    self.registers[0xF] = if (self.index + self.registers[x] > 0xFFF) 1 else 0;
                    self.index += self.registers[x];
                } else if (kk == 0x29) {
                    if (self.registers[x] < 16) {
                        self.index = self.registers[x] * 0x5;
                    }
                } else if (kk == 0x33) {
                    self.memory[self.index] = self.registers[x] / 100;
                    self.memory[self.index + 1] = (self.registers[x] / 10) % 10;
                    self.memory[self.index + 2] = self.registers[x] % 10;
                } else if (kk == 0x55) {
                    var i: usize = 0;
                    while (i <= x) : (i += 1) {
                        self.memory[self.index + i] = self.registers[i]; // dump registers into memory
                    }
                } else if (kk == 0x65) {
                    var i: usize = 0;
                    while (i <= x) : (i += 1) {
                        self.registers[i] = self.memory[self.index + i];
                    }
                }

                self.incrementPc();
            },
            else => {
                std.debug.print("CURRENT OP: {x}\n", .{self.opcode});
            },
        }
    }

    if (self.delay_timer > 0)
        self.delay_timer -= 1;

    if (self.sound_timer > 0) {
        //TODO: Sound!
        self.sound_timer -= 1;
    }
}
