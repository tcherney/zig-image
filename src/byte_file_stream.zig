// Small utility struct that gives basic byte by byte reading of a file after its been loaded into memory
const std = @import("std");

pub const BYTEFILESTREAM_ERRORS = error{
    OUT_OF_BOUNDS,
};

pub const ByteFileStream = struct {
    _index: usize = 0,
    _buffer: []u8 = undefined,
    _allocator: *std.mem.Allocator = undefined,
    pub fn init(self: *ByteFileStream, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        const _file = try std.fs.cwd().openFile(file_name, .{});
        defer _file.close();
        const size_limit = std.math.maxInt(u32);
        self._buffer = try _file.readToEndAlloc(self._allocator.*, size_limit);
        self._index = 0;
    }
    pub fn clean_up(self: *ByteFileStream) void {
        self._allocator.free(self._buffer);
    }
    pub fn getPos(self: *ByteFileStream) usize {
        return self._index;
    }
    pub fn getEndPos(self: *ByteFileStream) usize {
        return self._buffer.len - 1;
    }
    pub fn peek(self: *ByteFileStream) BYTEFILESTREAM_ERRORS!u8 {
        if (self._index > self._buffer.len - 1) {
            return BYTEFILESTREAM_ERRORS.OUT_OF_BOUNDS;
        }
        return self._buffer[self._index];
    }
    pub fn readByte(self: *ByteFileStream) BYTEFILESTREAM_ERRORS!u8 {
        if (self._index > self._buffer.len - 1) {
            return BYTEFILESTREAM_ERRORS.OUT_OF_BOUNDS;
        }
        self._index += 1;
        return self._buffer[self._index - 1];
    }
};
