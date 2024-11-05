const std = @import("std");
var timer: std.time.Timer = undefined;
pub fn timer_start() std.time.Timer.Error!void {
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
    pub const Error = error{} || std.mem.Allocator.Error || std.fs.File.Writer.Error || std.fs.File.OpenError || Mat(3).Error;
    const BicubicPixel = struct {
        r: f32 = 0,
        g: f32 = 0,
        b: f32 = 0,
        a: f32 = 255,
        pub fn sub(self: *const BicubicPixel, other: BicubicPixel) BicubicPixel {
            return .{
                .r = self.r - other.r,
                .g = self.g - other.g,
                .b = self.b - other.b,
                .a = self.a - other.a,
            };
        }
        pub fn add(self: *const BicubicPixel, other: BicubicPixel) BicubicPixel {
            return .{
                .r = self.r + other.r,
                .g = self.g + other.g,
                .b = self.b + other.b,
                .a = self.a + other.a,
            };
        }
        pub fn scale(self: *const BicubicPixel, scalar: f32) BicubicPixel {
            return .{
                .r = self.r * scalar,
                .g = self.g * scalar,
                .b = self.b * scalar,
                .a = self.a * scalar,
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
    pub fn bilinear(self: *const Self, width: u32, height: u32) Error![]Pixel {
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
                    new_pixel.set_r(self.data[src_y_floor_indx * self.width + src_x_floor_indx].get_r());
                    new_pixel.set_g(self.data[src_y_floor_indx * self.width + src_x_floor_indx].get_g());
                    new_pixel.set_b(self.data[src_y_floor_indx * self.width + src_x_floor_indx].get_b());
                    new_pixel.set_a(self.data[src_y_floor_indx * self.width + src_x_floor_indx].get_a());
                } else if (src_x_ceil == src_x_floor) {
                    const q1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const q2 = self.data[src_y_ceil_indx * self.width + src_x_floor_indx];
                    new_pixel.set_r(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_r())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_r())) * (src_y - src_y_floor)))));
                    new_pixel.set_g(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_g())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_g())) * (src_y - src_y_floor)))));
                    new_pixel.set_b(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_b())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_b())) * (src_y - src_y_floor)))));
                    new_pixel.set_a(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_a())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_a())) * (src_y - src_y_floor)))));
                } else if (src_y_ceil == src_y_floor) {
                    const q1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const q2 = self.data[src_y_ceil_indx * self.width + src_x_ceil_indx];
                    new_pixel.set_r(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_r())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.get_r())) * (src_x - src_x_floor)))));
                    new_pixel.set_g(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_g())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.get_g())) * (src_x - src_x_floor)))));
                    new_pixel.set_b(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_b())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.get_b())) * (src_x - src_x_floor)))));
                    new_pixel.set_a(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_a())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(q2.get_a())) * (src_x - src_x_floor)))));
                } else {
                    const v1 = self.data[src_y_floor_indx * self.width + src_x_floor_indx];
                    const v2 = self.data[src_y_floor_indx * self.width + src_x_ceil_indx];
                    const v3 = self.data[src_y_ceil_indx * self.width + src_x_floor_indx];
                    const v4 = self.data[src_y_ceil_indx * self.width + src_x_ceil_indx];

                    const q1 = Pixel.init(
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.get_r())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.get_r())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.get_g())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.get_g())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.get_b())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.get_b())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v1.get_a())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v2.get_a())) * (src_x - src_x_floor)))),
                    );
                    const q2 = Pixel.init(
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.get_r())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.get_r())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.get_g())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.get_g())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.get_b())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.get_b())) * (src_x - src_x_floor)))),
                        @as(u8, @intFromFloat((@as(f32, @floatFromInt(v3.get_a())) * (src_x_ceil - src_x)) + (@as(f32, @floatFromInt(v4.get_a())) * (src_x - src_x_floor)))),
                    );
                    new_pixel.set_r(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_r())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_r())) * (src_y - src_y_floor)))));
                    new_pixel.set_g(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_g())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_g())) * (src_y - src_y_floor)))));
                    new_pixel.set_b(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_b())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_b())) * (src_y - src_y_floor)))));
                    new_pixel.set_a(@as(u8, @intFromFloat((@as(f32, @floatFromInt(q1.get_a())) * (src_y_ceil - src_y)) + (@as(f32, @floatFromInt(q2.get_a())) * (src_y - src_y_floor)))));
                }

                data_copy[y * width + x].v = new_pixel.v;
            }
        }
        return data_copy;
    }
    fn bicubic_get_pixel(self: *const Self, y: i64, x: i64) BicubicPixel {
        if (x < self.width and y < self.height and x > 0 and y > 0) {
            return BicubicPixel{
                .r = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].get_r())),
                .g = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].get_g())),
                .b = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].get_b())),
                .a = @as(f32, @floatFromInt(self.data[@as(usize, @bitCast(y)) * self.width + @as(usize, @bitCast(x))].get_a())),
            };
        } else {
            return BicubicPixel{};
        }
    }
    pub fn bicubic(self: *const Self, width: u32, height: u32) Error![]Pixel {
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
                if (new_pixel.a > 255) {
                    new_pixel.a = 255;
                } else if (new_pixel.a < 0) {
                    new_pixel.a = 0;
                }
                data_copy[y * width + x].v = .{ @as(u8, @intFromFloat(new_pixel.r)), @as(u8, @intFromFloat(new_pixel.b)), @as(u8, @intFromFloat(new_pixel.b)), @as(u8, @intFromFloat(new_pixel.a)) };
            }
        }

        return data_copy;
    }
    pub fn gaussian_blur(self: *const Self, sigma: f32) Error![]Pixel {
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

                        r += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.get_r()));
                        g += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.get_g()));
                        b += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.get_b()));
                        a += kernel_2d[i * kernel_size + j] * @as(f32, @floatFromInt(curr_pixel.get_a()));
                    }
                }

                data_copy[y * self.width + x].v = .{ @as(u8, @intFromFloat(r)), @as(u8, @intFromFloat(g)), @as(u8, @intFromFloat(b)), @as(u8, @intFromFloat(a)) };
            }
        }
        return data_copy;
    }
    pub fn nearest_neighbor(self: *const Self, width: usize, height: usize) Error![]Pixel {
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        for (0..height) |y| {
            for (0..width) |x| {
                const src_x: usize = @min(self.width - 1, @as(usize, @intFromFloat(@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width)) * @as(f32, @floatFromInt(self.width)))));
                const src_y: usize = @min(self.height - 1, @as(usize, @intFromFloat(@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height)) * @as(f32, @floatFromInt(self.height)))));
                data_copy[y * width + x].v = self.data[src_y * self.width + src_x].v;
            }
        }
        return data_copy;
    }
    pub fn grayscale(self: *const Self) Error![]Pixel {
        var data_copy = try self.allocator.dupe(Pixel, self.data);
        for (0..data_copy.len) |i| {
            const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].get_r())) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].get_g())) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(data_copy[i].get_b())) * 0.1140));
            data_copy[i].v = .{ gray, gray, gray, data_copy[i].get_a() };
        }
        return data_copy;
    }
    //TODO add more image processing functions https://en.wikipedia.org/wiki/Digital_image_processing
    //TODO lowpass highpass fourier denoising
    pub fn spatial_highpass(self: *const Self) Error![]Pixel {
        const highpass_mat = try Mat(3).spatial_highpass();
        return try self.convol(highpass_mat);
    }
    pub fn convol(self: *const Self, kernel: Mat(3)) Error![]Pixel {
        var data_copy = try self.allocator.dupe(Pixel, self.data);
        std.debug.print("kernel\n", .{});
        kernel.print();
        for (0..self.height) |i| {
            for (0..self.width) |j| {
                const indx: usize = (i * self.width + j);
                if (i >= 1 and j >= 1 and i < self.height - 1 and j < self.width - 1) {
                    for (0..3) |c| {
                        var sum: f32 = 0;
                        for (0..3) |k| {
                            const float_vector: Mat(3).Vec = .{ @floatFromInt(self.data[indx - self.width - 1 + k].v[c]), @floatFromInt(self.data[indx - 1 + k].v[c]), @floatFromInt(self.data[indx + self.width - 1 + k].v[c]) };
                            sum += @reduce(.Add, float_vector * kernel.row(k));
                        }
                        data_copy[indx].v[c] = if (sum > 255) 255 else if (sum < 0) 0 else @as(u8, @intFromFloat(sum));
                    }
                    //std.debug.print("float_vector {any}\n", .{float_vector});
                } else {
                    data_copy[indx] = Pixel.init(0, 0, 0, null);
                }
            }
        }
        return data_copy;
    }
    //reflect along an axis x, y or both
    pub fn reflection(self: *const Self, comptime axis: @Type(.EnumLiteral)) Error![]Pixel {
        var data_copy = try self.allocator.dupe(Pixel, self.data);
        errdefer self.allocator.free(data_copy);
        switch (axis) {
            .x => {
                for (0..self.height) |y| {
                    for (0..self.width) |x| {
                        data_copy[y * self.width + x].v = self.data[y * self.width + (self.width - 1 - x)].v;
                    }
                }
            },
            .y => {
                for (0..self.height) |y| {
                    for (0..self.width) |x| {
                        data_copy[y * self.width + x].v = self.data[(self.height - 1 - y) * self.width + x].v;
                    }
                }
            },
            .xy, .yx => {
                for (0..self.height) |y| {
                    for (0..self.width) |x| {
                        data_copy[y * self.width + x].v = self.data[(self.height - 1 - y) * self.width + (self.width - 1 - x)].v;
                    }
                }
            },
            else => unreachable,
        }
        return data_copy;
    }
    fn rotate_slow(self: *Self, degrees: f32) Error!struct { width: u32, height: u32, data: []Pixel } {
        const scale_factor = 4;
        var scaled_width = self.width * scale_factor;
        var scaled_height = self.height * scale_factor;
        var scaled_pixels = try self.bicubic(scaled_width, scaled_height);
        const radians: f32 = std.math.degreesToRadians(degrees);
        const shear13 = try Mat(3).shear(0, -@tan(radians / 2));
        shear13.print();
        const shear2 = try Mat(3).shear(@sin(radians), 0);
        shear2.print();
        const rotate_mat = shear13.mul(shear2).mul(shear13);
        rotate_mat.print();
        const Vec = Mat(3).Vec;
        var vectors: []Vec = try self.allocator.alloc(Vec, scaled_pixels.len);
        defer self.allocator.free(vectors);
        var min_x: f32 = -@as(f32, @floatFromInt(scaled_width / 2));
        var max_x: f32 = @as(f32, @floatFromInt(scaled_width / 2)) - 1;
        var min_y: f32 = -@as(f32, @floatFromInt(scaled_height / 2));
        var max_y: f32 = @as(f32, @floatFromInt(scaled_height / 2)) - 1;
        var translate_mat = try Mat(3).translate(min_x, min_y);
        for (0..scaled_height) |i| {
            for (0..scaled_width) |j| {
                //vectors[i * self.width + j] = shear13.mul_v(shear2.mul_v(shear13.mul_v(try Mat(3).vectorize(.{ @as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)) }))));
                vectors[i * scaled_width + j] = rotate_mat.mul_v(translate_mat.mul_v(try Mat(3).vectorize(.{ @as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)) })));
                if (i == 0 and j == 0) {
                    min_x = vectors[0][0];
                    max_x = vectors[0][0];
                    min_y = vectors[0][1];
                    max_y = vectors[0][1];
                } else {
                    min_x = @min(min_x, vectors[i * scaled_width + j][0]);
                    max_x = @max(max_x, vectors[i * scaled_width + j][0]);
                    min_y = @min(min_y, vectors[i * scaled_width + j][1]);
                    max_y = @max(max_y, vectors[i * scaled_width + j][1]);
                }
            }
        }
        //std.log.warn("pre translate {any}\n", .{vectors});
        translate_mat = try Mat(3).translate(-min_x, -min_y);
        for (0..scaled_height) |i| {
            for (0..scaled_width) |j| {
                vectors[i * scaled_width + j] = translate_mat.mul_v(vectors[i * scaled_width + j]);
            }
        }
        //std.log.warn("translated {any}\n", .{vectors});
        const width = @as(u32, @intFromFloat(@ceil(max_x - min_x))) + 1;
        const height = @as(u32, @intFromFloat(@ceil(max_y - min_y))) + 1;
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        std.log.warn("min_x {d} max_x {d} min_y {d} max_y {d} width {d} height {d} len {d}\n", .{ min_x, max_x, min_y, max_y, width, height, data_copy.len });
        for (0..data_copy.len) |i| {
            data_copy[i] = Pixel{};
        }
        for (0..scaled_height) |i| {
            for (0..scaled_width) |j| {
                //std.log.warn("x coord {any}", .{vectors[i * self.width + j][0]});
                const x = @as(usize, @intFromFloat(@floor(vectors[i * scaled_width + j][0])));
                const y = @as(usize, @intFromFloat(@floor(vectors[i * scaled_width + j][1])));
                const indx = y * width + x;
                if (indx < data_copy.len and indx >= 0) data_copy[y * width + x] = scaled_pixels[i * scaled_width + j];
            }
        }
        self.allocator.free(scaled_pixels);
        const old_data = self.data;
        const old_width = self.width;
        const old_height = self.height;
        self.data = data_copy;
        self.height = height;
        self.width = width;
        self.data = try self.gaussian_blur(6);
        self.allocator.free(data_copy);
        scaled_width = @divFloor(width, scale_factor);
        scaled_height = @divFloor(height, scale_factor);
        scaled_pixels = try self.bicubic(scaled_width, scaled_height);
        self.allocator.free(self.data);
        self.data = old_data;
        self.height = old_height;
        self.width = old_width;
        return .{ .width = scaled_width, .height = scaled_height, .data = scaled_pixels };
    }

    fn inv_lerp_point(a_x: f32, a_y: f32, b_x: f32, b_y: f32, v_x: f32, v_y: f32) f32 {
        if (@abs(a_x - b_x) > @abs(a_y - b_y)) {
            return inv_lerp(a_x, b_x, v_x);
        } else {
            return inv_lerp(a_y, b_y, v_y);
        }
    }

    fn inv_lerp(a: f32, b: f32, v: f32) f32 {
        return (v - a) / (b - a);
    }

    fn distance(a_x: f32, a_y: f32, b_x: f32, b_y: f32) f32 {
        return @sqrt((a_x - b_x) * (a_x - b_x) + (a_y - b_y) * (a_y - b_y));
    }

    pub fn rotate(self: *const Self, degrees: f32) Error!struct { width: u32, height: u32, data: []Pixel } {
        const radians: f32 = std.math.degreesToRadians(degrees);
        var x_1 = -@as(f32, @floatFromInt(self.width / 2));
        var y_1 = -@as(f32, @floatFromInt(self.height / 2));
        var points: [4]struct { x: f32, y: f32 } = undefined;
        points[0] = .{
            .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
            .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
        };
        x_1 = -@as(f32, @floatFromInt(self.width / 2));
        y_1 = @as(f32, @floatFromInt(self.height / 2));
        points[1] = .{
            .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
            .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
        };
        x_1 = @as(f32, @floatFromInt(self.width / 2));
        y_1 = @as(f32, @floatFromInt(self.height / 2));
        points[2] = .{
            .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
            .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
        };
        x_1 = @as(f32, @floatFromInt(self.width / 2));
        y_1 = -@as(f32, @floatFromInt(self.height / 2));
        points[3] = .{
            .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
            .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
        };
        var min_x: f32 = points[0].x;
        var max_x: f32 = points[0].x;
        var min_y: f32 = points[0].y;
        var max_y: f32 = points[0].y;
        for (1..points.len) |i| {
            min_x = @min(min_x, points[i].x);
            max_x = @max(max_x, points[i].x);
            min_y = @min(min_y, points[i].y);
            max_y = @max(max_y, points[i].y);
        }
        const width = @as(u32, @intFromFloat(@round(max_x - min_x)));
        const height = @as(u32, @intFromFloat(@round(max_y - min_y)));
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        for (0..data_copy.len) |i| {
            data_copy[i] = Pixel{};
        }
        var vectors: []Mat(3).Vec = try self.allocator.alloc(Mat(3).Vec, width * height);
        defer self.allocator.free(vectors);
        var translate_mat = try Mat(3).translate(-@as(f32, @floatFromInt((width - 1) / 2)), -@as(f32, @floatFromInt((height - 1) / 2)));
        const rotate_mat = try Mat(3).rotate(.z, -degrees);
        for (0..height) |i| {
            for (0..width) |j| {
                vectors[i * width + j] = rotate_mat.mul_v(translate_mat.mul_v(try Mat(3).vectorize(.{ @as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)) })));
            }
        }
        translate_mat = try Mat(3).translate(@as(f32, @floatFromInt((self.width - 1) / 2)), @as(f32, @floatFromInt((self.height - 1) / 2)));
        for (0..height) |i| {
            for (0..width) |j| {
                vectors[i * width + j] = translate_mat.mul_v(vectors[i * width + j]);
            }
        }
        for (0..height) |i| {
            for (0..width) |j| {
                if (vectors[i * width + j][0] < 0 or vectors[i * width + j][1] < 0) continue;
                const floored_x = @floor(vectors[i * width + j][0]);
                const floored_y = @floor(vectors[i * width + j][1]);
                const ceil_x = @ceil(vectors[i * width + j][0]);
                const ceil_y = @ceil(vectors[i * width + j][1]);
                var min_x_overlap: usize = undefined;
                var min_y_overlap: usize = undefined;
                var max_x_overlap: usize = undefined;
                var max_y_overlap: usize = undefined;
                if (floored_x >= 0) min_x_overlap = @as(usize, @intFromFloat(floored_x));
                if (floored_y >= 0) min_y_overlap = @as(usize, @intFromFloat(floored_y));
                if (ceil_x >= 0) max_x_overlap = @as(usize, @intFromFloat(ceil_x));
                if (ceil_y >= 0) max_y_overlap = @as(usize, @intFromFloat(ceil_y));
                const x_per = vectors[i * width + j][0] - @floor(vectors[i * width + j][0]);
                const y_per = vectors[i * width + j][1] - @floor(vectors[i * width + j][1]);
                var average_pixel: struct { r: f32, g: f32, b: f32, a: f32 } = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
                var weight: f32 = 0;
                var indx: usize = 0;
                if (floored_x >= 0 and floored_y >= 0) {
                    indx = min_y_overlap * self.width + min_x_overlap;
                    if (indx < self.data.len and indx >= 0 and min_y_overlap < self.height and min_x_overlap < self.width) {
                        const scale = ((1 - x_per) * (1 - y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (ceil_x >= 0 and floored_y >= 0) {
                    indx = min_y_overlap * self.width + max_x_overlap;
                    if (indx < self.data.len and indx >= 0 and min_y_overlap < self.height and max_x_overlap < self.width) {
                        const scale = ((x_per) * (1 - y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (floored_x >= 0 and ceil_y >= 0) {
                    indx = max_y_overlap * self.width + min_x_overlap;
                    if (indx < self.data.len and indx >= 0 and max_y_overlap < self.height and min_x_overlap < self.width) {
                        const scale = ((1 - x_per) * (y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (ceil_y >= 0 and ceil_x >= 0) {
                    indx = max_y_overlap * self.width + max_x_overlap;
                    if (indx < self.data.len and indx >= 0 and max_y_overlap < self.height and max_x_overlap < self.width) {
                        const scale = ((x_per) * (y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (weight != 0) {
                    data_copy[i * width + j].set_r(@as(u8, @intFromFloat(average_pixel.r / weight)));
                    data_copy[i * width + j].set_g(@as(u8, @intFromFloat(average_pixel.g / weight)));
                    data_copy[i * width + j].set_b(@as(u8, @intFromFloat(average_pixel.b / weight)));
                    data_copy[i * width + j].set_a(@as(u8, @intFromFloat(average_pixel.a / weight)));
                }
            }
        }
        return .{ .width = width, .height = height, .data = data_copy };
    }
    pub fn shear(self: *const Self, c_x: f32, c_y: f32) Error!struct { width: u32, height: u32, data: []Pixel } {
        var corners: [4]Mat(3).Vec = undefined;
        corners[0] = .{ 0, 0, 1 };
        corners[1] = .{
            0,
            @as(f32, @floatFromInt(self.height)) - 1,
            1,
        };
        corners[2] = .{
            @as(f32, @floatFromInt(self.width)) - 1,
            0,
            1,
        };
        corners[3] = .{
            @as(f32, @floatFromInt(self.width)) - 1,
            @as(f32, @floatFromInt(self.height)) - 1,
            1,
        };
        const shear_forward = try Mat(3).shear(c_x, c_y);
        for (0..4) |i| {
            corners[i] = shear_forward.mul_v(corners[i]);
        }
        var min_x: f32 = corners[0][0];
        var max_x: f32 = corners[0][0];
        var min_y: f32 = corners[0][1];
        var max_y: f32 = corners[0][1];
        for (1..4) |i| {
            min_x = @min(min_x, corners[i][0]);
            max_x = @max(max_x, corners[i][0]);
            min_y = @min(min_y, corners[i][1]);
            max_y = @max(max_y, corners[i][1]);
        }
        const width = @as(u32, @intFromFloat(@round(max_x - min_x)));
        const height = @as(u32, @intFromFloat(@round(max_y - min_y)));
        var data_copy = try self.allocator.alloc(Pixel, width * height);
        for (0..data_copy.len) |i| {
            data_copy[i] = Pixel{};
        }
        var vectors: []Mat(3).Vec = try self.allocator.alloc(Mat(3).Vec, width * height);
        defer self.allocator.free(vectors);
        const shear_reverse = try Mat(3).shear(-c_x, -c_y);
        for (0..height) |i| {
            for (0..width) |j| {
                vectors[i * width + j] = shear_reverse.mul_v(try Mat(3).vectorize(.{ @as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(i)) }));
                if (vectors[i * width + j][0] < 0 or vectors[i * width + j][1] < 0) continue;
                const floored_x = @floor(vectors[i * width + j][0]);
                const floored_y = @floor(vectors[i * width + j][1]);
                const ceil_x = @ceil(vectors[i * width + j][0]);
                const ceil_y = @ceil(vectors[i * width + j][1]);
                var min_x_overlap: usize = undefined;
                var min_y_overlap: usize = undefined;
                var max_x_overlap: usize = undefined;
                var max_y_overlap: usize = undefined;
                if (floored_x >= 0) min_x_overlap = @as(usize, @intFromFloat(floored_x));
                if (floored_y >= 0) min_y_overlap = @as(usize, @intFromFloat(floored_y));
                if (ceil_x >= 0) max_x_overlap = @as(usize, @intFromFloat(ceil_x));
                if (ceil_y >= 0) max_y_overlap = @as(usize, @intFromFloat(ceil_y));
                const x_per = vectors[i * width + j][0] - @floor(vectors[i * width + j][0]);
                const y_per = vectors[i * width + j][1] - @floor(vectors[i * width + j][1]);
                var average_pixel: struct { r: f32, g: f32, b: f32, a: f32 } = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
                var weight: f32 = 0;
                var indx: usize = undefined;
                if (floored_x >= 0 and floored_y >= 0) {
                    indx = min_y_overlap * self.width + min_x_overlap;
                    if (indx < self.data.len and indx >= 0 and min_y_overlap < self.height and min_x_overlap < self.width) {
                        const scale = ((1 - x_per) * (1 - y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (ceil_x >= 0 and floored_y >= 0) {
                    indx = min_y_overlap * self.width + max_x_overlap;
                    if (indx < self.data.len and indx >= 0 and min_y_overlap < self.height and max_x_overlap < self.width) {
                        const scale = ((x_per) * (1 - y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (floored_x >= 0 and ceil_y >= 0) {
                    indx = max_y_overlap * self.width + min_x_overlap;
                    if (indx < self.data.len and indx >= 0 and max_y_overlap < self.height and min_x_overlap < self.width) {
                        const scale = ((1 - x_per) * (y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (ceil_y >= 0 and ceil_x >= 0) {
                    indx = max_y_overlap * self.width + max_x_overlap;
                    if (indx < self.data.len and indx >= 0 and max_y_overlap < self.height and max_x_overlap < self.width) {
                        const scale = ((x_per) * (y_per));
                        average_pixel.r += scale * @as(f32, @floatFromInt(self.data[indx].get_r()));
                        average_pixel.g += scale * @as(f32, @floatFromInt(self.data[indx].get_g()));
                        average_pixel.b += scale * @as(f32, @floatFromInt(self.data[indx].get_b()));
                        average_pixel.a += scale * @as(f32, @floatFromInt(self.data[indx].get_a()));
                        weight += scale;
                    }
                }
                if (weight != 0) {
                    data_copy[i * width + j].set_r(@as(u8, @intFromFloat(average_pixel.r / weight)));
                    data_copy[i * width + j].set_g(@as(u8, @intFromFloat(average_pixel.g / weight)));
                    data_copy[i * width + j].set_b(@as(u8, @intFromFloat(average_pixel.b / weight)));
                    data_copy[i * width + j].set_a(@as(u8, @intFromFloat(average_pixel.a / weight)));
                }
            }
        }
        return .{ .width = width, .height = height, .data = data_copy };
    }
    pub fn write_BMP(self: *const Self, file_name: []const u8) Error!void {
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
                var end_color: @Vector(4, f32) = .{ @as(f32, @floatFromInt(pixel.v[0])), @as(f32, @floatFromInt(pixel.v[1])), @as(f32, @floatFromInt(pixel.v[2])), @as(f32, @floatFromInt(pixel.v[3])) };
                if (pixel.get_a() != 255) {
                    const bkgd = 0;
                    end_color *= @as(@Vector(4, f32), @splat((@as(f32, @floatFromInt(pixel.get_a())) / 255.0)));
                    end_color += @as(@Vector(4, f32), @splat((1 - (@as(f32, @floatFromInt(pixel.get_a())) / 255.0)) * bkgd));
                }
                const r: u8 = @as(u8, @intFromFloat(end_color[0]));
                const g: u8 = @as(u8, @intFromFloat(end_color[1]));
                const b: u8 = @as(u8, @intFromFloat(end_color[2]));
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
    std.log.debug("{d} s elapsed.\n", .{@as(f32, @floatFromInt(timer.read())) / 1000000000.0});
    timer.reset();
}

pub fn Mat(comptime S: comptime_int) type {
    return struct {
        data: [S * S]f32 = undefined,
        size: usize = S,
        pub const Self = @This();
        pub const Vec = @Vector(S, f32);
        pub const Error = error{
            TransformationUndefined,
            ArgError,
        };
        pub fn print(self: *const Self) void {
            std.log.warn("{any}\n", .{self.data});
            for (0..S) |i| {
                const v: Vec = self.data[i * S .. i * S + S][0..S].*;
                std.log.warn("{any}\n", .{v});
            }
        }
        pub fn scale(s: f32) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = s;
            ret.data[1] = 0;
            ret.data[2] = 0;

            ret.data[S] = 0;
            ret.data[S + 1] = s;
            ret.data[S + 2] = 0;
            ret.fill_identity(2);
            return ret;
        }
        pub fn fill_identity(self: *Self, rc_start: usize) void {
            for (rc_start..S) |i| {
                for (0..S - 1) |j| {
                    self.data[j * S + i] = 0;
                    self.data[i * S + j] = 0;
                }
                self.data[i * S + i] = 1;
            }
        }

        pub fn clamp_vector(v: Vec, min: f32, max: f32) Vec {
            const min_v: Vec = @splat(min);
            const max_v: Vec = @splat(max);
            var pred: @Vector(S, bool) = v < min_v;
            var res: Vec = @select(f32, pred, min_v, v);
            pred = res > max_v;
            res = @select(f32, pred, max_v, res);
            return res;
        }

        pub fn fill_x(self: *Self, rc_start: usize, x: f32) void {
            for (rc_start..S) |i| {
                for (rc_start..S) |j| {
                    self.data[i * S + j] = x;
                }
            }
        }
        pub fn rotate(comptime axis: @Type(.EnumLiteral), degrees: f32) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            const rad = degrees * std.math.rad_per_deg;
            var ret = Self{};
            switch (axis) {
                .x => {
                    if (S < 4) return Error.TransformationUndefined;
                    ret.data[0] = 1;
                    ret.data[1] = 0;
                    ret.data[2] = 0;

                    ret.data[S] = 0;
                    ret.data[S + 1] = std.math.cos(rad);
                    ret.data[S + 2] = std.math.sin(rad);

                    ret.data[2 * S] = 0;
                    ret.data[2 * S + 1] = -std.math.sin(rad);
                    ret.data[2 * S + 2] = std.math.cos(rad);
                    ret.fill_identity(3);
                },
                .y => {
                    if (S < 4) return Error.TransformationUndefined;
                    ret.data[0] = std.math.cos(rad);
                    ret.data[1] = 0;
                    ret.data[2] = -std.math.sin(rad);

                    ret.data[S] = 0;
                    ret.data[S + 1] = 1;
                    ret.data[S + 2] = 0;

                    ret.data[2 * S] = std.math.sin(rad);
                    ret.data[2 * S + 1] = 0;
                    ret.data[2 * S + 2] = std.math.cos(rad);
                    ret.fill_identity(3);
                },
                .z => {
                    ret.data[0] = std.math.cos(rad);
                    ret.data[1] = -std.math.sin(rad);

                    ret.data[S] = std.math.sin(rad);
                    ret.data[S + 1] = std.math.cos(rad);
                    ret.fill_identity(2);
                },
                else => return Error.TransformationUndefined,
            }
            return ret;
        }
        pub fn shear(x: f32, y: f32) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 1;
            ret.data[1] = y;
            ret.data[2] = 0;

            ret.data[S] = x;
            ret.data[S + 1] = 1;
            ret.data[S + 2] = 0;
            ret.fill_identity(2);
            return ret;
        }
        pub fn translate(x: f32, y: f32) Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 1;
            ret.data[1] = 0;
            ret.data[2] = x;

            ret.data[S] = 0;
            ret.data[S + 1] = 1;
            ret.data[S + 2] = y;

            ret.data[2 * S] = 0;
            ret.data[2 * S + 1] = 0;
            ret.data[2 * S + 2] = 1;
            ret.fill_identity(3);
            return ret;
        }
        pub fn identity() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.fill_identity(0);
            return ret;
        }
        pub fn spatial_lowpass() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            return Self{ .data = [_]f32{1.0 / 9.0} ** (S * S) };
        }
        pub fn spatial_highpass() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = -1;
            ret.data[1] = -1;
            ret.data[2] = -1;

            ret.data[S] = -1;
            ret.data[S + 1] = 8;
            ret.data[S + 2] = -1;

            ret.data[2 * S] = -1;
            ret.data[2 * S + 1] = -1;
            ret.data[2 * S + 2] = -1;
            ret.fill_identity(3);
            return ret;
        }
        pub fn vectorize(args: anytype) Error!Vec {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .Struct) {
                @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
            }
            if (args_type_info.Struct.fields.len != S - 1) {
                return Error.ArgError;
            }
            var res: Vec = undefined;
            inline for (0..args_type_info.Struct.fields.len) |i| {
                res[i] = @field(args, args_type_info.Struct.fields[i].name);
            }
            res[S - 1] = 1;
            //std.log.warn("vectorized {any}\n", .{res});
            return res;
        }
        pub fn row(self: *const Self, r: usize) Mat(S).Vec {
            return self.data[r * S .. r * S + S][0..S].*;
        }
        pub fn mul_v(self: *const Self, v: Vec) Vec {
            var res: Vec = undefined;
            for (0..S) |i| {
                const mat_r: Vec = self.data[i * S .. i * S + S][0..S].*;
                res[i] = @reduce(.Add, mat_r * v);
            }
            //std.log.warn("matrix vector {any}\n", .{res});
            return res;
        }
        pub fn mul(self: *const Self, other: Self) Self {
            var res: Self = undefined;
            for (0..S) |i| {
                const mat_r: Vec = self.data[i * S .. i * S + S][0..S].*;
                for (0..S) |j| {
                    var mat_c: Vec = undefined;
                    for (0..S) |k| {
                        mat_c[k] = other.data[k * S + j];
                    }
                    res.data[i * S + j] = @reduce(.Add, mat_r * mat_c);
                }
            }
            std.log.debug("matrix matrix {any}\n", .{res.data});
            return res;
        }
        pub fn naive_mul(self: *const Self, other: Self) Self {
            var res: Self = undefined;
            for (0..S) |i| {
                for (0..S) |j| {
                    res.data[i * S + j] = 0;
                    //std.debug.print("C{d}{d} = ", .{ i, j });
                    for (0..S) |k| {
                        //std.debug.print("{d} x {d}", .{ self.data[i * S + k], other.data[k * S + j] });
                        res.data[i * S + j] += self.data[i * S + k] * other.data[k * S + j];
                        if (k < S - 1) {
                            //std.debug.print(" + ", .{});
                        }
                    }
                    //std.debug.print(" = {d}\n", .{res.data[i * S + j]});
                }
            }
            //std.log.warn("matrix matrix {any}\n", .{res.data});
            return res;
        }
        pub fn naive_mul_v(self: *const Self, v: [S]f32) [S]f32 {
            var res: [S]f32 = undefined;
            for (0..S) |i| {
                res[i] = 0;
                for (0..S) |j| {
                    res[i] += self.data[i * S + j] * v[j];
                }
            }
            //std.log.warn("matrix vector {any}\n", .{res});
            return res;
        }
    };
}

test "MATRIX" {
    const size: comptime_int = 3;
    const Matrix = Mat(size);
    var m: Matrix = undefined;
    for (0..size) |i| {
        for (0..size) |j| {
            m.data[i * size + j] = 2;
        }
    }
    m.print();
    var m2: Matrix = undefined;
    for (0..size) |i| {
        for (0..size) |j| {
            m2.data[i * size + j] = 2;
        }
    }
    m2.print();
    var v: @Vector(size, f32) = undefined;
    for (0..size) |i| {
        v[i] = 2;
    }
    var v_a: [size]f32 = undefined;
    for (0..size) |i| {
        v_a[i] = 2;
    }
    try timer_start();
    _ = m.mul_v(v);
    timer_end();
    try timer_start();
    _ = m.naive_mul_v(v_a);
    timer_end();
    try timer_start();
    _ = m.mul(m2);
    timer_end();
    try timer_start();
    _ = m.naive_mul(m2);
    timer_end();

    const rotate = try Matrix.rotate(.z, 45);
    rotate.print();
    _ = rotate.mul_v(.{ 5, 5, 1 });

    _ = try Matrix.vectorize(.{ 2, 4 });

    const scale = try Mat(4).scale(5);
    scale.print();
}

pub const Pixel = struct {
    v: vec4 = .{ 0, 0, 0, 255 },
    pub const vec4 = @Vector(4, u8);
    pub fn init(r: u8, g: u8, b: u8, a: ?u8) Pixel {
        return Pixel{
            .v = .{
                r, g, b, if (a == null) 255 else a.?,
            },
        };
    }
    pub inline fn get_r(self: *const Pixel) u8 {
        return self.v[0];
    }
    pub inline fn set_r(self: *Pixel, val: u8) void {
        self.v[0] = val;
    }
    pub inline fn get_b(self: *const Pixel) u8 {
        return self.v[2];
    }
    pub inline fn set_b(self: *Pixel, val: u8) void {
        self.v[2] = val;
    }
    pub inline fn get_g(self: *const Pixel) u8 {
        return self.v[1];
    }
    pub inline fn set_g(self: *Pixel, val: u8) void {
        self.v[1] = val;
    }
    pub inline fn get_a(self: *const Pixel) u8 {
        return self.v[3];
    }
    pub inline fn set_a(self: *Pixel, val: u8) void {
        self.v[3] = val;
    }
    pub fn eql(self: *Pixel, other: Pixel) bool {
        return @reduce(.And, self.v == other.v);
    }
};

pub fn max_array(comptime T: type, arr: []T) T {
    if (arr.len == 1) {
        return arr[0];
    } else if (arr.len == 0) {
        unreachable;
    }
    var max_t: T = arr[0];
    for (1..arr.len) |i| {
        if (arr[i] > max_t) {
            max_t = arr[i];
        }
    }
    return max_t;
}

pub fn write_little_endian(file: *const std.fs.File, num_bytes: comptime_int, i: u32) std.fs.File.Writer.Error!void {
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
        pub const Error = error{} || std.mem.Allocator.Error;
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
        pub fn init(allocator: std.mem.Allocator) Error!HuffmanTree(T) {
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
        pub fn insert(self: *Self, codeword: T, n: T, symbol: T) Error!void {
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

// Small utility struct that gives basic byte by byte reading of a file after its been loaded into memory
pub const ByteStream = struct {
    index: usize = 0,
    buffer: []u8 = undefined,
    allocator: std.mem.Allocator = undefined,
    own_data: bool = false,
    pub const Error = error{ OutOfBounds, InvalidArgs, FileTooBig } || std.fs.File.OpenError || std.mem.Allocator.Error || std.fs.File.Reader.Error;
    pub fn init(options: anytype) Error!ByteStream {
        const ArgsType = @TypeOf(options);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            return Error.InvalidArgs;
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
            return Error.InvalidArgs;
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
            return Error.OutOfBounds;
        }
        return self.buffer[self.index];
    }
    pub fn readByte(self: *ByteStream) Error!u8 {
        if (self.index > self.buffer.len - 1) {
            return Error.OutOfBounds;
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
        InvalidRead,
        InvalidArgs,
    } || ByteStream.Error;

    pub fn init(options: anytype) Error!BitReader {
        var bit_reader: BitReader = BitReader{};
        bit_reader.byte_stream = try ByteStream.init(options);
        try bit_reader.set_options(options);
        return bit_reader;
    }

    pub fn set_options(self: *Self, options: anytype) Error!void {
        const ArgsType = @TypeOf(options);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .Struct) {
            return Error.InvalidArgs;
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

    pub fn read(self: *Self, comptime T: type) Error!T {
        self.next_bit = 0;
        var ret: T = undefined;
        switch (T) {
            u8 => {
                ret = try self.byte_stream.readByte();
            },
            i8 => {
                ret = @as(i8, @bitCast(try self.byte_stream.readByte()));
            },
            u16 => {
                ret = @as(u16, @intCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    ret |= @as(u16, @intCast(try self.byte_stream.readByte())) << 8;
                } else {
                    ret <<= 8;
                    ret += try self.byte_stream.readByte();
                }
            },
            i16 => {
                ret = @as(i16, @bitCast(@as(u16, @intCast(try self.byte_stream.readByte()))));
                if (self.little_endian) {
                    ret |= @as(i16, @bitCast(@as(u16, @intCast(try self.byte_stream.readByte())))) << 8;
                } else {
                    ret <<= 8;
                    ret += try self.byte_stream.readByte();
                }
            },
            u32 => {
                ret = @as(u32, @intCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte())) << 24;
                } else {
                    ret <<= 24;
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(u32, @intCast(try self.byte_stream.readByte()));
                }
            },
            i32 => {
                ret = @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte()))));
                if (self.little_endian) {
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte())))) << 8;
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte())))) << 16;
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte())))) << 24;
                } else {
                    ret <<= 24;
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte())))) << 16;
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte())))) << 8;
                    ret |= @as(i32, @bitCast(@as(u32, @intCast(try self.byte_stream.readByte()))));
                }
            },
            u64 => {
                ret = @as(u64, @intCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 24;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 32;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 40;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 48;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 56;
                } else {
                    ret <<= 56;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 48;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 40;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 32;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 24;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(u64, @intCast(try self.byte_stream.readByte()));
                }
            },
            usize => {
                ret = @as(usize, @intCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 24;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 32;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 40;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 48;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 56;
                } else {
                    ret <<= 56;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 48;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 40;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 32;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 24;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 16;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte())) << 8;
                    ret |= @as(usize, @intCast(try self.byte_stream.readByte()));
                }
            },
            i64 => {
                ret = @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte()))));
                if (self.little_endian) {
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 8;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 16;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 24;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 32;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 40;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 48;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 56;
                } else {
                    ret <<= 56;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 48;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 40;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 32;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 24;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 16;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte())))) << 8;
                    ret |= @as(i64, @bitCast(@as(u64, @intCast(try self.byte_stream.readByte()))));
                }
            },
            f32 => {
                var float_imm: u32 = @as(u32, @bitCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte())) << 24;
                } else {
                    float_imm <<= 24;
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte())) << 16;
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte())) << 8;
                    float_imm |= @as(u32, @intCast(try self.byte_stream.readByte()));
                }
                ret = @as(f32, @floatFromInt(float_imm));
            },
            f64 => {
                var float_imm: u64 = @as(u64, @bitCast(try self.byte_stream.readByte()));
                if (self.little_endian) {
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 8;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 16;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 24;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 32;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 40;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 48;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 56;
                } else {
                    float_imm <<= 56;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 48;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 40;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 32;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 24;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 16;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte())) << 8;
                    float_imm |= @as(u64, @intCast(try self.byte_stream.readByte()));
                }
                ret = @as(f64, @floatFromInt(float_imm));
            },
            else => return Error.InvalidArgs,
        }
        return ret;
    }
    pub fn read_bit(self: *Self) Error!u32 {
        var bit: u32 = undefined;
        if (self.next_bit == 0) {
            if (!self.has_bits()) {
                return Error.InvalidRead;
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
                        return Error.InvalidRead;
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
    pub fn read_bits(self: *Self, length: u32) Error!u32 {
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
        std.log.warn("Leaked!\n", .{});
    }
}
