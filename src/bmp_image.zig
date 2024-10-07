//https://en.wikipedia.org/wiki/BMP_file_format
const std = @import("std");
const utils = @import("utils.zig");

pub const BMPImage = struct {
    file_data: utils.BitReader = undefined,
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    data: std.ArrayList(utils.Pixel) = undefined,
    bmp_file_header: BMPFileHeader = undefined,
    dib_file_header: BMPDIBHeader = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    pub const Error = error{
        NotLoaded,
        InvalidBMPHeader,
        InvalidDIBHeader,
        UnsupportedCompressionMethod,
    } || utils.BitReader.Error || std.mem.Allocator.Error || utils.ImageCore.Error;
    const BMPFileHeader = struct {
        bmp_type: [2]u8 = [_]u8{0} ** 2,
        file_size: u32 = undefined,
        reserved1: u16 = undefined,
        reserved2: u16 = undefined,
        offset: u32 = undefined,
    };

    const BMPCompressionMethod = enum(u32) {
        BI_RGB = 0,
        BI_RLE8 = 1,
        BI_RLE4 = 2,
        BI_BITFIELDS = 3,
        BI_JPEG = 4,
        BI_PNG = 5,
        BI_ALPHABITFIELDS = 6,
        BI_CMYK = 11,
        BI_CMYKRLE8 = 12,
        BI_CMYKRLE4 = 13,
    };

    const BMPDIBHeader = struct {
        size: u32 = undefined,
        image_size: u32 = undefined,
        bpp: u32 = undefined,
        header_type: BMPDIBType = undefined,
        compression_method: BMPCompressionMethod = undefined,
        color_planes: u16 = undefined,
        horizontal_res: u32 = undefined,
        vertical_res: u32 = undefined,
        num_col_palette: u32 = undefined,
        important_colors: u32 = undefined,
        red_mask: u32 = undefined,
        green_mask: u32 = undefined,
        blue_mask: u32 = undefined,
        alpha_mask: u32 = undefined,
        color_space_type: u32 = undefined,
        ciexyz: CIEXYZ = undefined,
        gamma_red: u32 = undefined,
        gamma_green: u32 = undefined,
        gamma_blue: u32 = undefined,
        intent: u32 = undefined,
        profile_data: u32 = undefined,
        profile_size: u32 = undefined,
        reserved: u32 = undefined,

        const Pixel32 = struct {
            r: u32,
            g: u32,
            b: u32,
        };

        const CIEXYZ = struct {
            ciexyz_x: Pixel32 = undefined,
            ciexyz_y: Pixel32 = undefined,
            ciexyz_z: Pixel32 = undefined,
        };
    };

    const BMPDIBType = enum(u32) {
        OS = 12,
        V1 = 40,
        V2 = 52,
        V3 = 56,
        V4 = 108,
        V5 = 124,
    };

    pub fn convert_grayscale(self: *BMPImage) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().grayscale();
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].r = data_copy[i].r;
                self.data.items[i].g = data_copy[i].g;
                self.data.items[i].b = data_copy[i].b;
                self.data.items[i].a = data_copy[i].a;
            }
        } else {
            return Error.NotLoaded;
        }
    }
    pub fn load(self: *BMPImage, file_name: []const u8, allocator: std.mem.Allocator) Error!void {
        self.allocator = allocator;
        self.file_data = try utils.BitReader.init(.{ .file_name = file_name, .allocator = self.allocator, .little_endian = true });
        std.debug.print("reading bmp\n", .{});
        try self.read_BMP_header();
        try self.read_DIB_header();
        self.data = try std.ArrayList(utils.Pixel).initCapacity(self.allocator, self.height * self.width);
        self.data.expandToCapacity();
        try self.read_color_data();
        self.loaded = true;
    }

    pub fn get(self: *const BMPImage, x: usize, y: usize) *utils.Pixel {
        return &self.data.items[y * self.width + x];
    }

    fn read_color_data(self: *BMPImage) Error!void {
        const padding_size = self.width % 4;
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) : (i -= 1) {
            while (j < self.width) : (j += 1) {
                switch (self.dib_file_header.compression_method) {
                    .BI_RGB => {
                        if (self.dib_file_header.bpp == 24) {
                            self.data.items[i * self.width + j] = utils.Pixel{
                                .b = try self.file_data.read(u8),
                                .g = try self.file_data.read(u8),
                                .r = try self.file_data.read(u8),
                            };
                        }
                    },
                    .BI_BITFIELDS => {
                        if (self.dib_file_header.bpp == 24) {
                            self.data.items[i * self.width + j] = utils.Pixel{
                                .b = try self.file_data.read(u8),
                                .g = try self.file_data.read(u8),
                                .r = try self.file_data.read(u8),
                            };
                            _ = try self.file_data.read(u8);
                        } else if (self.dib_file_header.bpp == 32) {
                            self.data.items[i * self.width + j] = utils.Pixel{
                                .b = try self.file_data.read(u8),
                                .g = try self.file_data.read(u8),
                                .r = try self.file_data.read(u8),
                            };
                            _ = try self.file_data.read(u8);
                        }
                    },
                    //TODO support other compression types
                    else => return Error.UnsupportedCompressionMethod,
                }
            }
            for (0..padding_size) |_| {
                _ = try self.file_data.read(u8);
            }
            j = 0;
            if (i == 0) break;
        }
    }

    fn read_DIB_V2_header(self: *BMPImage) Error!void {
        try self.read_DIB_V1_header();
        self.dib_file_header.red_mask = try self.file_data.read(u32);
        self.dib_file_header.green_mask = try self.file_data.read(u32);
        self.dib_file_header.blue_mask = try self.file_data.read(u32);
        std.debug.print("red mask {d}, green mask {d}, blue mask {d}\n", .{ self.dib_file_header.red_mask, self.dib_file_header.green_mask, self.dib_file_header.blue_mask });
    }

    fn read_DIB_V3_header(self: *BMPImage) Error!void {
        try self.read_DIB_V2_header();
        self.dib_file_header.alpha_mask = try self.file_data.read(u32);
        std.debug.print("alpha mask {d}\n", .{self.dib_file_header.alpha_mask});
    }

    fn read_DIB_V4_header(self: *BMPImage) Error!void {
        try self.read_DIB_V3_header();
        self.dib_file_header.color_space_type = try self.file_data.read(u32);
        self.dib_file_header.ciexyz = BMPDIBHeader.CIEXYZ{};
        self.dib_file_header.ciexyz.ciexyz_x = BMPDIBHeader.Pixel32{
            .r = try self.file_data.read(u32),
            .g = try self.file_data.read(u32),
            .b = try self.file_data.read(u32),
        };
        self.dib_file_header.ciexyz.ciexyz_y = BMPDIBHeader.Pixel32{
            .r = try self.file_data.read(u32),
            .g = try self.file_data.read(u32),
            .b = try self.file_data.read(u32),
        };
        self.dib_file_header.ciexyz.ciexyz_z = BMPDIBHeader.Pixel32{
            .r = try self.file_data.read(u32),
            .g = try self.file_data.read(u32),
            .b = try self.file_data.read(u32),
        };
        self.dib_file_header.gamma_red = try self.file_data.read(u32);
        self.dib_file_header.gamma_green = try self.file_data.read(u32);
        self.dib_file_header.gamma_blue = try self.file_data.read(u32);
    }

    fn read_DIB_V5_header(self: *BMPImage) Error!void {
        try self.read_DIB_V4_header();
        self.dib_file_header.intent = try self.file_data.read(u32);
        self.dib_file_header.profile_data = try self.file_data.read(u32);
        self.dib_file_header.profile_size = try self.file_data.read(u32);
        self.dib_file_header.reserved = try self.file_data.read(u32);
    }

    fn read_DIB_V1_header(self: *BMPImage) Error!void {
        self.width = try self.file_data.read(u32);
        self.height = try self.file_data.read(u32);
        self.dib_file_header.color_planes = try self.file_data.read(u16);
        if (self.dib_file_header.color_planes != 1) {
            return Error.InvalidDIBHeader;
        }
        self.dib_file_header.bpp = try self.file_data.read(u16);
        self.dib_file_header.compression_method = @enumFromInt(try self.file_data.read(u32));
        self.dib_file_header.image_size = try self.file_data.read(u32);
        self.dib_file_header.horizontal_res = try self.file_data.read(u32);
        self.dib_file_header.vertical_res = try self.file_data.read(u32);
        self.dib_file_header.num_col_palette = try self.file_data.read(u32);
        self.dib_file_header.important_colors = try self.file_data.read(u32);
        std.debug.print("width {d}, height {d}, color_planes {d}, bpp {d}, compression_method {}, image_size {d}, horizontal_res {d}, vertical_res {d}, num_col_palette {d}, important_colors {d}, \n", .{ self.width, self.height, self.dib_file_header.color_planes, self.dib_file_header.bpp, self.dib_file_header.compression_method, self.dib_file_header.image_size, self.dib_file_header.horizontal_res, self.dib_file_header.vertical_res, self.dib_file_header.num_col_palette, self.dib_file_header.important_colors });
    }

    fn read_DIB_header(self: *BMPImage) Error!void {
        self.dib_file_header = BMPDIBHeader{};
        self.dib_file_header.size = try self.file_data.read(u32);
        std.debug.print("header_size {d}\n", .{self.dib_file_header.size});
        self.dib_file_header.header_type = @enumFromInt(self.dib_file_header.size);
        switch (self.dib_file_header.header_type) {
            .OS => {
                self.width = try self.file_data.read(u16);
                self.height = try self.file_data.read(u16);
                self.dib_file_header.color_planes = try self.file_data.read(u16);
                if (self.dib_file_header.color_planes != 1) {
                    return Error.InvalidDIBHeader;
                }
                self.dib_file_header.bpp = try self.file_data.read(u16);
                std.debug.print("width {d}, height {d}, color_planes {d}, bpp {d}\n", .{ self.width, self.height, self.dib_file_header.color_planes, self.dib_file_header.bpp });
            },
            .V1 => {
                try self.read_DIB_V1_header();
            },
            .V2 => {
                try self.read_DIB_V2_header();
            },
            .V3 => {
                try self.read_DIB_V3_header();
            },
            .V4 => {
                try self.read_DIB_V4_header();
            },
            .V5 => {
                try self.read_DIB_V5_header();
            },
        }
    }

    fn read_BMP_header(self: *BMPImage) Error!void {
        // type
        self.bmp_file_header.bmp_type[0] = try self.file_data.read(u8);
        self.bmp_file_header.bmp_type[1] = try self.file_data.read(u8);
        //TODO handle types
        if (!std.mem.eql(u8, &self.bmp_file_header.bmp_type, "BM")) {
            return Error.InvalidBMPHeader;
        }
        std.debug.print("file type {s}\n", .{self.bmp_file_header.bmp_type});
        // size
        self.bmp_file_header.file_size = try self.file_data.read(u32);
        std.debug.print("file size {d}\n", .{self.bmp_file_header.file_size});
        // reserved
        self.bmp_file_header.reserved1 = try self.file_data.read(u16);
        self.bmp_file_header.reserved2 = try self.file_data.read(u16);
        // offset
        self.bmp_file_header.offset = try self.file_data.read(u32);
        std.debug.print("offset {d}\n", .{self.bmp_file_header.offset});
    }

    pub fn image_core(self: *BMPImage) utils.ImageCore {
        return utils.ImageCore.init(self.allocator, self.width, self.height, self.data.items);
    }

    pub fn write_BMP(self: *BMPImage, file_name: []const u8) Error!void {
        if (!self.loaded) {
            return Error.NotLoaded;
        }
        try self.image_core().write_BMP(file_name);
    }

    pub fn deinit(self: *BMPImage) void {
        self.file_data.deinit();
        std.ArrayList(utils.Pixel).deinit(self.data);
    }
};

test "CAT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/cat.bmp", allocator);
    try image.write_BMP("os.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "V3" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/basic0.bmp", allocator);
    try image.write_BMP("v3.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "V5" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/basic1.bmp", allocator);
    try image.write_BMP("v5.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
