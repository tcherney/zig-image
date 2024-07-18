//wrapper struct to provide generic image struct
const std = @import("std");
const jpeg_image = @import("jpeg_image.zig");

pub fn Image(comptime T: type) type {
    return T;
}

pub const JPEGImage: type = jpeg_image.JPEGImage;

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image(JPEGImage){};
    try image.load_JPEG("cat.jpg", &allocator);
    try image.convert_grayscale();
    try image.write_BMP("cat.bmp");
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
