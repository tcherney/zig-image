//wrapper struct to provide generic image struct
const std = @import("std");
const jpeg_image = @import("jpeg_image.zig");
const png_image = @import("png_image.zig");
const bmp_image = @import("bmp_image.zig");

pub fn Image(comptime T: type) type {
    return T;
}

pub const JPEGImage: type = jpeg_image.JPEGImage;
pub const PNGImage: type = png_image.PNGImage;
pub const BMPImage: type = bmp_image.BMPImage;
pub const Error = jpeg_image.Error || png_image.Error || bmp_image.Error;

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image(JPEGImage){};
    try image.load("tests/jpeg/cat.jpg", &allocator);
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
    try image.load("tests/png/shield.png", &allocator);
    try image.convert_grayscale();
    image.get(5, 5).r = 255;
    try image.write_BMP("shield.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BMP" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image(BMPImage){};
    try image.load("tests/bmp/parrot.bmp", &allocator);
    try image.convert_grayscale();
    image.get(5, 5).r = 255;
    try image.write_BMP("parrot2.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
