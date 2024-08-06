//https://en.wikipedia.org/wiki/BMP_file_format
const std = @import("std");
const utils = @import("utils.zig");

pub const Error = error{
    NOT_LOADED,
    INVALID_BMP_HEADER,
    INVALID_DIB_HEADER,
    UNSUPPORTED_COMPRESSION_METHOD,
};

pub const BMPImage = struct {
    _file_data: utils.BitReader = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,
    data: std.ArrayList(utils.Pixel(u8)) = undefined,
    _bmp_file_header: BMPFileHeader = undefined,
    _dib_file_header: BMPDIBHeader = undefined,
    width: u32 = undefined,
    height: u32 = undefined,

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

        const CIEXYZ = struct {
            ciexyz_x: utils.Pixel(u32) = undefined,
            ciexyz_y: utils.Pixel(u32) = undefined,
            ciexyz_z: utils.Pixel(u32) = undefined,
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

    pub fn convert_grayscale(self: *BMPImage) !void {
        if (self._loaded) {
            for (0..self.data.items.len) |i| {
                const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].r)) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].g)) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].b)) * 0.1140));
                self.data.items[i].r = gray;
                self.data.items[i].g = gray;
                self.data.items[i].b = gray;
            }
        } else {
            return Error.NOT_LOADED;
        }
    }
    pub fn load(self: *BMPImage, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._file_data = try utils.BitReader.init(.{ .file_name = file_name, .allocator = self._allocator, .little_endian = true });
        std.debug.print("reading bmp\n", .{});
        try self.read_BMP_header();
        try self.read_DIB_header();
        self.data = try std.ArrayList(utils.Pixel(u8)).initCapacity(self._allocator.*, self.height * self.width);
        self.data.expandToCapacity();
        try self.read_color_data();
        self._loaded = true;
    }

    pub fn get(self: *const BMPImage, x: usize, y: usize) *utils.Pixel(u8) {
        return &self.data.items[y * self.width + x];
    }

    fn read_color_data(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        const padding_size = self.width % 4;
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) : (i -= 1) {
            while (j < self.width) : (j += 1) {
                switch (self._dib_file_header.compression_method) {
                    .BI_RGB => {
                        if (self._dib_file_header.bpp == 24) {
                            self.data.items[i * self.width + j] = utils.Pixel(u8){
                                .b = try self._file_data.read_byte(),
                                .g = try self._file_data.read_byte(),
                                .r = try self._file_data.read_byte(),
                            };
                        }
                    },
                    .BI_BITFIELDS => {
                        if (self._dib_file_header.bpp == 24) {
                            self.data.items[i * self.width + j] = utils.Pixel(u8){
                                .b = try self._file_data.read_byte(),
                                .g = try self._file_data.read_byte(),
                                .r = try self._file_data.read_byte(),
                            };
                            _ = try self._file_data.read_byte();
                        } else if (self._dib_file_header.bpp == 32) {
                            self.data.items[i * self.width + j] = utils.Pixel(u8){
                                .b = try self._file_data.read_byte(),
                                .g = try self._file_data.read_byte(),
                                .r = try self._file_data.read_byte(),
                            };
                            _ = try self._file_data.read_byte();
                        }
                    },
                    //TODO support other compression types
                    else => return Error.UNSUPPORTED_COMPRESSION_METHOD,
                }
            }
            for (0..padding_size) |_| {
                _ = try self._file_data.read_byte();
            }
            j = 0;
            if (i == 0) break;
        }
    }

    fn read_DIB_V2_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        try self.read_DIB_V1_header();
        self._dib_file_header.red_mask = try self._file_data.read_int();
        self._dib_file_header.green_mask = try self._file_data.read_int();
        self._dib_file_header.blue_mask = try self._file_data.read_int();
        std.debug.print("red mask {d}, green mask {d}, blue mask {d}\n", .{ self._dib_file_header.red_mask, self._dib_file_header.green_mask, self._dib_file_header.blue_mask });
    }

    fn read_DIB_V3_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        try self.read_DIB_V2_header();
        self._dib_file_header.alpha_mask = try self._file_data.read_int();
        std.debug.print("alpha mask {d}\n", .{self._dib_file_header.alpha_mask});
    }

    fn read_DIB_V4_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        try self.read_DIB_V3_header();
        self._dib_file_header.color_space_type = try self._file_data.read_int();
        self._dib_file_header.ciexyz = BMPDIBHeader.CIEXYZ{};
        self._dib_file_header.ciexyz.ciexyz_x = utils.Pixel(u32){
            .r = try self._file_data.read_int(),
            .g = try self._file_data.read_int(),
            .b = try self._file_data.read_int(),
        };
        self._dib_file_header.ciexyz.ciexyz_y = utils.Pixel(u32){
            .r = try self._file_data.read_int(),
            .g = try self._file_data.read_int(),
            .b = try self._file_data.read_int(),
        };
        self._dib_file_header.ciexyz.ciexyz_z = utils.Pixel(u32){
            .r = try self._file_data.read_int(),
            .g = try self._file_data.read_int(),
            .b = try self._file_data.read_int(),
        };
        self._dib_file_header.gamma_red = try self._file_data.read_int();
        self._dib_file_header.gamma_green = try self._file_data.read_int();
        self._dib_file_header.gamma_blue = try self._file_data.read_int();
    }

    fn read_DIB_V5_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        try self.read_DIB_V4_header();
        self._dib_file_header.intent = try self._file_data.read_int();
        self._dib_file_header.profile_data = try self._file_data.read_int();
        self._dib_file_header.profile_size = try self._file_data.read_int();
        self._dib_file_header.reserved = try self._file_data.read_int();
    }

    fn read_DIB_V1_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        self.width = try self._file_data.read_int();
        self.height = try self._file_data.read_int();
        self._dib_file_header.color_planes = try self._file_data.read_word();
        if (self._dib_file_header.color_planes != 1) {
            return Error.INVALID_DIB_HEADER;
        }
        self._dib_file_header.bpp = try self._file_data.read_word();
        self._dib_file_header.compression_method = @enumFromInt(try self._file_data.read_int());
        self._dib_file_header.image_size = try self._file_data.read_int();
        self._dib_file_header.horizontal_res = try self._file_data.read_int();
        self._dib_file_header.vertical_res = try self._file_data.read_int();
        self._dib_file_header.num_col_palette = try self._file_data.read_int();
        self._dib_file_header.important_colors = try self._file_data.read_int();
        std.debug.print("width {d}, height {d}, color_planes {d}, bpp {d}, compression_method {}, image_size {d}, horizontal_res {d}, vertical_res {d}, num_col_palette {d}, important_colors {d}, \n", .{ self.width, self.height, self._dib_file_header.color_planes, self._dib_file_header.bpp, self._dib_file_header.compression_method, self._dib_file_header.image_size, self._dib_file_header.horizontal_res, self._dib_file_header.vertical_res, self._dib_file_header.num_col_palette, self._dib_file_header.important_colors });
    }

    fn read_DIB_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        self._dib_file_header = BMPDIBHeader{};
        self._dib_file_header.size = try self._file_data.read_int();
        std.debug.print("header_size {d}\n", .{self._dib_file_header.size});
        self._dib_file_header.header_type = @enumFromInt(self._dib_file_header.size);
        switch (self._dib_file_header.header_type) {
            .OS => {
                self.width = try self._file_data.read_word();
                self.height = try self._file_data.read_word();
                self._dib_file_header.color_planes = try self._file_data.read_word();
                if (self._dib_file_header.color_planes != 1) {
                    return Error.INVALID_DIB_HEADER;
                }
                self._dib_file_header.bpp = try self._file_data.read_word();
                std.debug.print("width {d}, height {d}, color_planes {d}, bpp {d}\n", .{ self.width, self.height, self._dib_file_header.color_planes, self._dib_file_header.bpp });
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

    fn read_BMP_header(self: *BMPImage) (utils.ByteStream.Error || utils.BitReader.Error || Error)!void {
        // type
        self._bmp_file_header.bmp_type[0] = try self._file_data.read_byte();
        self._bmp_file_header.bmp_type[1] = try self._file_data.read_byte();
        //TODO handle types
        if (!std.mem.eql(u8, &self._bmp_file_header.bmp_type, "BM")) {
            return Error.INVALID_BMP_HEADER;
        }
        std.debug.print("file type {s}\n", .{self._bmp_file_header.bmp_type});
        // size
        self._bmp_file_header.file_size = try self._file_data.read_int();
        std.debug.print("file size {d}\n", .{self._bmp_file_header.file_size});
        // reserved
        self._bmp_file_header.reserved1 = try self._file_data.read_word();
        self._bmp_file_header.reserved2 = try self._file_data.read_word();
        // offset
        self._bmp_file_header.offset = try self._file_data.read_int();
        std.debug.print("offset {d}\n", .{self._bmp_file_header.offset});
    }

    pub fn write_BMP(self: *BMPImage, file_name: []const u8) !void {
        if (!self._loaded) {
            return Error.NOT_LOADED;
        }
        const image_file = try std.fs.cwd().createFile(file_name, .{});
        defer image_file.close();
        try image_file.writer().writeByte('B');
        try image_file.writer().writeByte('M');
        const padding_size: u32 = self.width % 4;
        const size: u32 = 14 + 12 + self.height * self.width * 3 + padding_size * self.height;

        var buffer: []u8 = try self._allocator.alloc(u8, self.height * self.width * 3 + padding_size * self.height);
        var buffer_pos = buffer[0..buffer.len];
        defer self._allocator.free(buffer);
        try utils.write_little_endian(&image_file, 4, size);
        try utils.write_little_endian(&image_file, 4, 0);
        try utils.write_little_endian(&image_file, 4, 0x1A);
        try utils.write_little_endian(&image_file, 4, 12);
        try utils.write_little_endian(&image_file, 2, self.width);
        try utils.write_little_endian(&image_file, 2, self.height);
        try utils.write_little_endian(&image_file, 2, 1);
        try utils.write_little_endian(&image_file, 2, 24);
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) {
            while (j < self.width) {
                const pixel: *utils.Pixel(u8) = &self.data.items[i * self.width + j];
                buffer_pos[0] = pixel.b;
                buffer_pos.ptr += 1;
                buffer_pos[0] = pixel.g;
                buffer_pos.ptr += 1;
                buffer_pos[0] = pixel.r;
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
    pub fn deinit(self: *BMPImage) void {
        self._file_data.deinit();
        std.ArrayList(utils.Pixel(u8)).deinit(self.data);
    }
};

test "CAT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/cat.bmp", &allocator);
    try image.write_BMP("os.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "V3" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/basic0.bmp", &allocator);
    try image.write_BMP("v3.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "V5" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load("tests/bmp/basic1.bmp", &allocator);
    try image.write_BMP("v5.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
