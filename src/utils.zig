// Small utility struct that gives basic byte by byte reading of a file after its been loaded into memory
const std = @import("std");
var timer: std.time.Timer = undefined;
pub fn timer_start() !void {
    timer = try std.time.Timer.start();
}

inline fn gaussian_kernel(x: i32, y: i32, sigma: f32) f32 {
    const coeff: f32 = 1.0 / (2.0 * std.math.pi * sigma * sigma);
    const exponent: f32 = -(@as(f32, @floatFromInt(x)) * @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(y)) * @as(f32, @floatFromInt(y))) / (2.0 * sigma * sigma);
    return coeff * std.math.exp(exponent);
}

fn gaussian_kernel_2d(allocator: std.mem.Allocator, sigma: f32) std.mem.Allocator.Error![]f32 {
    var kernel_size: u32 = @as(u32, @intFromFloat(@ceil(2 * sigma + 1)));
    if (kernel_size % 2 == 0) {
        kernel_size += 1;
    }
    var kernel_2d: []f32 = try allocator.alloc(f32, kernel_size * kernel_size);
    var sum: f32 = 0.0;
    for (0..kernel_size) |i| {
        for (0..kernel_size) |j| {
            const x: i32 = @as(i32, @intCast(@as(i64, @bitCast(j)))) - @divFloor(@as(i32, @bitCast(kernel_size)), 2);
            const y: i32 = @as(i32, @intCast(@as(i64, @bitCast(i)))) - @divFloor(@as(i32, @bitCast(kernel_size)), 2);
            const val: f32 = gaussian_kernel(x, y, sigma);
            kernel_2d[i * kernel_size + j] = val;
            sum += val;
        }
    }

    for (0..kernel_size) |i| {
        for (0..kernel_size) |j| {
            kernel_2d[i * kernel_size + j] /= sum;
        }
    }
    return kernel_2d;
}

