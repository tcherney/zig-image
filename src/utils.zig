// Small utility struct that gives basic byte by byte reading of a file after its been loaded into memory
const std = @import("std");

pub fn HuffmanTree(comptime T: type) type {
    return struct {
        root: Node,
        allocator: std.mem.Allocator,
        const Self = @This();
        pub const Node = struct {
            symbol: T,
            left: ?*Node,
            right: ?*Node,
            pub fn init() Node {
                return Node{
                    .symbol = ' ',
                    .left = null,
                    .right = null,
                };
            }
        };
        pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!HuffmanTree(T) {
            return .{
                .root = Node.init(),
                .allocator = allocator,
            };
        }
        pub fn deinit_node(self: *Self, node: ?*Node) void {
            if (node) |parent| {
                self.deinit_node(parent.left);
                self.deinit_node(parent.right);
                self.allocator.destroy(parent);
            }
        }
        pub fn deinit(self: *Self) void {
            self.deinit_node(self.root.left);
            self.deinit_node(self.root.right);
        }
        pub fn insert(self: *Self, codeword: T, n: T, symbol: T) std.mem.Allocator.Error!void {
            std.debug.print("inserting {b} with length {d} and symbol {d}\n", .{ codeword, n, symbol });
            var node: *Node = &self.root;
            var i = n - 1;
            var next_node: ?*Node = null;
            while (i >= 0) : (i -= 1) {
                const b = codeword & std.math.shl(T, 1, i);
                std.debug.print("b {d}\n", .{b});
                if (b != 0) {
                    if (node.right) |right| {
                        next_node = right;
                    } else {
                        node.right = try self.allocator.create(Node);
                        node.right.?.* = Node.init();
                        next_node = node.right;
                    }
                } else {
                    if (node.left) |left| {
                        next_node = left;
                    } else {
                        node.left = try self.allocator.create(Node);
                        node.left.?.* = Node.init();
                        next_node = node.left;
                    }
                }
                node = next_node.?;
                if (i == 0) break;
            }
            node.symbol = symbol;
        }
    };
}

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
    INVALID_ARGS,
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
        pub fn read_word(self: *Self, args: anytype) (BitReader_Error || ByteStream_Error)!u16 {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .Struct) {
                return BitReader_Error.INVALID_ARGS;
            }
            const fields_info = args_type_info.Struct.fields;
            if (fields_info.len != 0 and fields_info.len != 1) {
                return BitReader_Error.INVALID_ARGS;
            }
            if (fields_info.len != 0 and !std.mem.eql(u8, fields_info[0].name, "little_endian")) {
                return BitReader_Error.INVALID_ARGS;
            }
            const little_endian: bool = if (fields_info.len == 1) @field(args, "little_endian") else false;
            self.next_bit = 0;
            var ret_word: u16 = @as(u16, try self._byte_stream.readByte());
            if (little_endian) {
                ret_word |= @as(u16, @intCast(try self._byte_stream.readByte())) << 8;
            } else {
                ret_word <<= 8;
                ret_word += try self._byte_stream.readByte();
            }

            return ret_word;
        }
        pub fn read_int(self: *Self, args: anytype) (BitReader_Error || ByteStream_Error)!u32 {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .Struct) {
                return BitReader_Error.INVALID_ARGS;
            }
            const fields_info = args_type_info.Struct.fields;
            if (fields_info.len != 0 and fields_info.len != 1) {
                return BitReader_Error.INVALID_ARGS;
            }
            if (fields_info.len != 0 and !std.mem.eql(u8, fields_info[0].name, "little_endian")) {
                return BitReader_Error.INVALID_ARGS;
            }
            const little_endian: bool = if (fields_info.len == 1) @field(args, "little_endian") else false;
            self.next_bit = 0;
            var ret_int: u32 = @as(u32, try self._byte_stream.readByte());
            if (little_endian) {
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte())) << 8;
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte())) << 16;
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte())) << 24;
            } else {
                ret_int <<= 24;
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte())) << 16;
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte())) << 8;
                ret_int |= @as(u32, @intCast(try self._byte_stream.readByte()));
            }

            return ret_int;
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

test "HUFFMAN_TREE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var t = try HuffmanTree(u32).init(allocator);
    try t.insert(1, 2, 'A');
    try t.insert(1, 1, 'B');
    try t.insert(0, 3, 'C');
    try t.insert(1, 3, 'D');
    t.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
