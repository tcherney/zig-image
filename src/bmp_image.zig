//https://en.wikipedia.org/wiki/BMP_file_format
const std = @import("std");
const utils = @import("utils.zig");

pub const BMPImage_Error = error{
    NOT_LOADED,
};

pub const BMPImage = struct {
    _file_data: utils.ByteStream = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,
    data: std.ArrayList(utils.Pixel(u8)) = undefined,
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
        self._file_data = utils.ByteStream{};
        try self._file_data.init_file(file_name, self._allocator);
        std.debug.print("reading bmp\n", .{});
        self._loaded = true;
    }

    pub fn get(self: *BMPImage, x: usize, y: usize) *utils.Pixel(u8) {
        return &self.data.items[y * self.width + x];
    }

    pub fn write_BMP(self: *BMPImage, file_name: []const u8) !void {
        if (!self._loaded) {
            return BMPImage.NOT_LOADED;
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
