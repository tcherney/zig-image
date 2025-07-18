const std = @import("std");
const common = @import("common");

pub const Pixel = common.Pixel;
pub const Allocator = std.mem.Allocator;

inline fn gaussian_kernel(x: i32, y: i32, sigma: f64) f64 {
    const coeff: f64 = 1.0 / (2.0 * std.math.pi * sigma * sigma);
    const exponent: f64 = -(@as(f64, @floatFromInt(x)) * @as(f64, @floatFromInt(x)) + @as(f64, @floatFromInt(y)) * @as(f64, @floatFromInt(y))) / (2.0 * sigma * sigma);
    return coeff * std.math.exp(exponent);
}

fn gaussian_kernel_2d(allocator: std.mem.Allocator, sigma: f64) std.mem.Allocator.Error![]f64 {
    var kernel_size: u32 = @as(u32, @intFromFloat(@ceil(2 * sigma + 1)));
    if (kernel_size % 2 == 0) {
        kernel_size += 1;
    }
    var kernel_2d: []f64 = try allocator.alloc(f64, kernel_size * kernel_size);
    var sum: f64 = 0.0;
    for (0..kernel_size) |i| {
        for (0..kernel_size) |j| {
            const x: i32 = @as(i32, @intCast(@as(i64, @bitCast(j)))) - @divFloor(@as(i32, @bitCast(kernel_size)), 2);
            const y: i32 = @as(i32, @intCast(@as(i64, @bitCast(i)))) - @divFloor(@as(i32, @bitCast(kernel_size)), 2);
            const val: f64 = gaussian_kernel(x, y, sigma);
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
pub const ConvolMat = common.Mat(3, f64);
pub const AffinePosMat = common.Mat(3, f64);

pub const Error = error{FFTPow2} || std.mem.Allocator.Error || std.fs.File.Writer.Error || std.fs.File.OpenError || ConvolMat.Error;
const BicubicPixel = struct {
    r: f64 = 0,
    g: f64 = 0,
    b: f64 = 0,
    a: f64 = 255,
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
    pub fn scale(self: *const BicubicPixel, scalar: f64) BicubicPixel {
        return .{
            .r = self.r * scalar,
            .g = self.g * scalar,
            .b = self.b * scalar,
            .a = self.a * scalar,
        };
    }
};

pub fn bilinear(allocator: Allocator, data: []Pixel, width: u32, height: u32, n_width: u32, n_height: u32) Error![]Pixel {
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    const width_scale: f64 = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(n_width));
    const height_scale: f64 = @as(f64, @floatFromInt(height)) / @as(f64, @floatFromInt(n_height));
    for (0..n_height) |y| {
        for (0..n_width) |x| {
            const src_x: f64 = @as(f64, @floatFromInt(x)) * width_scale;
            const src_y: f64 = @as(f64, @floatFromInt(y)) * height_scale;
            const src_x_floor: f64 = @floor(src_x);
            const src_x_ceil: f64 = @min(@as(f64, @floatFromInt(width)) - 1.0, @ceil(src_x));
            const src_y_floor: f64 = @floor(src_y);
            const src_y_ceil: f64 = @min(@as(f64, @floatFromInt(height)) - 1.0, @ceil(src_y));
            const src_x_floor_indx: usize = @as(usize, @intFromFloat(src_x_floor));
            const src_x_ceil_indx: usize = @as(usize, @intFromFloat(src_x_ceil));
            const src_y_floor_indx: usize = @as(usize, @intFromFloat(src_y_floor));
            const src_y_ceil_indx: usize = @as(usize, @intFromFloat(src_y_ceil));
            var new_pixel: Pixel = Pixel{};
            if (src_x_ceil == src_x_floor and src_y_ceil == src_y_floor) {
                new_pixel.set_r(data[src_y_floor_indx * width + src_x_floor_indx].get_r());
                new_pixel.set_g(data[src_y_floor_indx * width + src_x_floor_indx].get_g());
                new_pixel.set_b(data[src_y_floor_indx * width + src_x_floor_indx].get_b());
                new_pixel.set_a(data[src_y_floor_indx * width + src_x_floor_indx].get_a());
            } else if (src_x_ceil == src_x_floor) {
                const q1 = data[src_y_floor_indx * width + src_x_floor_indx];
                const q2 = data[src_y_ceil_indx * width + src_x_floor_indx];
                new_pixel.set_r(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_r())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_r())) * (src_y - src_y_floor)))));
                new_pixel.set_g(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_g())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_g())) * (src_y - src_y_floor)))));
                new_pixel.set_b(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_b())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_b())) * (src_y - src_y_floor)))));
                new_pixel.set_a(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_a())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_a())) * (src_y - src_y_floor)))));
            } else if (src_y_ceil == src_y_floor) {
                const q1 = data[src_y_floor_indx * width + src_x_floor_indx];
                const q2 = data[src_y_ceil_indx * width + src_x_ceil_indx];
                new_pixel.set_r(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_r())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(q2.get_r())) * (src_x - src_x_floor)))));
                new_pixel.set_g(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_g())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(q2.get_g())) * (src_x - src_x_floor)))));
                new_pixel.set_b(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_b())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(q2.get_b())) * (src_x - src_x_floor)))));
                new_pixel.set_a(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_a())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(q2.get_a())) * (src_x - src_x_floor)))));
            } else {
                const v1 = data[src_y_floor_indx * width + src_x_floor_indx];
                const v2 = data[src_y_floor_indx * width + src_x_ceil_indx];
                const v3 = data[src_y_ceil_indx * width + src_x_floor_indx];
                const v4 = data[src_y_ceil_indx * width + src_x_ceil_indx];

                const q1 = Pixel.init(
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v1.get_r())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v2.get_r())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v1.get_g())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v2.get_g())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v1.get_b())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v2.get_b())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v1.get_a())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v2.get_a())) * (src_x - src_x_floor)))),
                );
                const q2 = Pixel.init(
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v3.get_r())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v4.get_r())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v3.get_g())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v4.get_g())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v3.get_b())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v4.get_b())) * (src_x - src_x_floor)))),
                    @as(u8, @intFromFloat((@as(f64, @floatFromInt(v3.get_a())) * (src_x_ceil - src_x)) + (@as(f64, @floatFromInt(v4.get_a())) * (src_x - src_x_floor)))),
                );
                new_pixel.set_r(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_r())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_r())) * (src_y - src_y_floor)))));
                new_pixel.set_g(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_g())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_g())) * (src_y - src_y_floor)))));
                new_pixel.set_b(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_b())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_b())) * (src_y - src_y_floor)))));
                new_pixel.set_a(@as(u8, @intFromFloat((@as(f64, @floatFromInt(q1.get_a())) * (src_y_ceil - src_y)) + (@as(f64, @floatFromInt(q2.get_a())) * (src_y - src_y_floor)))));
            }

            data_copy[y * n_width + x].v = new_pixel.v;
        }
    }
    return data_copy;
}
fn bicubic_get_pixel(data: []Pixel, width: u32, height: u32, y: i64, x: i64) BicubicPixel {
    if (x < width and y < height and x > 0 and y > 0) {
        const y_usize = if (@sizeOf(usize) == 8) @as(usize, @bitCast(y)) else @as(usize, @bitCast(@as(i32, @intCast(y))));
        const x_usize = if (@sizeOf(usize) == 8) @as(usize, @bitCast(x)) else @as(usize, @bitCast(@as(i32, @intCast(x))));
        return BicubicPixel{
            .r = @as(f64, @floatFromInt(data[y_usize * width + x_usize].get_r())),
            .g = @as(f64, @floatFromInt(data[y_usize * width + x_usize].get_g())),
            .b = @as(f64, @floatFromInt(data[y_usize * width + x_usize].get_b())),
            .a = @as(f64, @floatFromInt(data[y_usize * width + x_usize].get_a())),
        };
    } else {
        return BicubicPixel{};
    }
}
pub fn bicubic(allocator: Allocator, data: []Pixel, width: u32, height: u32, n_width: u32, n_height: u32) Error![]Pixel {
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    const width_scale: f64 = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(n_width));
    const height_scale: f64 = @as(f64, @floatFromInt(height)) / @as(f64, @floatFromInt(n_height));
    var C: [5]BicubicPixel = undefined;
    for (0..5) |i| {
        C[i] = BicubicPixel{};
    }
    for (0..n_height) |y| {
        for (0..n_width) |x| {
            const src_x: i64 = @as(i64, @intFromFloat(@as(f64, @floatFromInt(x)) * width_scale));
            const src_y: i64 = @as(i64, @intFromFloat(@as(f64, @floatFromInt(y)) * height_scale));
            const dx: f64 = width_scale * @as(f64, @floatFromInt(x)) - @as(f64, @floatFromInt(src_x));
            const dy: f64 = height_scale * @as(f64, @floatFromInt(y)) - @as(f64, @floatFromInt(src_y));
            var new_pixel: BicubicPixel = BicubicPixel{};
            for (0..4) |jj| {
                const jj_i64 = if (@sizeOf(usize) == 8) @as(i64, @bitCast(jj)) else @as(i64, @bitCast(@as(u64, @intCast(jj))));
                const z: i64 = src_y + jj_i64 - 1;
                const a0 = bicubic_get_pixel(data, width, height, z, src_x);
                const d0 = bicubic_get_pixel(data, width, height, z, src_x - 1).sub(a0);
                const d2 = bicubic_get_pixel(data, width, height, z, src_x + 1).sub(a0);
                const d3 = bicubic_get_pixel(data, width, height, z, src_x + 2).sub(a0);

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
            data_copy[y * n_width + x].v = .{ @as(u8, @intFromFloat(new_pixel.r)), @as(u8, @intFromFloat(new_pixel.b)), @as(u8, @intFromFloat(new_pixel.b)), @as(u8, @intFromFloat(new_pixel.a)) };
        }
    }

    return data_copy;
}
pub fn gaussian_blur(allocator: Allocator, data: []Pixel, width: u32, height: u32, sigma: f64) Error![]Pixel {
    const kernel_2d = try gaussian_kernel_2d(allocator, sigma);
    defer allocator.free(kernel_2d);
    var kernel_size: u32 = @as(u32, @intFromFloat(@ceil(2 * sigma + 1)));
    if (kernel_size % 2 == 0) {
        kernel_size += 1;
    }
    var data_copy: []Pixel = try allocator.alloc(Pixel, data.len);
    for (kernel_size / 2..height - kernel_size / 2) |y| {
        for (kernel_size / 2..width - kernel_size / 2) |x| {
            var r: f64 = 0.0;
            var g: f64 = 0.0;
            var b: f64 = 0.0;
            var a: f64 = 0.0;
            for (0..kernel_size) |i| {
                for (0..kernel_size) |j| {
                    var curr_pixel: Pixel = undefined;

                    curr_pixel = data[(y + i - kernel_size / 2) * width + (x + j - kernel_size / 2)];

                    r += kernel_2d[i * kernel_size + j] * @as(f64, @floatFromInt(curr_pixel.get_r()));
                    g += kernel_2d[i * kernel_size + j] * @as(f64, @floatFromInt(curr_pixel.get_g()));
                    b += kernel_2d[i * kernel_size + j] * @as(f64, @floatFromInt(curr_pixel.get_b()));
                    a += kernel_2d[i * kernel_size + j] * @as(f64, @floatFromInt(curr_pixel.get_a()));
                }
            }

            data_copy[y * width + x].v = .{ @as(u8, @intFromFloat(r)), @as(u8, @intFromFloat(g)), @as(u8, @intFromFloat(b)), @as(u8, @intFromFloat(a)) };
        }
    }
    return data_copy;
}
pub fn nearest_neighbor(allocator: Allocator, data: []Pixel, width: u32, height: u32, n_width: usize, n_height: usize) Error![]Pixel {
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    for (0..n_height) |y| {
        for (0..n_width) |x| {
            const src_x: usize = @min(width - 1, @as(usize, @intFromFloat(@as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(n_width)) * @as(f64, @floatFromInt(width)))));
            const src_y: usize = @min(height - 1, @as(usize, @intFromFloat(@as(f64, @floatFromInt(y)) / @as(f64, @floatFromInt(n_height)) * @as(f64, @floatFromInt(height)))));
            data_copy[y * n_width + x].v = data[src_y * width + src_x].v;
        }
    }
    return data_copy;
}
pub fn grayscale(allocator: Allocator, data: []Pixel) Error![]Pixel {
    var data_copy = try allocator.dupe(Pixel, data);
    for (0..data_copy.len) |i| {
        const gray: u8 = @as(u8, @intFromFloat(@as(f64, @floatFromInt(data_copy[i].get_r())) * 0.2989)) + @as(u8, @intFromFloat(@as(f64, @floatFromInt(data_copy[i].get_g())) * 0.5870)) + @as(u8, @intFromFloat(@as(f64, @floatFromInt(data_copy[i].get_b())) * 0.1140));
        data_copy[i].v = .{ gray, gray, gray, data_copy[i].get_a() };
    }
    return data_copy;
}
//TODO add more image processing functions https://en.wikipedia.org/wiki/Digital_image_processing
pub fn histogram_equalization(allocator: Allocator, data: []Pixel, width: u32, height: u32) Error![]Pixel {
    var data_copy = try allocator.dupe(Pixel, data);
    const num_channels = 3;
    var channel_cdf: [num_channels][256]f64 = undefined;
    for (0..num_channels) |i| {
        const histo = histogram(data, width, height, 0);
        const cdf = gen_cdf(histo);
        channel_cdf[i] = normalize_hist(data, cdf);
        //std.debug.print("channel_cdf {any}\n", .{channel_cdf[i]});
    }

    for (0..height) |i| {
        for (0..width) |j| {
            const indx = i * width + j;
            for (0..num_channels) |k| {
                const pix_val = data[indx].v[k];
                //std.debug.print("cdf val, ceil, -1 {d}, {d}, {d}\n", .{ channel_cdf[k][pix_val], @ceil(channel_cdf[k][pix_val] * 256.0), @ceil(channel_cdf[k][pix_val] * 256.0) - 1 });
                var equal_comp: f64 = @ceil(channel_cdf[k][pix_val] * 256.0) - 1;
                if (equal_comp < 0) equal_comp = 0;
                data_copy[indx].v[k] = @as(u8, @intFromFloat(equal_comp));
            }
        }
    }
    return data_copy;
}
fn normalize_hist(data: []Pixel, histo: [256]u32) [256]f64 {
    var ret: [256]f64 = undefined;
    for (0..histo.len) |i| {
        ret[i] = @as(f64, @floatFromInt(histo[i])) / @as(f64, @floatFromInt(data.len));
    }
    return ret;
}
fn gen_cdf(histo: [256]u32) [256]u32 {
    var ret: [256]u32 = [_]u32{0} ** 256;
    var sum: u32 = 0;
    for (0..ret.len) |i| {
        sum += histo[i];
        ret[i] = sum;
    }
    return ret;
}
fn histogram(data: []Pixel, width: u32, height: u32, channel: usize) [256]u32 {
    var ret: [256]u32 = undefined;
    for (0..ret.len) |i| {
        ret[i] = 0;
    }
    for (0..height) |i| {
        for (0..width) |j| {
            ret[data[i * width + j].v[channel]] += 1;
        }
    }
    return ret;
}

