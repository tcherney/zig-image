// Small utility struct that gives basic byte by byte reading of a file after its been loaded into memory
const std = @import("std");

pub const ByteStream_Error = error{
    OUT_OF_BOUNDS,
};

pub const ByteStream = struct {
    _index: usize = 0,
    _buffer: []u8 = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _own_data: bool = false,
    pub fn init_file(self: *ByteStream, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._own_data = true;
        const _file = try std.fs.cwd().openFile(file_name, .{});
        defer _file.close();
        const size_limit = std.math.maxInt(u32);
        self._buffer = try _file.readToEndAlloc(self._allocator.*, size_limit);
        self._index = 0;
    }
    pub fn init(self: *ByteStream, data: []u8) void {
        self._buffer = data;
    }
    pub fn deinit(self: *ByteStream) void {
        if (self._own_data) {
            self._allocator.free(self._buffer);
        }
    }
    pub fn getPos(self: *ByteStream) usize {
        return self._index;
    }
    pub fn getEndPos(self: *ByteStream) usize {
        return self._buffer.len - 1;
    }
    pub fn peek(self: *ByteStream) ByteStream_Error!u8 {
        if (self._index > self._buffer.len - 1) {
            return ByteStream_Error.OUT_OF_BOUNDS;
        }
        return self._buffer[self._index];
    }
    pub fn readByte(self: *ByteStream) ByteStream_Error!u8 {
        if (self._index > self._buffer.len - 1) {
            return ByteStream_Error.OUT_OF_BOUNDS;
        }
        self._index += 1;
        return self._buffer[self._index - 1];
    }
};

pub const BitReader_Error = error{
    INVALID_READ,
};

pub fn BitReader(comptime T: type) type {
    return struct {
        next_byte: u32 = 0,
        next_bit: u32 = 0,
        _byte_stream: ByteStream = undefined,
        const Self = @This();
        pub fn init(self: *Self, data: []u8) void {
            self._byte_stream = ByteStream{};
            self._byte_stream.init(data);
        }
        pub fn init_file(self: *Self, file_name: []const u8, allocator: *std.mem.Allocator) !void {
            self._byte_stream = ByteStream{};
            try self._byte_stream.init_file(file_name, allocator);
        }
        pub fn deinit(self: *Self) void {
            self._byte_stream.deinit();
        }
        pub fn has_bits(self: *Self) bool {
            return if (self._byte_stream.getPos() != self._byte_stream.getEndPos()) true else false;
        }
        pub fn read_byte(self: *Self) ByteStream_Error!u8 {
            self.next_bit = 0;
            return try self._byte_stream.readByte();
        }
        pub fn read_word(self: *Self) ByteStream_Error!u16 {
            self.next_bit = 0;
            var ret_word: u16 = @as(u16, try self._byte_stream.readByte());
            ret_word <<= 8;
            ret_word += try self._byte_stream.readByte();
            return ret_word;
        }
        pub fn read_bit(self: *Self) (BitReader_Error || ByteStream_Error)!u32 {
            if (self.next_bit == 0) {
                if (!self.has_bits()) {
                    return BitReader_Error.INVALID_READ;
                }
                self.next_byte = try self._byte_stream.readByte();
                if (std.mem.eql(u8, @typeName(T), "jpeg_image.JPEGImage")) {
                    while (self.next_byte == 0xFF) {
                        var marker: u8 = try self._byte_stream.peek();
                        while (marker == 0xFF) {
                            _ = try self._byte_stream.readByte();
                            marker = try self._byte_stream.peek();
                        }
                        if (marker == 0x00) {
                            _ = try self._byte_stream.readByte();
                            break;
                        } else if (marker >= 0xD0 and marker <= 0xD7) {
                            _ = try self._byte_stream.readByte();
                            self.next_byte = try self._byte_stream.readByte();
                        } else {
                            return BitReader_Error.INVALID_READ;
                        }
                    }
                }
            }
            const bit: u32 = (self.next_byte >> @as(u5, @intCast(7 - self.next_bit))) & 1;
            self.next_bit = (self.next_bit + 1) % 8;
            return bit;
        }
        pub fn read_bits(self: *Self, length: u32) (BitReader_Error || ByteStream_Error)!u32 {
            var bits: u32 = 0;
            for (0..length) |_| {
                const bit = try self.read_bit();
                bits = (bits << 1) | bit;
            }
            return bits;
        }
        pub fn align_reader(self: *Self) void {
            self.next_bit = 0;
        }
    };
}