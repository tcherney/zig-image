//https://en.wikipedia.org/wiki/BMP_file_format
const std = @import("std");
const common = @import("common");
const image_core = @import("image_core.zig");
const _image = @import("image.zig");

pub const Image = _image.Image;
const BMP_LOG = std.log.scoped(.bmp_image);

pub const BMPBuilder = struct {
    file_data: common.BitReader = undefined,
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    data: std.ArrayList(common.Pixel) = undefined,
    bmp_file_header: BMPFileHeader = undefined,
    dib_file_header: BMPDIBHeader = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    grayscale: bool = false,
    pub const Error = error{
        NotLoaded,
        InvalidBMPHeader,
        InvalidDIBHeader,
        UnsupportedCompressionMethod,
    } || common.BitReader.Error || std.mem.Allocator.Error || image_core.Error;
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

    pub fn load(self: *BMPBuilder, file_name: []const u8, allocator: std.mem.Allocator) Error!Image {
        self.allocator = allocator;
        self.file_data = try common.BitReader.init(.{ .file_name = file_name, .allocator = self.allocator, .little_endian = true });
        BMP_LOG.info("reading bmp\n", .{});
        try self.read_BMP_header();
        try self.read_DIB_header();
        self.data = try std.ArrayList(common.Pixel).initCapacity(self.allocator, self.height * self.width);
        self.data.expandToCapacity();
        try self.read_color_data();
        self.loaded = true;
        return Image{
            .allocator = self.allocator,
            .data = self.data,
            .grayscale = self.grayscale,
            .height = self.height,
            .width = self.width,
            .loaded = true,
        };
    }

    fn read_color_data(self: *BMPBuilder) Error!void {
        const padding_size = self.width % 4;
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) : (i -= 1) {
            while (j < self.width) : (j += 1) {
                switch (self.dib_file_header.compression_method) {
                    .BI_RGB => {
                        if (self.dib_file_header.bpp == 24) {
                            const b = try self.file_data.read(u8);
                            const g = try self.file_data.read(u8);
                            const r = try self.file_data.read(u8);
                            self.data.items[i * self.width + j] = common.Pixel.init(
                                r,
                                g,
                                b,
                                null,
                            );
                        }
                    },
                    .BI_BITFIELDS => {
                        if (self.dib_file_header.bpp == 24) {
                            const b = try self.file_data.read(u8);
                            const g = try self.file_data.read(u8);
                            const r = try self.file_data.read(u8);
                            self.data.items[i * self.width + j] = common.Pixel.init(
                                r,
                                g,
                                b,
                                null,
                            );
                            _ = try self.file_data.read(u8);
                        } else if (self.dib_file_header.bpp == 32) {
                            const b = try self.file_data.read(u8);
                            const g = try self.file_data.read(u8);
                            const r = try self.file_data.read(u8);
                            self.data.items[i * self.width + j] = common.Pixel.init(
                                r,
                                g,
                                b,
                                null,
                            );
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

    fn read_DIB_V2_header(self: *BMPBuilder) Error!void {
        try self.read_DIB_V1_header();
        self.dib_file_header.red_mask = try self.file_data.read(u32);
        self.dib_file_header.green_mask = try self.file_data.read(u32);
        self.dib_file_header.blue_mask = try self.file_data.read(u32);
        BMP_LOG.info("red mask {d}, green mask {d}, blue mask {d}\n", .{ self.dib_file_header.red_mask, self.dib_file_header.green_mask, self.dib_file_header.blue_mask });
    }

    fn read_DIB_V3_header(self: *BMPBuilder) Error!void {
        try self.read_DIB_V2_header();
        self.dib_file_header.alpha_mask = try self.file_data.read(u32);
        BMP_LOG.info("alpha mask {d}\n", .{self.dib_file_header.alpha_mask});
    }

    fn read_DIB_V4_header(self: *BMPBuilder) Error!void {
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

    fn read_DIB_V5_header(self: *BMPBuilder) Error!void {
        try self.read_DIB_V4_header();
        self.dib_file_header.intent = try self.file_data.read(u32);
        self.dib_file_header.profile_data = try self.file_data.read(u32);
        self.dib_file_header.profile_size = try self.file_data.read(u32);
        self.dib_file_header.reserved = try self.file_data.read(u32);
    }

    fn read_DIB_V1_header(self: *BMPBuilder) Error!void {
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
        BMP_LOG.info("width {d}, height {d}, color_planes {d}, bpp {d}, compression_method {}, image_size {d}, horizontal_res {d}, vertical_res {d}, num_col_palette {d}, important_colors {d}, \n", .{ self.width, self.height, self.dib_file_header.color_planes, self.dib_file_header.bpp, self.dib_file_header.compression_method, self.dib_file_header.image_size, self.dib_file_header.horizontal_res, self.dib_file_header.vertical_res, self.dib_file_header.num_col_palette, self.dib_file_header.important_colors });
    }

    fn read_DIB_header(self: *BMPBuilder) Error!void {
        self.dib_file_header = BMPDIBHeader{};
        self.dib_file_header.size = try self.file_data.read(u32);
        BMP_LOG.info("header_size {d}\n", .{self.dib_file_header.size});
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
                BMP_LOG.info("width {d}, height {d}, color_planes {d}, bpp {d}\n", .{ self.width, self.height, self.dib_file_header.color_planes, self.dib_file_header.bpp });
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

    fn read_BMP_header(self: *BMPBuilder) Error!void {
        // type
        self.bmp_file_header.bmp_type[0] = try self.file_data.read(u8);
        self.bmp_file_header.bmp_type[1] = try self.file_data.read(u8);
        //TODO handle types
        if (!std.mem.eql(u8, &self.bmp_file_header.bmp_type, "BM")) {
            return Error.InvalidBMPHeader;
        }
        BMP_LOG.info("file type {s}\n", .{self.bmp_file_header.bmp_type});
        // size
        self.bmp_file_header.file_size = try self.file_data.read(u32);
        BMP_LOG.info("file size {d}\n", .{self.bmp_file_header.file_size});
        // reserved
        self.bmp_file_header.reserved1 = try self.file_data.read(u16);
        self.bmp_file_header.reserved2 = try self.file_data.read(u16);
        // offset
        self.bmp_file_header.offset = try self.file_data.read(u32);
        BMP_LOG.info("offset {d}\n", .{self.bmp_file_header.offset});
    }

    pub fn deinit(self: *BMPBuilder) void {
        self.file_data.deinit();
    }
};

test "CAT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.write_BMP("test_output/os.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "HISTOGRAM EQUALIZATION" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.histogram_equalization();
    try image.write_BMP("test_output/cat_histogram_equal_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "FFT CONVOL" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.fft_convol(try Image.ConvolMat.edge_detection());
    try image.write_BMP("test_output/cat_fft_edge_detection_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "FFT REP" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.fft_rep();
    try image.write_BMP("test_output/cat_fft_rep_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "EDGE DETECTION" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.edge_detection();
    try image.write_BMP("test_output/cat_edge_detection_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "SHEAR" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.shear(0.5, 0);
    try image.write_BMP("test_output/cat_shear_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "ROTATE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.rotate(45);
    try image.write_BMP("test_output/cat_rotate_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "CAT_REFLECT_X" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.reflection(.x);
    try image.write_BMP("test_output/cat_reflectx_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "CAT_REFLECT_Y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.reflection(.y);
    try image.write_BMP("test_output/cat_reflecty_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
test "CAT_REFLECT_XY" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/cat.bmp", .BMP);
    try image.reflection(.xy);
    try image.write_BMP("test_output/cat_reflectxy_bmp.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}

test "V3" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/basic0.bmp", .BMP);
    try image.write_BMP("test_output/v3.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}

test "V5" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/bmp/basic1.bmp", .BMP);
    try image.write_BMP("test_output/v5.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        BMP_LOG.warn("Leaked!\n", .{});
    }
}
