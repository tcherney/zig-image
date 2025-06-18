//wrapper struct to provide generic image struct
const std = @import("std");
const common = @import("common");
const image_core = @import("image_core.zig");
const jpeg_image = @import("jpeg_image.zig");
const png_image = @import("png_image.zig");
const bmp_image = @import("bmp_image.zig");

//TODO replace generic with union
//TODO can completely overhaul the use of image_core, would no longer have to create another object in order to use core functions

pub fn Image(comptime T: type) type {
    return T;
}

pub const ByteStream = common.ByteStream;
pub const BitReader = common.BitReader;
pub const ImageCore = image_core.ImageCore;
pub const Pixel = common.Pixel;
pub const Mat = common.Mat;
pub const ConvolMat = image_core.ConvolMat;
pub const JPEGImage: type = jpeg_image.JPEGImage;
pub const PNGImage: type = png_image.PNGImage;
pub const BMPImage: type = bmp_image.BMPImage;
pub const Error = JPEGImage.Error || PNGImage.Error || BMPImage.Error;

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = Image(JPEGImage){};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.image_core().write_BMP("test_output/cat.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}

test "PNG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = Image(PNGImage){};
    try image.load("tests/png/shield.png", allocator);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.image_core().write_BMP("test_output/shield.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}

test "BMP" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = Image(BMPImage){};
    try image.load("tests/bmp/parrot.bmp", allocator);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.image_core().write_BMP("test_output/parrot2.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}
