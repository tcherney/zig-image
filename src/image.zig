//wrapper struct to provide generic image struct
const std = @import("std");
const common = @import("common");
pub const image_core = @import("image_core.zig");
pub const svg_image = @import("svg_image.zig");
pub const jpeg_image = @import("jpeg_image.zig");
pub const png_image = @import("png_image.zig");
pub const bmp_image = @import("bmp_image.zig");

pub const Allocator = std.mem.Allocator;
pub const ByteStream = common.ByteStream;
pub const BitReader = common.BitReader;
pub const Pixel = common.Pixel;
pub const Mat = common.Mat;

pub const JPEGBuilder: type = jpeg_image.JPEGBuilder;
pub const PNGBuilder: type = png_image.PNGBuilder;
pub const BMPBuilder: type = bmp_image.BMPBuilder;
pub const SVGBuilder: type = svg_image.SVGBuilder;

pub const Image = struct {
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    data: std.ArrayList(common.Pixel) = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    grayscale: bool = false,
    pub const ConvolMat = image_core.ConvolMat;
    pub const Error = image_core.Error || ImageBuilder.Error;
    pub const CoreError = image_core.Error || error{NotLoaded};
    pub const ImageType = enum {
        JPEG,
        PNG,
        BMP,
        SVG,
    };
    pub const ScaleOption = enum { BICUBIC, BILINEAR, NN };
    pub const ImageBuilder = union(enum) {
        jpeg: JPEGBuilder,
        png: PNGBuilder,
        bmp: BMPBuilder,
        svg: SVGBuilder,
        pub const Error = JPEGBuilder.Error || PNGBuilder.Error || BMPBuilder.Error || SVGBuilder.Error;
        pub fn load(self: *ImageBuilder, path: []const u8, allocator: Allocator) ImageBuilder.Error!Image {
            switch (self.*) {
                inline else => |*i| return try i.load(path, allocator),
            }
        }
        pub fn deinit(self: *ImageBuilder) void {
            switch (self.*) {
                .jpeg => {},
                inline else => |*i| i.deinit(),
            }
        }
    };
    pub fn init_load(allocator: Allocator, path: []const u8, image_type: ImageType) Error!Image {
        var builder: ImageBuilder = undefined;
        var ret: Image = undefined;
        switch (image_type) {
            .JPEG => {
                builder = .{ .jpeg = JPEGBuilder{} };
                defer builder.deinit();
                ret = try builder.load(path, allocator);
            },
            .PNG => {
                builder = .{ .png = PNGBuilder{} };
                defer builder.deinit();
                ret = try builder.load(path, allocator);
            },
            .BMP => {
                builder = .{ .bmp = BMPBuilder{} };
                defer builder.deinit();
                ret = try builder.load(path, allocator);
            },
            .SVG => {
                builder = .{ .svg = SVGBuilder{} };
                defer builder.deinit();
                ret = try builder.load(path, allocator);
            },
        }
        return ret;
    }

    pub fn deinit(self: *Image) void {
        self.data.deinit();
    }

    pub fn convert_grayscale(self: *Image) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.grayscale(self.allocator, self.data.items);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
            self.grayscale = true;
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn fft_rep(self: *Image) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.fft_rep(self.allocator, self.data.items, self.width, self.height);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn reflection(self: *Image, comptime axis: @Type(.enum_literal)) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.reflection(self.allocator, self.data.items, self.width, self.height, axis);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn edge_detection(self: *Image) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.edge_detection(self.allocator, self.data.items, self.width, self.height);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn rotate(self: *Image, degrees: f64) CoreError!void {
        if (self.loaded) {
            const data = try image_core.rotate(self.allocator, self.data.items, self.width, self.height, degrees);
            const data_copy = data.data;
            self.width = data.width;
            self.height = data.height;
            defer self.allocator.free(data_copy);
            self.data.clearRetainingCapacity();
            for (0..data_copy.len) |i| {
                try self.data.append(data_copy[i]);
            }
        } else {
            return CoreError.NotLoaded;
        }
    }

    pub fn histogram_equalization(self: *Image) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.histogram_equalization(self.allocator, self.data.items, self.width, self.height);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn shear(self: *Image, c_x: f64, c_y: f64) Error!void {
        if (self.loaded) {
            const data = try image_core.shear(self.allocator, self.data.items, self.width, self.height, c_x, c_y);
            const data_copy = data.data;
            self.width = data.width;
            self.height = data.height;
            defer self.allocator.free(data_copy);
            self.data.clearRetainingCapacity();
            for (0..data_copy.len) |i| {
                try self.data.append(data_copy[i]);
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn scale(self: *Image, width: u32, height: u32, scale_option: ScaleOption) Error!void {
        if (self.loaded) {
            const data = switch (scale_option) {
                .BICUBIC => try image_core.bicubic(self.allocator, self.data.items, self.width, self.height, width, height),
                .BILINEAR => try image_core.bilinear(self.allocator, self.data.items, self.width, self.height, width, height),
                .NN => try image_core.nearest_neighbor(self.allocator, self.data.items, self.width, self.height, width, height),
            };
            self.width = width;
            self.height = height;
            defer self.allocator.free(data);
            self.data.clearRetainingCapacity();
            for (0..data.len) |i| {
                try self.data.append(data[i]);
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn fft_convol(self: *Image, kernel: ConvolMat) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.fft_convol(self.allocator, self.data.items, self.width, self.height, self.grayscale, kernel);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn convol(self: *Image, kernel: ConvolMat) Error!void {
        if (self.loaded) {
            const data_copy = try image_core.convol(self.allocator, self.data.items, self.width, self.height, kernel);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn write_BMP(self: *Image, file_name: []const u8) Error!void {
        if (!self.loaded) {
            return Error.NotLoaded;
        }
        try image_core.write_BMP(self.allocator, self.data.items, self.width, self.height, file_name);
    }
    pub fn get(self: *const Image, x: usize, y: usize) *common.Pixel {
        return &self.data.items[y * self.width + x];
    }
};

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/jpeg/cat.jpg", .JPEG);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.write_BMP("test_output/cat.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}

test "PNG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/png/shield.png", .PNG);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.write_BMP("test_output/shield.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}

test "BMP" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/parrot.bmp", .BMP);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.write_BMP("test_output/parrot2.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}

test "SVG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/svg/cat.svg", .SVG);
    try image.convert_grayscale();
    image.get(5, 5).set_r(255);
    try image.write_BMP("test_output/cat.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}
