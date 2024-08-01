const std = @import("std");
const image = @import("image.zig");

const ASCII_CHARS = [_]u8{ ' ', '.', '*', '%', '$', '#' };

const Error = error{
    INVALID_ARG,
    SAMPLE_ERROR,
};

pub fn sample_pixel(im: anytype, i: usize, j: usize, num_samples: comptime_int) Error!f32 {
    if (num_samples % 2 != 0) {
        return Error.SAMPLE_ERROR;
    }
    var sample: f32 = (@as(f32, @floatFromInt(im.get(j, i).r)) / 255.0);
    for (1..(num_samples / 2) + 1) |k| {
        sample += if (j + k >= im.width) 0 else (@as(f32, @floatFromInt(im.get(j + k, i).r)) / 255.0);
        sample += if (i + k >= im.height) 0 else (@as(f32, @floatFromInt(im.get(j, i + k).r)) / 255.0);
    }
    sample /= num_samples + 1;
    return sample;
}

pub fn img2ascii(im: anytype, alloc: std.mem.Allocator) (Error || std.mem.Allocator.Error)![]u8 {
    const image_type = @TypeOf(im);
    if (image_type != image.JPEGImage and image_type != image.PNGImage and image_type != image.BMPImage) {
        return Error.INVALID_ARG;
    }
    const SAMPLE = 8;
    const SCALE = 1.0 / @as(f32, @floatCast(SAMPLE));
    var ascii_pixels: []u8 = try alloc.alloc(u8, im.height + @as(usize, @intFromFloat(@ceil(@as(f32, @floatFromInt(im.width)) * @as(f32, @floatFromInt(im.height)) * SCALE))));
    for (ascii_pixels) |*pix| {
        pix.* = ' ';
    }
    const ascii_seperation = 1.0 / @as(f32, @floatFromInt(ASCII_CHARS.len));
    var ascii_index: usize = 0;
    var i: usize = 0;
    var j: usize = 0;
    while (i < im.height) : (i += SAMPLE) {
        while (j < im.width) : (j += SAMPLE) {
            const pixel_value = try sample_pixel(im, i, j, SAMPLE);
            if (pixel_value < ascii_seperation) {
                ascii_pixels[ascii_index] = ASCII_CHARS[0];
            } else if (pixel_value < ascii_seperation * 2) {
                ascii_pixels[ascii_index] = ASCII_CHARS[1];
            } else if (pixel_value < ascii_seperation * 3) {
                ascii_pixels[ascii_index] = ASCII_CHARS[2];
            } else if (pixel_value < ascii_seperation * 4) {
                ascii_pixels[ascii_index] = ASCII_CHARS[3];
            } else if (pixel_value < ascii_seperation * 5) {
                ascii_pixels[ascii_index] = ASCII_CHARS[5];
            } else {
                ascii_pixels[ascii_index] = ASCII_CHARS[5];
            }
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
    var allocator = gpa.allocator();
    var im = image.Image(image.PNGImage){};
    try im.load_PNG("tests/png/shield.png", &allocator);
    try im.convert_grayscale();
    const ascii_image: []u8 = try img2ascii(im, allocator);
    try stdout.print("{s}\n", .{ascii_image});
    try bw.flush(); // don't forget to flush!
    const ascii_file = try std.fs.cwd().createFile("shield.txt", .{});
    try ascii_file.writeAll(ascii_image);
    ascii_file.close();
    allocator.free(ascii_image);
    im.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
