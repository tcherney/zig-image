//https://www.w3.org/TR/PNG-Structure.html
//https://iter.ca/post/png/
const std = @import("std");
const byte_file_stream = @import("byte_file_stream.zig");

pub const PNGIMAGE_ERRORS = error{
    INVALID_SIGNATURE,
};

pub const PNGImage = struct {
    _file_data: byte_file_stream.ByteFileStream = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,

    fn read_chucks(self: *PNGImage) (byte_file_stream.BYTEFILESTREAM_ERRORS || PNGIMAGE_ERRORS || error{OutOfMemory})!void {
        while (self._file_data.getPos() != self._file_data.getEndPos()) {
            const length = (@as(u32, @intCast(try self._file_data.readByte())) << 24) | (@as(u32, @intCast(try self._file_data.readByte())) << 16) | (@as(u32, @intCast(try self._file_data.readByte())) << 8) | (@as(u32, @intCast(try self._file_data.readByte())));
            std.debug.print("length {d}\n", .{length});
            const chunk_type = [_]u8{ try self._file_data.readByte(), try self._file_data.readByte(), try self._file_data.readByte(), try self._file_data.readByte() };
            std.debug.print("chunk type {s}\n", .{chunk_type});
            const data: []u8 = try self._allocator.alloc(u8, length);
            defer self._allocator.free(data);
            for (0..data.len) |i| {
                data[i] = try self._file_data.readByte();
                std.debug.print("{x} ", .{data[i]});
            }
            std.debug.print("\n", .{});
            const crc = (@as(u32, @intCast(try self._file_data.readByte())) << 24) | (@as(u32, @intCast(try self._file_data.readByte())) << 16) | (@as(u32, @intCast(try self._file_data.readByte())) << 8) | (@as(u32, @intCast(try self._file_data.readByte())));
            std.debug.print("crc {x}\n", .{crc});
            break;
        }
    }
    fn read_sig(self: *PNGImage) (byte_file_stream.BYTEFILESTREAM_ERRORS || PNGIMAGE_ERRORS)!void {
        std.debug.print("reading signature\n", .{});
        const signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
        for (signature) |sig| {
            const current = try self._file_data.readByte();
            if (current != sig) {
                return PNGIMAGE_ERRORS.INVALID_SIGNATURE;
            }
        }
    }
    pub fn load_PNG(self: *PNGImage, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._file_data = byte_file_stream.ByteFileStream{};
        try self._file_data.init(file_name, self._allocator);
        std.debug.print("reading png\n", .{});
        try self.read_sig();
        try self.read_chucks();
    }

    pub fn clean_up(self: *PNGImage) void {
        self._file_data.clean_up();
    }
};

test "SHIELD" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load_PNG("shield.png", &allocator);
    //try image.write_BMP("shield.png");
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