pub fn edge_detection(allocator: Allocator, data: []Pixel, width: u32, height: u32) Error![]Pixel {
    const edge_detect_mat = try ConvolMat.edge_detection();
    return try convol(allocator, data, width, height, edge_detect_mat);
}
pub const Complex = std.math.complex.Complex(f64);
pub fn fft_convol(allocator: Allocator, data: []Pixel, width: u32, height: u32, is_grayscale: bool, kernel: ConvolMat) Error![]Pixel {
    const bits: usize = @intFromFloat(@ceil(std.math.log(f64, 2, @floatFromInt(data.len))));
    const size_pow = std.math.log(usize, 2, data.len);
    var buf_len: usize = data.len;
    if (bits != size_pow) {
        buf_len = std.math.pow(usize, 2, bits);
    }
    const num_channels: usize = if (is_grayscale) 1 else 3;
    var fft_buf: [][]Complex = try allocator.alloc([]Complex, num_channels);
    var fft_buf_copy: [][]Complex = try allocator.alloc([]Complex, num_channels);
    for (0..num_channels) |c| {
        fft_buf[c] = try allocator.alloc(Complex, buf_len);
        fft_buf_copy[c] = try allocator.alloc(Complex, buf_len);
    }
    for (0..height) |i| {
        for (0..width) |j| {
            const indx = i * width + j;
            for (0..num_channels) |c| {
                fft_buf[c][indx] = Complex.init(@as(f64, @floatFromInt(data[indx].v[c])), 0);
                fft_buf_copy[c][indx] = Complex.init(@as(f64, @floatFromInt(data[indx].v[c])), 0);
            }
        }
    }
    for (0..num_channels) |j| {
        for (data.len..fft_buf[j].len) |i| {
            fft_buf[j][i] = Complex.init(0, 0);
            fft_buf_copy[j][i] = Complex.init(0, 0);
        }
    }
    // -> frequency space
    for (0..num_channels) |c| {
        try fft(fft_buf[c]);
    }
    // -> convol
    var kernel_buf = try allocator.alloc(Complex, buf_len);
    for (0..kernel.size) |i| {
        for (0..kernel.size) |j| {
            const indx = i * kernel.size + j;
            kernel_buf[indx] = Complex.init(kernel.data[indx], 0);
        }
    }
    for ((kernel.size * kernel.size)..kernel_buf.len) |i| {
        kernel_buf[i] = Complex.init(0, 0);
    }
    try fft(kernel_buf);
    for (0..height) |i| {
        for (0..width) |j| {
            const indx: usize = (i * width + j);
            for (0..num_channels) |c| {
                fft_buf_copy[c][indx] = fft_buf[c][indx].mul(kernel_buf[indx]);
            }
        }
    }
    for (0..num_channels) |j| {
        for (data.len..fft_buf[j].len) |i| {
            fft_buf_copy[j][i] = fft_buf[j][i].mul(kernel_buf[i]);
        }
    }
    allocator.free(kernel_buf);
    for (0..num_channels) |i| {
        allocator.free(fft_buf[i]);
    }
    allocator.free(fft_buf);
    // -> back to color space
    for (0..num_channels) |c| {
        try ifft(fft_buf_copy[c]);
    }
    var data_copy = try allocator.dupe(Pixel, data);
    for (0..height) |i| {
        for (0..width) |j| {
            for (0..num_channels) |c| {
                data_copy[i * width + j].v[c] = if (fft_buf_copy[c][i * width + j].re > 255) 255 else if (fft_buf_copy[c][i * width + j].re < 0) 0 else @as(u8, @intFromFloat(fft_buf_copy[c][i * width + j].re));
            }
        }
    }
    for (0..num_channels) |i| {
        allocator.free(fft_buf_copy[i]);
    }
    allocator.free(fft_buf_copy);
    return data_copy;
}
pub fn fft_bit_reverse(n: usize, bits: usize) usize {
    var reversed_n: usize = n;
    var count: usize = bits - 1;
    var n_cpy: isize = @bitCast(n);
    n_cpy >>= 1;
    while (n_cpy > 0) {
        reversed_n = (reversed_n << 1) | (@as(usize, @bitCast(n_cpy)) & 1);
        count -= 1;
        n_cpy >>= 1;
    }
    return ((reversed_n << @as(u6, @intCast(count))) & ((@as(usize, @intCast(1)) << @as(u6, @intCast(bits))) - 1));
}
fn is_pow_2(x: usize) bool {
    return (x != 0) and ((x & (x - 1)) == 0);
}
pub fn ifft(buf: []Complex) Error!void {
    if (!is_pow_2(buf.len)) return Error.FFTPow2;
    for (0..buf.len) |i| {
        if (buf[i].im != 0) buf[i].im = -buf[i].im;
    }
    try fft(buf);
    for (0..buf.len) |i| {
        buf[i].im = -buf[i].im;
        buf[i].re /= @floatFromInt(buf.len);
        buf[i].im /= @floatFromInt(buf.len);
    }
}
pub fn fft(buf: []Complex) Error!void {
    if (!is_pow_2(buf.len)) return Error.FFTPow2;
    const bits: usize = std.math.log(usize, 2, buf.len);
    for (1..buf.len) |i| {
        const indx = fft_bit_reverse(i, bits);
        if (indx <= i) continue;
        const temp = buf[i];
        buf[i] = buf[indx];
        buf[indx] = temp;
    }
    var N: usize = 2;
    while (N <= buf.len) : (N <<= 1) {
        var i: usize = 0;
        while (i < buf.len) : (i += N) {
            for (0..(N / 2)) |k| {
                const even_indx = i + k;
                const odd_indx = i + k + (N / 2);
                const even = Complex.init(buf[even_indx].re, buf[even_indx].im);
                const odd = Complex.init(buf[odd_indx].re, buf[odd_indx].im);
                const term: f64 = -2 * std.math.pi * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(N));
                const exp: Complex = std.math.complex.exp(Complex.init(0, term)).mul(odd);
                buf[even_indx] = even.add(exp);
                buf[odd_indx] = even.sub(exp);
            }
        }
    }
}