pub const ImageCore = struct {
    height: u32,
    width: u32,
    data: []Pixel,
    allocator: std.mem.Allocator,
    const Self = @This();
    const BicubicPixel = struct {
        r: f32 = 0,
        g: f32 = 0,
        b: f32 = 0,
        a: ?f32 = null,
        pub fn sub(self: *const BicubicPixel, other: BicubicPixel) BicubicPixel {
            return .{
                .r = self.r - other.r,
                .g = self.g - other.g,
                .b = self.b - other.b,
                .a = if (self.a != null and other.a != null) self.a.? - other.a.? else null,
            };
        }
        pub fn add(self: *const BicubicPixel, other: BicubicPixel) BicubicPixel {
            return .{
                .r = self.r + other.r,
                .g = self.g + other.g,
                .b = self.b + other.b,
                .a = if (self.a != null and other.a != null) self.a.? + other.a.? else null,
            };
        }
        pub fn scale(self: *const BicubicPixel, scalar: f32) BicubicPixel {
            return .{
                .r = self.r * scalar,
                .g = self.g * scalar,
                .b = self.b * scalar,
                .a = if (self.a != null) self.a.? * scalar else null,
            };
        }
    };
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, data: []Pixel) ImageCore {
        return .{
            .height = height,
            .width = width,
            .data = data,
            .allocator = allocator,
        };
    }
    pub fn bilinear(self: *const Self, width: u32, height: u32) std.mem.Allocator.Error![]Pixel {
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        const width_scale: f32 = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(width));
        const height_scale: f32 = @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(height));
        for (0..height) |y| {
            for (0..width) |x| {
                const src_x: f32 = @as(f32, @floatFromInt(x)) * width_scale;
                const src_y: f32 = @as(f32, @floatFromInt(y)) * height_scale;
                const src_x_floor: f32 = @floor(src_x);
                const src_x_ceil: f32 = @min(@as(f32, @floatFromInt(self.width)) - 1.0, @ceil(src_x));
                const src_y_floor: f32 = @floor(src_y);
                const src_y_ceil: f32 = @min(@as(f32, @floatFromInt(self.height)) - 1.0, @ceil(src_y));
                const src_x_floor_indx: usize = @as(usize, @intFromFloat(src_x_floor));
                const src_x_ceil_indx: usize = @as(usize, @intFromFloat(src_x_ceil));
                const src_y_floor_indx: usize = @as(usize, @intFromFloat(src_y_floor));
                const src_y_ceil_indx: usize = @as(usize, @intFromFloat(src_y_ceil));
                var new_pixel: Pixel = Pixel{};
                if (src_x_ceil == src_x_floor and src_y_ceil == src_y_floor) {
                    new_pixel.r = self.data[src_y_floor_indx * self.width + src_x_floor_indx].r;
                    new_pixel.g = self.data[src_y_floor_indx * self.width + src_x_floor_indx].g;
                    new_pixel.b = self.data[src_y_floor_indx * self.width + src_x_floor_indx].b;
                    new_pixel.a = self.data[src_y_floor_indx * self.width + src_x_floor_indx].a;
                } else if (src_x_ceil == src_x_floor) {
                    const q1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const q2 = self.data[src_y_ceil_indx * self.width + src_x_floor_indx];
                    new_pixel.r = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.r)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.r)) * (src_y - src_y_floor))));
                    new_pixel.g = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.g)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.g)) * (src_y - src_y_floor))));
                    new_pixel.b = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.b)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.b)) * (src_y - src_y_floor))));
                    new_pixel.a = if (q1.a != null and q2.a != null) @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.a.?)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.a.?)) * (src_y - src_y_floor)))) else null;
                } else if (src_y_ceil == src_y_floor) {
                    const q1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const q2 = self.data[src_y_ceil_indx * self.width + src_x_ceil_indx];
                    new_pixel.r = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.r)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.r)) * (src_x - src_x_floor))));
                    new_pixel.g = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.g)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.g)) * (src_x - src_x_floor))));
                    new_pixel.b = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.b)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.b)) * (src_x - src_x_floor))));
                    new_pixel.a = if (q1.a != null and q2.a != null) @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.a.?)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.a.?)) * (src_x - src_x_floor)))) else null;
                } else {
                    const v1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const v2 = self.data[src_y_floor_indx * self.width + src_x_ceil_indx];
                    const v3 = self.data[src_y_ceil_indx * self.width + src_x_floor_indx];
                    const v4 = self.data[src_y_ceil_indx * self.width + src_x_ceil_indx];

                    const q1 = .{
                        .r = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.r)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.r)) * (src_x - src_x_floor)))),
                        .g = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.g)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.g)) * (src_x - src_x_floor)))),
                        .b = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.b)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.b)) * (src_x - src_x_floor)))),
                        .a = if (v1.a != null and v2.a != null) @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.a.?)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.a.?)) * (src_x - src_x_floor)))) else null,
                    };
                    const q2 = .{
                        .r = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.r)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.r)) * (src_x - src_x_floor)))),
                        .g = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.g)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.g)) * (src_x - src_x_floor)))),
                        .b = @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.b)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.b)) * (src_x - src_x_floor)))),
                        .a = if (v3.a != null and v4.a != null) @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.a.?)) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.a.?)) * (src_x - src_x_floor)))) else null,
                    };
                    new_pixel.r = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.r)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.r)) * (src_y - src_y_floor))));
                    new_pixel.g = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.g)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.g)) * (src_y - src_y_floor))));
                    new_pixel.b = @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.b)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.b)) * (src_y - src_y_floor))));
                    new_pixel.a = if (q1.a != null and q2.a != null) @as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.a.?)) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.a.?)) * (src_y - src_y_floor)))) else null;
                }

                data_copy[y * width + x].r = new_pixel.r;
                data_copy[y * width + x].g = new_pixel.g;
                data_copy[y * width + x].b = new_pixel.b;
                data_copy[y * width + x].a = new_pixel.a;
            }
        }
        return data_copy;
    }
    fn bicubic_get_pixel(self: *const Self, y: i64, x: i64) BicubicPixel {
        if (x < self.width and y < self.height and x > 0 and y > 0) {
            return BicubicPixel{
                .r = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].r)),
                .g = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].g)),
                .b = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].b)),
            };
        } else {
            return BicubicPixel{};
        }
    }
    pub fn bicubic(self: *const Self, width: u32, height: u32) std.mem.Allocator.Error![]Pixel {
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        const width_scale: f32 = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(width));
        const height_scale: f32 = @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(height));
        var C: [5]BicubicPixel = undefined;
        for (0..5) |i| {
            C[i] = BicubicPixel{};
        }
        for (0..height) |y| {
            for (0..width) |x| {
                const src_x: i64 = @as(i64, @intFromFloat(@as(f32, @floatFromInt(x)) * width_scale));
                const src_y: i64 = @as(i64, @intFromFloat(@as(f32, @floatFromInt(y)) * height_scale));
                const dx: f32 = width_scale * @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(src_x));
                const dy: f32 = height_scale * @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(src_y));
                var new_pixel: BicubicPixel = BicubicPixel{};
                for (0..4) |jj| {
                    const z: i64 = src_y + @as(i64, @bitCast(jj)) - 1;
                    const a0 = self.bicubic_get_pixel(z, src_x);
                    const d0 = self.bicubic_get_pixel(z, src_x - 1).sub(a0);
                    const d2 = self.bicubic_get_pixel(z, src_x + 1).sub(a0);
                    const d3 = self.bicubic_get_pixel(z, src_x + 2).sub(a0);

                    const a1 = d0.scale(-1.0 / 3.0).add(d2.sub(d3.scale(1.0 / 6.0)));
                    const a2 = d0.scale(1.0 / 2.0).add(d2.scale(1.0 / 2.0));
                    const a3 = d0.scale(-1.0 / 6.0).sub(d2.scale(1.0 / 2.0).add(d3.scale(1.0 / 6.0)));

                    C[jj] = a0.add(a1.scale(dx)).add(a2.scale(dx * dx)).add(a3.scale(dx * dx * dx));
                }
                const d0 = C[0].sub(C[1]);
                const d2 = C[2].sub(C[1]);
                const d3 = C[3].sub(C[1]);
                const a0 = C[1];

                const a1 = d0.scale(-1.0 / 3.0).add(d2.sub(d3.scale(1.0 / 6.0)));
                const a2 = d0.scale(1.0 / 2.0).add(d2.scale(1.0 / 2.0));
                const a3 = d0.scale(-1.0 / 6.0).sub(d2.scale(1.0 / 2.0).add(d3.scale(1.0 / 6.0)));
                new_pixel = a0.add(a1.scale(dy)).add(a2.scale(dy * dy)).add(a3.scale(dy * dy * dy));
                if (new_pixel.r > 255) {
                    new_pixel.r = 255;
                } else if (new_pixel.r < 0) {
                    new_pixel.r = 0;
                }
                if (new_pixel.g > 255) {
                    new_pixel.g = 255;
                } else if (new_pixel.g < 0) {
                    new_pixel.g = 0;
                }
                if (new_pixel.b > 255) {
                    new_pixel.b = 255;
                } else if (new_pixel.b < 0) {
                    new_pixel.b = 0;
                }
                if (new_pixel.a != null and new_pixel.a.? > 255) {
                    new_pixel.a = 255;
                } else if (new_pixel.a != null and new_pixel.a.? < 0) {
                    new_pixel.a = 0;
                }
                std.debug.print("{any}\n", .{new_pixel.r});
                data_copy[y * width + x].r = @as(u8, @intFromFloat(new_pixel.r));
                data_copy[y * width + x].g = @as(u8, @intFromFloat(new_pixel.g));
                data_copy[y * width + x].b = @as(u8, @intFromFloat(new_pixel.b));
                data_copy[y * width + x].a = if (new_pixel.a != null) @as(u8, @intFromFloat(new_pixel.a.?)) else null;
            }
        }

        return data_copy;
    }
    pub fn gaussian_blur(self: *const Self, sigma: f32) std.mem.Allocator.Error![]Pixel {
        const kernel_2d = try gaussian_kernel_2d(self.allocator, sigma);
        defer self.allocator.free(kernel_2d);
        var kernel_size: u32 = @as(u32, @intFromFloat(@ceil(2 * sigma + 1)));
        if (kernel_size % 2 == 0) {
            kernel_size += 1;
        }
        var data_copy: []Pixel = try self.allocator.alloc(Pixel, self.data.len);
        for (kernel_size / 2..self.height - kernel_size / 2) |y| {
            for (kernel_size / 2..self.width - kernel_size / 2) |x| {
                var r: f32 = 0.0;
                var g: f32 = 0.0;
                var b: f32 = 0.0;
                var a: f32 = 0.0;
                for (0..kernel_size) |i| {
                    for (0..kernel_size) |j| {
                        var curr_pixel: Pixel = undefined;

                        curr_pixel = self.data[(y + i - kernel_size / 2) * self.width + (x + j - kernel_size / 2)];

                        r += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.r));
                        g += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.g));
                        b += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.b));
                        a += if (curr_pixel.a != null) kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.a.?)) else 0.0;
                    }
                }

                data_copy[y * self.width + x].r = @as(u8, @intFromFloat(r));
                data_copy[y * self.width + x].g = @as(u8, @intFromFloat(g));
                data_copy[y * self.width + x].b = @as(u8, @intFromFloat(b));
                data_copy[y * self.width + x].a = if (self.data[y * self.width + x].a != null) @as(u8, @intFromFloat(a)) else null;
            }
        }
        return data_copy;
    }
    pub fn nearest_neighbor(self: *const Self, width: usize, height: usize) std.mem.Allocator.Error![]Pixel {
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        for (0..height) |y| {
            for (0..width) |x| {
                const src_x: usize = @min(self.width - 1, @as(usize, @intFromFloat(@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width)) * @as(f32, @floatFromInt(self.width)))));
                const src_y: usize = @min(self.height - 1, @as(usize, @intFromFloat(@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height)) * @as(f32, @floatFromInt(self.height)))));
                data_copy[y * width + x] = .{ .r = self.data[src_y * self.width + src_x].r, .g = self.data[src_y * self.width + src_x].g, .b = self.data[src_y * self.width + src_x].b, .a = self.data[src_y * self.width + src_x].a };
            }
        }
        return data_copy;
    }
    pub fn grayscale(self: *const Self) std.mem.Allocator.Error![]Pixel {
        var data_copy = try self.allocator.dupe(Pixel, self.data);
        for (0..data_copy.len) |i| {
            const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].r)) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].g)) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].b)) * 0.1140));
            data_copy[i].r = gray;
            data_copy[i].g = gray;
            data_copy[i].b = gray;
        }
        return data_copy;
    }
    pub fn write_BMP(self: *const Self, file_name: []const u8) !void {
        const image_file = try std.fs.cwd().createFile(file_name, .{});
        defer image_file.close();
        try image_file.writer().writeByte('B');
        try image_file.writer().writeByte('M');
        const padding_size: u32 = self.width % 4;
        const size: u32 = 14 + 12 + self.height * self.width * 3 + padding_size * self.height;

        var buffer: []u8 = try self.allocator.alloc(u8, self.height * self.width * 3 + padding_size * self.height);
        var buffer_pos = buffer[0..buffer.len];
        defer self.allocator.free(buffer);
        try write_little_endian(&image_file, 4, size);
        try write_little_endian(&image_file, 4, 0);
        try write_little_endian(&image_file, 4, 0x1A);
        try write_little_endian(&image_file, 4, 12);
        try write_little_endian(&image_file, 2, self.width);
        try write_little_endian(&image_file, 2, self.height);
        try write_little_endian(&image_file, 2, 1);
        try write_little_endian(&image_file, 2, 24);
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) {
            while (j < self.width) {
                const pixel: *Pixel = &self.data[i * self.width + j];
                var r: u8 = pixel.r;
                var g: u8 = pixel.g;
                var b: u8 = pixel.b;
                if (pixel.a) |alpha| {
                    const max_pixel = 255.0;
                    const bkgd = 255.0;
                    var rf: f32 = if (alpha == 0) 0 else (@as(f32, @floatFromInt(alpha)) / max_pixel) * @as(f32, @floatFromInt(pixel.r));
                    var gf: f32 = if (alpha == 0) 0 else (@as(f32, @floatFromInt(alpha)) / max_pixel) * @as(f32, @floatFromInt(pixel.g));
                    var bf: f32 = if (alpha == 0) 0 else (@as(f32, @floatFromInt(alpha)) / max_pixel) * @as(f32, @floatFromInt(pixel.b));
                    rf += (1 - (@as(f32, @floatFromInt(alpha)) / max_pixel)) * bkgd;
                    gf += (1 - (@as(f32, @floatFromInt(alpha)) / max_pixel)) * bkgd;
                    bf += (1 - (@as(f32, @floatFromInt(alpha)) / max_pixel)) * bkgd;
                    r = @as(u8, @intFromFloat(rf));
                    g = @as(u8, @intFromFloat(gf));
                    b = @as(u8, @intFromFloat(bf));
                }
                buffer_pos[0] = b;
                buffer_pos.ptr += 1;
                buffer_pos[0] = g;
                buffer_pos.ptr += 1;
                buffer_pos[0] = r;
                buffer_pos.ptr += 1;
                j += 1;
            }
            for (0..padding_size) |_| {
                buffer_pos[0] = 0;
                buffer_pos.ptr += 1;
            }
            j = 0;
            if (i == 0) break;
            i -= 1;
        }
        try image_file.writeAll(buffer);
    }
};

