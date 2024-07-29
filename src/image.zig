//wrapper struct to provide generic image struct
const std = @import("std");
const jpeg_image = @import("jpeg_image.zig");
const png_image = @import("png_image.zig");

pub fn Image(comptime T: type) type {
    return T;
}

pub const JPEGImage: type = jpeg_image.JPEGImage;
pub const PNGImage: type = png_image.PNGImage;

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image(JPEGImage){};
    try image.load_JPEG("tests/jpeg/cat.jpg", &allocator);
    try image.convert_grayscale();
    image.get(5, 5).r = 255;
    try image.write_BMP("cat.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "PNG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image(PNGImage){};
    try image.load_PNG("tests/png/shield.png", &allocator);
    try image.convert_grayscale();
    image.get(5, 5).r = 255;
    try image.write_BMP("shield.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