pub fn fft_rep(allocator: Allocator, data: []Pixel, width: u32, height: u32) Error![]Pixel {
    const gray_data = try grayscale(allocator, data);
    const bits: usize = @intFromFloat(@ceil(std.math.log(f64, 2, @floatFromInt(data.len))));
    const size_pow = std.math.log(usize, 2, data.len);
    var buf_len: usize = data.len;
    if (bits != size_pow) {
        buf_len = std.math.pow(usize, 2, bits);
    }
    var fft_buf: []Complex = try allocator.alloc(Complex, buf_len);
    for (0..height) |i| {
        for (0..width) |j| {
            const indx = i * width + j;
            //centers fft
            fft_buf[indx] = Complex.init(@as(f64, @floatFromInt(data[indx].v[0])) * std.math.pow(
                f64,
                -1,
                @floatFromInt(i + j),
            ), 0);
        }
    }
    for (data.len..fft_buf.len) |i| {
        fft_buf[i] = Complex.init(0, 0);
    }
    allocator.free(gray_data);
    try fft(fft_buf);
    var data_copy = try allocator.dupe(Pixel, data);
    var max_mag: f64 = fft_buf[0].magnitude();
    for (1..data_copy.len) |i| {
        max_mag = @max(fft_buf[i].magnitude(), max_mag);
    }
    const c = 255.0 / (@log(1 + @abs(max_mag)));
    for (0..data_copy.len) |i| {
        const mag = c * @log(1 + @abs(fft_buf[i].magnitude()));
        const fft_val: u8 = if (mag > 255) 255 else if (mag < 0) 0 else @as(u8, @intFromFloat(mag));
        for (0..3) |j| {
            data_copy[i].v[j] = fft_val;
        }
    }
    allocator.free(fft_buf);
    return data_copy;
}
pub fn convol(allocator: Allocator, data: []Pixel, width: u32, height: u32, kernel: ConvolMat) Error![]Pixel {
    var data_copy = try allocator.dupe(Pixel, data);
    for (0..height) |i| {
        for (0..width) |j| {
            const indx: usize = (i * width + j);
            if (i >= 1 and j >= 1 and i < height - 1 and j < width - 1) {
                for (0..3) |c| {
                    var sum: f64 = 0;
                    for (0..3) |k| {
                        const float_vector: ConvolMat.Vec = .{ @floatFromInt(data[indx - width - 1 + k].v[c]), @floatFromInt(data[indx - 1 + k].v[c]), @floatFromInt(data[indx + width - 1 + k].v[c]) };
                        sum += @reduce(.Add, float_vector * kernel.row(k));
                    }
                    data_copy[indx].v[c] = if (sum > 255) 255 else if (sum < 0) 0 else @as(u8, @intFromFloat(sum));
                }
            } else {
                data_copy[indx] = Pixel.init(0, 0, 0, null);
            }
        }
    }
    return data_copy;
}
//reflect along an axis x, y or both
pub fn reflection(allocator: Allocator, data: []Pixel, width: u32, height: u32, comptime axis: @Type(.enum_literal)) Error![]Pixel {
    var data_copy = try allocator.dupe(Pixel, data);
    errdefer allocator.free(data_copy);
    switch (axis) {
        .x => {
            for (0..height) |y| {
                for (0..width) |x| {
                    data_copy[y * width + x].v = data[y * width + (width - 1 - x)].v;
                }
            }
        },
        .y => {
            for (0..height) |y| {
                for (0..width) |x| {
                    data_copy[y * width + x].v = data[(height - 1 - y) * width + x].v;
                }
            }
        },
        .xy, .yx => {
            for (0..height) |y| {
                for (0..width) |x| {
                    data_copy[y * width + x].v = data[(height - 1 - y) * width + (width - 1 - x)].v;
                }
            }
        },
        else => unreachable,
    }
    return data_copy;
}
fn rotate_slow(allocator: Allocator, data: []Pixel, width: u32, height: u32, degrees: f64) Error!struct { width: u32, height: u32, data: []Pixel } {
    const scale_factor = 4;
    var scaled_width = width * scale_factor;
    var scaled_height = height * scale_factor;
    var scaled_pixels = try bicubic(data, width, height, scaled_width, scaled_height);
    const radians: f64 = std.math.degreesToRadians(degrees);
    const shear13 = try AffinePosMat.shear(0, -@tan(radians / 2));
    shear13.print();
    const shear2 = try AffinePosMat.shear(@sin(radians), 0);
    shear2.print();
    const rotate_mat = shear13.mul(shear2).mul(shear13);
    rotate_mat.print();
    const Vec = AffinePosMat.Vec;
    var vectors: []Vec = try allocator.alloc(Vec, scaled_pixels.len);
    defer allocator.free(vectors);
    var min_x: f64 = -@as(f64, @floatFromInt(scaled_width / 2));
    var max_x: f64 = @as(f64, @floatFromInt(scaled_width / 2)) - 1;
    var min_y: f64 = -@as(f64, @floatFromInt(scaled_height / 2));
    var max_y: f64 = @as(f64, @floatFromInt(scaled_height / 2)) - 1;
    var translate_mat = try AffinePosMat.translate(min_x, min_y);
    for (0..scaled_height) |i| {
        for (0..scaled_width) |j| {
            //vectors[i * width + j] = shear13.mul_v(shear2.mul_v(shear13.mul_v(try AffinePosMat.vectorize(.{ @as(f64, @floatFromInt(j)), @as(f64, @floatFromInt(i)) }))));
            vectors[i * scaled_width + j] = rotate_mat.mul_v(translate_mat.mul_v(try AffinePosMat.vectorize(.{ @as(f64, @floatFromInt(j)), @as(f64, @floatFromInt(i)) })));
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
    translate_mat = try AffinePosMat.translate(-min_x, -min_y);
    for (0..scaled_height) |i| {
        for (0..scaled_width) |j| {
            vectors[i * scaled_width + j] = translate_mat.mul_v(vectors[i * scaled_width + j]);
        }
    }
    //std.log.warn("translated {any}\n", .{vectors});
    const n_width = @as(u32, @intFromFloat(@ceil(max_x - min_x))) + 1;
    const n_height = @as(u32, @intFromFloat(@ceil(max_y - min_y))) + 1;
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    std.log.warn("min_x {d} max_x {d} min_y {d} max_y {d} width {d} height {d} len {d}\n", .{ min_x, max_x, min_y, max_y, n_width, n_height, data_copy.len });
    for (0..data_copy.len) |i| {
        data_copy[i] = Pixel{};
    }
    for (0..scaled_height) |i| {
        for (0..scaled_width) |j| {
            //std.log.warn("x coord {any}", .{vectors[i * width + j][0]});
            const x = @as(usize, @intFromFloat(@floor(vectors[i * scaled_width + j][0])));
            const y = @as(usize, @intFromFloat(@floor(vectors[i * scaled_width + j][1])));
            const indx = y * n_width + x;
            if (indx < data_copy.len and indx >= 0) data_copy[y * n_width + x] = scaled_pixels[i * scaled_width + j];
        }
    }
    allocator.free(scaled_pixels);

    const data_blur = try gaussian_blur(data_copy, n_width, n_height, 6);
    allocator.free(data_copy);
    scaled_width = @divFloor(n_width, scale_factor);
    scaled_height = @divFloor(n_height, scale_factor);
    scaled_pixels = try bicubic(data_blur, n_width, n_height, scaled_width, scaled_height);
    allocator.free(data_blur);
    return .{ .width = scaled_width, .height = scaled_height, .data = scaled_pixels };
}

fn inv_lerp_point(a_x: f64, a_y: f64, b_x: f64, b_y: f64, v_x: f64, v_y: f64) f64 {
    if (@abs(a_x - b_x) > @abs(a_y - b_y)) {
        return inv_lerp(a_x, b_x, v_x);
    } else {
        return inv_lerp(a_y, b_y, v_y);
    }
}

fn inv_lerp(a: f64, b: f64, v: f64) f64 {
    return (v - a) / (b - a);
}

fn distance(a_x: f64, a_y: f64, b_x: f64, b_y: f64) f64 {
    return @sqrt((a_x - b_x) * (a_x - b_x) + (a_y - b_y) * (a_y - b_y));
}

pub fn rotate(allocator: Allocator, data: []Pixel, width: u32, height: u32, degrees: f64) Error!struct { width: u32, height: u32, data: []Pixel } {
    const radians: f64 = std.math.degreesToRadians(degrees);
    var x_1 = -@as(f64, @floatFromInt(width / 2));
    var y_1 = -@as(f64, @floatFromInt(height / 2));
    var points: [4]struct { x: f64, y: f64 } = undefined;
    points[0] = .{
        .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
        .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
    };
    x_1 = -@as(f64, @floatFromInt(width / 2));
    y_1 = @as(f64, @floatFromInt(height / 2));
    points[1] = .{
        .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
        .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
    };
    x_1 = @as(f64, @floatFromInt(width / 2));
    y_1 = @as(f64, @floatFromInt(height / 2));
    points[2] = .{
        .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
        .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
    };
    x_1 = @as(f64, @floatFromInt(width / 2));
    y_1 = -@as(f64, @floatFromInt(height / 2));
    points[3] = .{
        .x = std.math.cos(radians) * (x_1) - std.math.sin(radians) * (y_1),
        .y = std.math.sin(radians) * (x_1) + std.math.cos(radians) * (y_1),
    };
    var min_x: f64 = points[0].x;
    var max_x: f64 = points[0].x;
    var min_y: f64 = points[0].y;
    var max_y: f64 = points[0].y;
    for (1..points.len) |i| {
        min_x = @min(min_x, points[i].x);
        max_x = @max(max_x, points[i].x);
        min_y = @min(min_y, points[i].y);
        max_y = @max(max_y, points[i].y);
    }
    const n_width = @as(u32, @intFromFloat(@round(max_x - min_x)));
    const n_height = @as(u32, @intFromFloat(@round(max_y - min_y)));
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    for (0..data_copy.len) |i| {
        data_copy[i] = Pixel{};
    }
    var vectors: []AffinePosMat.Vec = try allocator.alloc(AffinePosMat.Vec, n_width * n_height);
    defer allocator.free(vectors);
    var translate_mat = try AffinePosMat.translate(-@as(f64, @floatFromInt((n_width - 1) / 2)), -@as(f64, @floatFromInt((n_height - 1) / 2)));
    const rotate_mat = try AffinePosMat.rotate(.z, -degrees);
    for (0..n_height) |i| {
        for (0..n_width) |j| {
            vectors[i * n_width + j] = rotate_mat.mul_v(translate_mat.mul_v(try AffinePosMat.vectorize(.{ @as(f64, @floatFromInt(j)), @as(f64, @floatFromInt(i)) })));
        }
    }
    translate_mat = try AffinePosMat.translate(@as(f64, @floatFromInt((width - 1) / 2)), @as(f64, @floatFromInt((height - 1) / 2)));
    for (0..n_height) |i| {
        for (0..n_width) |j| {
            vectors[i * n_width + j] = translate_mat.mul_v(vectors[i * n_width + j]);
        }
    }
    for (0..n_height) |i| {
        for (0..n_width) |j| {
            if (vectors[i * n_width + j][0] < 0 or vectors[i * n_width + j][1] < 0) continue;
            const floored_x = @floor(vectors[i * n_width + j][0]);
            const floored_y = @floor(vectors[i * n_width + j][1]);
            const ceil_x = @ceil(vectors[i * n_width + j][0]);
            const ceil_y = @ceil(vectors[i * n_width + j][1]);
            var min_x_overlap: usize = undefined;
            var min_y_overlap: usize = undefined;
            var max_x_overlap: usize = undefined;
            var max_y_overlap: usize = undefined;
            if (floored_x >= 0) min_x_overlap = @as(usize, @intFromFloat(floored_x));
            if (floored_y >= 0) min_y_overlap = @as(usize, @intFromFloat(floored_y));
            if (ceil_x >= 0) max_x_overlap = @as(usize, @intFromFloat(ceil_x));
            if (ceil_y >= 0) max_y_overlap = @as(usize, @intFromFloat(ceil_y));
            const x_per = vectors[i * n_width + j][0] - @floor(vectors[i * n_width + j][0]);
            const y_per = vectors[i * n_width + j][1] - @floor(vectors[i * n_width + j][1]);
            var average_pixel: struct { r: f64, g: f64, b: f64, a: f64 } = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
            var weight: f64 = 0;
            var indx: usize = 0;
            if (floored_x >= 0 and floored_y >= 0) {
                indx = min_y_overlap * width + min_x_overlap;
                if (indx < data.len and indx >= 0 and min_y_overlap < height and min_x_overlap < width) {
                    const scale = ((1 - x_per) * (1 - y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (ceil_x >= 0 and floored_y >= 0) {
                indx = min_y_overlap * width + max_x_overlap;
                if (indx < data.len and indx >= 0 and min_y_overlap < height and max_x_overlap < width) {
                    const scale = ((x_per) * (1 - y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (floored_x >= 0 and ceil_y >= 0) {
                indx = max_y_overlap * width + min_x_overlap;
                if (indx < data.len and indx >= 0 and max_y_overlap < height and min_x_overlap < width) {
                    const scale = ((1 - x_per) * (y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (ceil_y >= 0 and ceil_x >= 0) {
                indx = max_y_overlap * width + max_x_overlap;
                if (indx < data.len and indx >= 0 and max_y_overlap < height and max_x_overlap < width) {
                    const scale = ((x_per) * (y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (weight != 0) {
                data_copy[i * n_width + j].set_r(@as(u8, @intFromFloat(average_pixel.r / weight)));
                data_copy[i * n_width + j].set_g(@as(u8, @intFromFloat(average_pixel.g / weight)));
                data_copy[i * n_width + j].set_b(@as(u8, @intFromFloat(average_pixel.b / weight)));
                data_copy[i * n_width + j].set_a(@as(u8, @intFromFloat(average_pixel.a / weight)));
            }
        }
    }
    return .{ .width = n_width, .height = n_height, .data = data_copy };
}
pub fn shear(allocator: Allocator, data: []Pixel, width: u32, height: u32, c_x: f64, c_y: f64) Error!struct { width: u32, height: u32, data: []Pixel } {
    var corners: [4]AffinePosMat.Vec = undefined;
    corners[0] = .{ 0, 0, 1 };
    corners[1] = .{
        0,
        @as(f64, @floatFromInt(height)) - 1,
        1,
    };
    corners[2] = .{
        @as(f64, @floatFromInt(width)) - 1,
        0,
        1,
    };
    corners[3] = .{
        @as(f64, @floatFromInt(width)) - 1,
        @as(f64, @floatFromInt(height)) - 1,
        1,
    };
    const shear_forward = try AffinePosMat.shear(c_x, c_y);
    for (0..4) |i| {
        corners[i] = shear_forward.mul_v(corners[i]);
    }
    var min_x: f64 = corners[0][0];
    var max_x: f64 = corners[0][0];
    var min_y: f64 = corners[0][1];
    var max_y: f64 = corners[0][1];
    for (1..4) |i| {
        min_x = @min(min_x, corners[i][0]);
        max_x = @max(max_x, corners[i][0]);
        min_y = @min(min_y, corners[i][1]);
        max_y = @max(max_y, corners[i][1]);
    }
    const n_width = @as(u32, @intFromFloat(@round(max_x - min_x)));
    const n_height = @as(u32, @intFromFloat(@round(max_y - min_y)));
    var data_copy = try allocator.alloc(Pixel, n_width * n_height);
    for (0..data_copy.len) |i| {
        data_copy[i] = Pixel{};
    }
    var vectors: []AffinePosMat.Vec = try allocator.alloc(AffinePosMat.Vec, n_width * n_height);
    defer allocator.free(vectors);
    const shear_reverse = try AffinePosMat.shear(-c_x, -c_y);
    for (0..n_height) |i| {
        for (0..n_width) |j| {
            vectors[i * n_width + j] = shear_reverse.mul_v(try AffinePosMat.vectorize(.{ @as(f64, @floatFromInt(j)), @as(f64, @floatFromInt(i)) }));
            if (vectors[i * n_width + j][0] < 0 or vectors[i * n_width + j][1] < 0) continue;
            const floored_x = @floor(vectors[i * n_width + j][0]);
            const floored_y = @floor(vectors[i * n_width + j][1]);
            const ceil_x = @ceil(vectors[i * n_width + j][0]);
            const ceil_y = @ceil(vectors[i * n_width + j][1]);
            var min_x_overlap: usize = undefined;
            var min_y_overlap: usize = undefined;
            var max_x_overlap: usize = undefined;
            var max_y_overlap: usize = undefined;
            if (floored_x >= 0) min_x_overlap = @as(usize, @intFromFloat(floored_x));
            if (floored_y >= 0) min_y_overlap = @as(usize, @intFromFloat(floored_y));
            if (ceil_x >= 0) max_x_overlap = @as(usize, @intFromFloat(ceil_x));
            if (ceil_y >= 0) max_y_overlap = @as(usize, @intFromFloat(ceil_y));
            const x_per = vectors[i * n_width + j][0] - @floor(vectors[i * n_width + j][0]);
            const y_per = vectors[i * n_width + j][1] - @floor(vectors[i * n_width + j][1]);
            var average_pixel: struct { r: f64, g: f64, b: f64, a: f64 } = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
            var weight: f64 = 0;
            var indx: usize = undefined;
            if (floored_x >= 0 and floored_y >= 0) {
                indx = min_y_overlap * width + min_x_overlap;
                if (indx < data.len and indx >= 0 and min_y_overlap < height and min_x_overlap < width) {
                    const scale = ((1 - x_per) * (1 - y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (ceil_x >= 0 and floored_y >= 0) {
                indx = min_y_overlap * width + max_x_overlap;
                if (indx < data.len and indx >= 0 and min_y_overlap < height and max_x_overlap < width) {
                    const scale = ((x_per) * (1 - y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (floored_x >= 0 and ceil_y >= 0) {
                indx = max_y_overlap * width + min_x_overlap;
                if (indx < data.len and indx >= 0 and max_y_overlap < height and min_x_overlap < width) {
                    const scale = ((1 - x_per) * (y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (ceil_y >= 0 and ceil_x >= 0) {
                indx = max_y_overlap * width + max_x_overlap;
                if (indx < data.len and indx >= 0 and max_y_overlap < height and max_x_overlap < width) {
                    const scale = ((x_per) * (y_per));
                    average_pixel.r += scale * @as(f64, @floatFromInt(data[indx].get_r()));
                    average_pixel.g += scale * @as(f64, @floatFromInt(data[indx].get_g()));
                    average_pixel.b += scale * @as(f64, @floatFromInt(data[indx].get_b()));
                    average_pixel.a += scale * @as(f64, @floatFromInt(data[indx].get_a()));
                    weight += scale;
                }
            }
            if (weight != 0) {
                data_copy[i * n_width + j].set_r(@as(u8, @intFromFloat(average_pixel.r / weight)));
                data_copy[i * n_width + j].set_g(@as(u8, @intFromFloat(average_pixel.g / weight)));
                data_copy[i * n_width + j].set_b(@as(u8, @intFromFloat(average_pixel.b / weight)));
                data_copy[i * n_width + j].set_a(@as(u8, @intFromFloat(average_pixel.a / weight)));
            }
        }
    }
    return .{ .width = n_width, .height = n_height, .data = data_copy };
}
pub fn write_BMP(allocator: Allocator, data: []Pixel, width: u32, height: u32, file_name: []const u8) Error!void {
    const image_file = try std.fs.cwd().createFile(file_name, .{});
    defer image_file.close();
    try image_file.writer().writeByte('B');
    try image_file.writer().writeByte('M');
    const padding_size: u32 = width % 4;
    const size: u32 = 14 + 12 + height * width * 3 + padding_size * height;

    var buffer: []u8 = try allocator.alloc(u8, height * width * 3 + padding_size * height);
    var buffer_pos = buffer[0..buffer.len];
    defer allocator.free(buffer);
    try common.write_little_endian(&image_file, 4, size);
    try common.write_little_endian(&image_file, 4, 0);
    try common.write_little_endian(&image_file, 4, 0x1A);
    try common.write_little_endian(&image_file, 4, 12);
    try common.write_little_endian(&image_file, 2, width);
    try common.write_little_endian(&image_file, 2, height);
    try common.write_little_endian(&image_file, 2, 1);
    try common.write_little_endian(&image_file, 2, 24);
    var i: usize = height - 1;
    var j: usize = 0;
    while (i >= 0) {
        while (j < width) {
            const pixel: *Pixel = &data[i * width + j];
            var end_color: @Vector(4, f64) = .{ @as(f64, @floatFromInt(pixel.v[0])), @as(f64, @floatFromInt(pixel.v[1])), @as(f64, @floatFromInt(pixel.v[2])), @as(f64, @floatFromInt(pixel.v[3])) };
            if (pixel.get_a() != 255) {
                const bkgd = 0;
                end_color *= @as(@Vector(4, f64), @splat((@as(f64, @floatFromInt(pixel.get_a())) / 255.0)));
                end_color += @as(@Vector(4, f64), @splat((1 - (@as(f64, @floatFromInt(pixel.get_a())) / 255.0)) * bkgd));
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