pub fn timer_end() void {
    std.debug.print("{d} s elapsed.\n", .{@as(f32, @floatFromInt(timer.read())) / 1000000000.0});
    timer.reset();
}

pub const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: ?u8 = null,
    pub fn eql(self: *Pixel, other: Pixel) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }
};

pub const Max_error = error{
    NO_ITEMS,
};

pub fn max_array(comptime T: type, arr: []T) Max_error!T {
    if (arr.len == 1) {
        return arr[0];
    } else if (arr.len == 0) {
        return Max_error.NO_ITEMS;
    }
    var max_t: T = arr[0];
    for (1..arr.len) |i| {
        if (arr[i] > max_t) {
            max_t = arr[i];
        }
    }
    return max_t;
}

pub fn write_little_endian(file: *const std.fs.File, num_bytes: comptime_int, i: u32) !void {
    switch (num_bytes) {
        2 => {
            try file.writer().writeInt(u16, @as(u16, @intCast(i)), std.builtin.Endian.little);
        },
        4 => {
            try file.writer().writeInt(u32, i, std.builtin.Endian.little);
        },
        else => unreachable,
    }
}

pub fn HuffmanTree(comptime T: type) type {
    return struct {
        root: Node,
        allocator: std.mem.Allocator,
        const Self = @This();
        pub const Node = struct {
            symbol: T,
            left: ?*Node,
            right: ?*Node,
            pub fn init() Node {
                return Node{
                    .symbol = ' ',
                    .left = null,
                    .right = null,
                };
            }
        };
        pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!HuffmanTree(T) {
            return .{
                .root = Node.init(),
                .allocator = allocator,
            };
        }
        pub fn deinit_node(self: *Self, node: ?*Node) void {
            if (node) |parent| {
                self.deinit_node(parent.left);
                self.deinit_node(parent.right);
                self.allocator.destroy(parent);
            }
        }
        pub fn deinit(self: *Self) void {
            self.deinit_node(self.root.left);
            self.deinit_node(self.root.right);
        }
        pub fn insert(self: *Self, codeword: T, n: T, symbol: T) std.mem.Allocator.Error!void {
            //std.debug.print("inserting {b} with length {d} and symbol {d}\n", .{ codeword, n, symbol });
            var node: *Node = &self.root;
            var i = n - 1;
            var next_node: ?*Node = null;
            while (i >= 0) : (i -= 1) {
                const b = codeword & std.math.shl(T, 1, i);
                //std.debug.print("b {d}\n", .{b});
                if (b != 0) {
                    if (node.right) |right| {
                        next_node = right;
                    } else {
                        node.right = try self.allocator.create(Node);
                        node.right.?.* = Node.init();
                        next_node = node.right;
                    }
                } else {
                    if (node.left) |left| {
                        next_node = left;
                    } else {
                        node.left = try self.allocator.create(Node);
                        node.left.?.* = Node.init();
                        next_node = node.left;
                    }
                }
                node = next_node.?;
                if (i == 0) break;
            }
            node.symbol = symbol;
        }
    };
}

