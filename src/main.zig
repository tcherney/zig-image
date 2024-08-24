const std = @import("std");
const image = @import("image.zig");

const ASCII_CHARS = [_]u8{ ' ', '.', ':', 'c', 'o', '?', 'P', 'O', '#', '@' };

const Error = error{
    INVALID_ARG,
    SAMPLE_ERROR,
};

pub fn sample_pixel(im: anytype, i: usize, j: usize, num_samples: u32) Error!f32 {
    if (num_samples % 2 != 0 and num_samples != 1) {
        return Error.SAMPLE_ERROR;
    }
    //TODO improve sample method
    var sample: f32 = (@as(f32, @floatFromInt(im.get(j, i).r)) / 255.0);
    if (num_samples > 1) {
        for (1..(num_samples / 2) + 1) |k| {
            sample += if (j + k >= im.width) 0 else (@as(f32, @floatFromInt(im.get(j + k, i).r)) / 255.0);
            sample += if (i + k >= im.height) 0 else (@as(f32, @floatFromInt(im.get(j, i + k).r)) / 255.0);
        }
        sample /= @as(f32, @floatFromInt(num_samples)) + 1;
    }
    return sample;
}

pub fn img2ascii(comptime T: type, im: *image.Image(T), ascii_height: u32, file_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (T == image.JPEGImage or T == image.PNGImage or T == image.BMPImage) {
        try im.load(file_name, allocator);
    } else {
        return Error.INVALID_ARG;
    }
    try im.convert_grayscale();
    defer im.deinit();
    var sample: u32 = 1;
    if ((im.height) > ascii_height) {
        sample = 2;
    }
    while ((im.height / sample) > ascii_height) {
        sample += 2;
    }
    std.debug.print("sample rate {d}\n", .{sample});
    const SCALE = 1.0 / @as(f32, @floatFromInt(sample));
    var ascii_pixels: []u8 = try allocator.alloc(u8, im.height + @as(usize, @intFromFloat(@ceil(@as(f32, @floatFromInt(im.width)) * @as(f32, @floatFromInt(im.height)) * SCALE))));
    for (ascii_pixels) |*pix| {
        pix.* = ' ';
    }
    var ascii_index: usize = 0;
    var i: usize = 0;
    var j: usize = 0;
    while (i < im.height) : (i += sample) {
        while (j < im.width) : (j += sample) {
            const pixel_value = try sample_pixel(im, i, j, sample);
            var ascii_char_index: usize = @as(usize, @intFromFloat(pixel_value * @as(f32, @floatFromInt(ASCII_CHARS.len))));
            ascii_char_index = if (ascii_char_index >= ASCII_CHARS.len) ASCII_CHARS.len - 1 else ascii_char_index;
            ascii_pixels[ascii_index] = ASCII_CHARS[ascii_char_index];
            ascii_index += 1;
        }
        j = 0;
        ascii_pixels[ascii_index] = '\n';
        ascii_index += 1;
    }

    return ascii_pixels;
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const argsv = try std.process.argsAlloc(allocator);
    if (argsv.len > 1) {
        if (argsv.len >= 2) {
            if (argsv[1].len < 3) {
                try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                try bw.flush();
                return;
            } else {
                const extension = argsv[1][argsv[1].len - 3 ..];
                if (std.mem.eql(u8, extension, "jpg")) {
                    var im = image.Image(image.JPEGImage){};
                    defer im.deinit();
                    const output_name = try std.fmt.allocPrint(allocator, "{s}.bmp", .{argsv[1][0 .. argsv[1].len - 4]});
                    defer allocator.free(output_name);
                    try im.load(argsv[1], allocator);
                    try im.write_BMP(output_name);
                } else if (std.mem.eql(u8, extension, "bmp")) {
                    var im = image.Image(image.BMPImage){};
                    defer im.deinit();
                    const output_name = try std.fmt.allocPrint(allocator, "{s}.bmp", .{argsv[1][0 .. argsv[1].len - 4]});
                    defer allocator.free(output_name);
                    try im.load(argsv[1], allocator);
                    try im.write_BMP(output_name);
                } else if (std.mem.eql(u8, extension, "png")) {
                    var im = image.Image(image.PNGImage){};
                    defer im.deinit();
                    const output_name = try std.fmt.allocPrint(allocator, "{s}.bmp", .{argsv[1][0 .. argsv[1].len - 4]});
                    defer allocator.free(output_name);
                    try im.load(argsv[1], allocator);
                    try im.write_BMP(output_name);
                } else {
                    try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                    try bw.flush();
                }
            }
        } else {
            try stdout.print("Usage: {s} image_file\n", .{argsv[0]});
            try bw.flush();
        }
    } else {
        try stdout.print("Usage: {s} image_file\n", .{argsv[0]});
        try bw.flush();
    }

    std.process.argsFree(allocator, argsv);

    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
