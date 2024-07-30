//https://en.wikipedia.org/wiki/BMP_file_format
const std = @import("std");
const utils = @import("utils.zig");

pub const BMPImage_Error = error{
    NOT_LOADED,
    INVALID_BMP_HEADER,
    INVALID_DIB_HEADER,
};

pub const BMPImage = struct {
    _file_data: utils.BitReader = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,
    data: std.ArrayList(utils.Pixel(u8)) = undefined,
    _file_size: u32 = undefined,
    _bpp: u32 = undefined,
    _offset: u32 = undefined,
    width: u32 = undefined,
    height: u32 = undefined,

    pub fn convert_grayscale(self: *BMPImage) !void {
        if (self._loaded) {
            for (0..self.data.items.len) |i| {
                const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].r)) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].g)) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].b)) * 0.1140));
                self.data.items[i].r = gray;
                self.data.items[i].g = gray;
                self.data.items[i].b = gray;
            }
        } else {
            return BMPImage.NOT_LOADED;
        }
    }
    pub fn load_PNG(self: *BMPImage, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._file_data = utils.BitReader{};
        try self._file_data.init_file(file_name, self._allocator, .{ .little_endian = true });
        std.debug.print("reading bmp\n", .{});
        try self.read_BMP_header();
        try self.read_DIB_header();
        self.data = try std.ArrayList(utils.Pixel(u8)).initCapacity(self._allocator.*, self.height * self.width);
        self.data.expandToCapacity();
        try self.read_color_data();
        self._loaded = true;
    }

    pub fn get(self: *BMPImage, x: usize, y: usize) *utils.Pixel(u8) {
        return &self.data.items[y * self.width + x];
    }

    fn read_color_data(self: *BMPImage) (utils.ByteStream_Error || utils.BitReader_Error || BMPImage_Error)!void {
        const padding_size = self.width % 4;
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) {
            while (j < self.width) {
                if (self._bpp == 24) {
                    self.data.items[i * self.width + j] = utils.Pixel(u8){
                        .b = try self._file_data.read_byte(),
                        .g = try self._file_data.read_byte(),
                        .r = try self._file_data.read_byte(),
                    };
                    j += 1;
                }
            }
            for (0..padding_size) |_| {
                _ = try self._file_data.read_byte();
            }
            j = 0;
            if (i == 0) break;
            i -= 1;
        }
    }

    fn read_DIB_header(self: *BMPImage) (utils.ByteStream_Error || utils.BitReader_Error || BMPImage_Error)!void {
        const header_size = try self._file_data.read_int();
        std.debug.print("header_size {d}\n", .{header_size});
        // OS/2
        if (header_size == 12) {
            self.width = try self._file_data.read_word();
            self.height = try self._file_data.read_word();
            const color_planes = try self._file_data.read_word();
            if (color_planes != 1) {
                return BMPImage_Error.INVALID_DIB_HEADER;
            }
            self._bpp = try self._file_data.read_word();
            std.debug.print("width {d}, height {d}, color_planes {d}, bpp {d}\n", .{ self.width, self.height, color_planes, self._bpp });
        }
        //TODO handle other headers
        else {
            return BMPImage_Error.INVALID_DIB_HEADER;
        }
    }

    fn read_BMP_header(self: *BMPImage) (utils.ByteStream_Error || utils.BitReader_Error || BMPImage_Error)!void {
        var bmp_type: [2]u8 = [_]u8{0} ** 2;
        // type
        bmp_type[0] = try self._file_data.read_byte();
        bmp_type[1] = try self._file_data.read_byte();
        //TODO handle other headers
        if (!std.mem.eql(u8, &bmp_type, "BM")) {
            return BMPImage_Error.INVALID_BMP_HEADER;
        }
        std.debug.print("file type {s}\n", .{bmp_type});
        // size
        self._file_size = try self._file_data.read_int();
        std.debug.print("file size {d}\n", .{self._file_size});
        // reserved
        _ = try self._file_data.read_word();
        _ = try self._file_data.read_word();
        // offset
        self._offset = try self._file_data.read_int();
        std.debug.print("offset {d}\n", .{self._offset});
    }

    pub fn write_BMP(self: *BMPImage, file_name: []const u8) !void {
        if (!self._loaded) {
            return BMPImage_Error.NOT_LOADED;
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

test "BASIC 16" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = BMPImage{};
    try image.load_PNG("tests/bmp/parrot.bmp", &allocator);
    try image.write_BMP("parrot2.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