pub const ByteStream = struct {
    index: usize = 0,
    buffer: []u8 = undefined,
    allocator: std.mem.Allocator = undefined,
    own_data: bool = false,
    pub const Error = error{
        OUT_OF_BOUNDS,
        INVALID_ARGS,
    };
    pub fn init(options: anytype) !ByteStream {
        const ArgsType = @TypeOf(options);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            return Error.INVALID_ARGS;
        }
        var buffer: []u8 = undefined;
        var allocator: std.mem.Allocator = undefined;
        var own_data: bool = false;
        if (@hasField(ArgsType, "data")) {
            buffer = @field(options, "data");
        } else if (@hasField(ArgsType, "file_name") and @hasField(ArgsType, "allocator")) {
            allocator = @field(options, "allocator");
            own_data = true;
            const file = try std.fs.cwd().openFile(@field(options, "file_name"), .{});
            defer file.close();
            const size_limit = std.math.maxInt(u32);
            buffer = try file.readToEndAlloc(allocator, size_limit);
        } else {
            return Error.INVALID_ARGS;
        }
        return ByteStream{
            .buffer = buffer,
            .allocator = allocator,
            .own_data = own_data,
        };
    }
    pub fn deinit(self: *ByteStream) void {
        if (self.own_data) {
            self.allocator.free(self.buffer);
        }
    }
    pub fn getPos(self: *ByteStream) usize {
        return self.index;
    }
    pub fn setPos(self: *ByteStream, index: usize) void {
        self.index = index;
    }
    pub fn getEndPos(self: *ByteStream) usize {
        return self.buffer.len - 1;
    }
    pub fn peek(self: *ByteStream) Error!u8 {
        if (self.index > self.buffer.len - 1) {
            return Error.OUT_OF_BOUNDS;
        }
        return self.buffer[self.index];
    }
    pub fn readByte(self: *ByteStream) Error!u8 {
        if (self.index > self.buffer.len - 1) {
            return Error.OUT_OF_BOUNDS;
        }
        self.index += 1;
        return self.buffer[self.index - 1];
    }
};

pub const BitReader = struct {
    next_byte: u32 = 0,
    next_bit: u32 = 0,
    byte_stream: ByteStream = undefined,
    jpeg_filter: bool = false,
    little_endian: bool = false,
    reverse_bit_order: bool = false,
    const Self = @This();
    pub const Error = error{
        INVALID_READ,
        INVALID_ARGS,
    };

    pub fn init(options: anytype) !BitReader {
        var bit_reader: BitReader = BitReader{};
        bit_reader.byte_stream = try ByteStream.init(options);
        try bit_reader.set_options(options);
        return bit_reader;
    }

    pub fn set_options(self: *Self, options: anytype) Error!void {
        const ArgsType = @TypeOf(options);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            return Error.INVALID_ARGS;
        }

        self.little_endian = if (@hasField(ArgsType, "little_endian")) @field(options, "little_endian") else false;
        self.jpeg_filter = if (@hasField(ArgsType, "jpeg_filter")) @field(options, "jpeg_filter") else false;
        self.reverse_bit_order = if (@hasField(ArgsType, "reverse_bit_order")) @field(options, "reverse_bit_order") else false;
    }
    pub fn deinit(self: *Self) void {
        self.byte_stream.deinit();
    }
    pub fn setPos(self: *Self, index: usize) void {
        self.byte_stream.setPos(index);
    }
    pub fn getPos(self: *Self) usize {
        return self.byte_stream.getPos();
    }
    pub fn has_bits(self: *Self) bool {
        return if (self.byte_stream.getPos() != self.byte_stream.getEndPos()) true else false;
    }
    pub fn read_byte(self: *Self) ByteStream.Error!u8 {
        self.next_bit = 0;
        return try self.byte_stream.readByte();
    }
    pub fn read_word(self: *Self) (Error || ByteStream.Error)!u16 {
        self.next_bit = 0;
        var ret_word: u16 = @as(u16, try self.byte_stream.readByte());
        if (self.little_endian) {
            ret_word |= @as(u16, @intCast(try self.byte_stream.readByte())) << 8;
        } else {
            ret_word <<= 8;
            ret_word += try self.byte_stream.readByte();
        }

        return ret_word;
    }
    pub fn read_int(self: *Self) (Error || ByteStream.Error)!u32 {
        self.next_bit = 0;
        var ret_int: u32 = @as(u32, try self.byte_stream.readByte());
        if (self.little_endian) {
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte())) << 24;
        } else {
            ret_int <<= 24;
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
            ret_int |= @as(u32, @intCast(try self.byte_stream.readByte()));
        }

        return ret_int;
    }
    pub fn read_bit(self: *Self) (Error || ByteStream.Error)!u32 {
        var bit: u32 = undefined;
        if (self.next_bit == 0) {
            if (!self.has_bits()) {
                return Error.INVALID_READ;
            }
            self.next_byte = try self.byte_stream.readByte();
            if (self.jpeg_filter) {
                while (self.next_byte == 0xFF) {
                    var marker: u8 = try self.byte_stream.peek();
                    while (marker == 0xFF) {
                        _ = try self.byte_stream.readByte();
                        marker = try self.byte_stream.peek();
                    }
                    if (marker == 0x00) {
                        _ = try self.byte_stream.readByte();
                        break;
                    } else if (marker >= 0xD0 and marker <= 0xD7) {
                        _ = try self.byte_stream.readByte();
                        self.next_byte = try self.byte_stream.readByte();
                    } else {
                        return Error.INVALID_READ;
                    }
                }
            }
        }
        if (self.reverse_bit_order) {
            bit = (self.next_byte >> @as(u5, @intCast(self.next_bit))) & 1;
        } else {
            bit = (self.next_byte >> @as(u5, @intCast(7 - self.next_bit))) & 1;
        }

        self.next_bit = (self.next_bit + 1) % 8;
        return bit;
    }
    pub fn read_bits(self: *Self, length: u32) (Error || ByteStream.Error)!u32 {
        var bits: u32 = 0;
        for (0..length) |i| {
            const bit = try self.read_bit();
            if (self.reverse_bit_order) {
                bits |= bit << @as(u5, @intCast(i));
            } else {
                bits = (bits << 1) | bit;
            }
        }
        return bits;
    }
    pub fn align_reader(self: *Self) void {
        self.next_bit = 0;
    }
};

test "HUFFMAN_TREE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var t = try allocator.create(HuffmanTree(u32));
    t.* = try HuffmanTree(u32).init(allocator);
    try t.insert(1, 2, 'A');
    try t.insert(1, 1, 'B');
    try t.insert(0, 3, 'C');
    try t.insert(1, 3, 'D');
    t.deinit();
    allocator.destroy(t);
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
