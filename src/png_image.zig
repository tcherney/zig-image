//https://www.w3.org/TR/PNG-Structure.html
//https://iter.ca/post/png/
const std = @import("std");
const byte_file_stream = @import("byte_file_stream.zig");

pub const PNGIMAGE_ERRORS = error{
    INVALID_SIGNATURE,
    INVALID_CRC,
};

var crc_table: [256]u32 = [_]u32{0} ** 256;
var crc_table_computed: bool = false;

fn make_crc_table() void {
    var c: u32 = undefined;
    for (0..256) |n| {
        c = @as(u32, @intCast(n));
        for (0..8) |_| {
            if (c & 1 > 0) {
                c = 0xedb88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        crc_table[n] = c;
    }
    crc_table_computed = true;
}
fn update_crc(crc: u32, buf: []u8, length: u32) u32 {
    var c: u32 = crc;
    if (!crc_table_computed) {
        make_crc_table();
    }
    for (0..length) |i| {
        c = crc_table[(c ^ buf[i]) & 0xff] ^ (c >> 8);
    }
    return c;
}

fn calc_crc(buf: []u8, length: u32) u32 {
    return update_crc(0xFFFFFFFF, buf, length) ^ 0xFFFFFFFF;
}

const Chunk = struct {
    _data: []u8 = undefined,
    _allocator: *std.mem.Allocator = undefined,
    length: u32 = undefined,
    chunk_type: []u8 = undefined,
    chunk_data: []u8 = undefined,
    crc_check: u32 = undefined,
    pub fn init(self: *Chunk, allocator: *std.mem.Allocator) void {
        self._allocator = allocator;
    }

    pub fn read_chunk(self: *Chunk, file_data: *byte_file_stream.ByteFileStream) (std.mem.Allocator.Error || byte_file_stream.BYTEFILESTREAM_ERRORS)!void {
        self.length = (@as(u32, @intCast(try file_data.readByte())) << 24) | (@as(u32, @intCast(try file_data.readByte())) << 16) | (@as(u32, @intCast(try file_data.readByte())) << 8) | (@as(u32, @intCast(try file_data.readByte())));
        std.debug.print("length {d}\n", .{self.length});
        self._data = try self._allocator.alloc(u8, self.length + 4);
        self._data[0] = try file_data.readByte();
        self._data[1] = try file_data.readByte();
        self._data[2] = try file_data.readByte();
        self._data[3] = try file_data.readByte();
        self.chunk_type = self._data[0..4];
        std.debug.print("chunk type {s}\n", .{self.chunk_type});
        for (4..self._data.len) |i| {
            self._data[i] = try file_data.readByte();
            //std.debug.print("{x} ", .{self._data[i]});
        }
        //std.debug.print("\n", .{});
        self.chunk_data = self._data[4..self._data.len];
        self.crc_check = (@as(u32, @intCast(try file_data.readByte())) << 24) | (@as(u32, @intCast(try file_data.readByte())) << 16) | (@as(u32, @intCast(try file_data.readByte())) << 8) | (@as(u32, @intCast(try file_data.readByte())));
        std.debug.print("crc {d}\n", .{self.crc_check});
    }
    pub fn verify_crc(self: *Chunk) PNGIMAGE_ERRORS!void {
        const calced_crc = calc_crc(self._data, @as(u32, @intCast(self._data.len)));
        std.debug.print("calculated crc {d}\n", .{calced_crc});
        if (calced_crc != self.crc_check) {
            return PNGIMAGE_ERRORS.INVALID_CRC;
        }
    }
    pub fn deinit(self: *Chunk) void {
        self._allocator.free(self._data);
    }
};

pub const PNGImage = struct {
    _file_data: byte_file_stream.ByteFileStream = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,
    _chunks: std.ArrayList(Chunk) = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    bit_depth: u8 = undefined,
    color_type: u8 = undefined,
    compression_method: u8 = undefined,
    filter_method: u8 = undefined,
    interlace_method: u8 = undefined,

    fn read_chucks(self: *PNGImage) (byte_file_stream.BYTEFILESTREAM_ERRORS || PNGIMAGE_ERRORS || std.mem.Allocator.Error)!void {
        self._chunks = std.ArrayList(Chunk).init(self._allocator.*);
        while (self._file_data.getPos() != self._file_data.getEndPos()) {
            var chunk: Chunk = Chunk{};
            chunk.init(self._allocator);
            try chunk.read_chunk(&self._file_data);
            try chunk.verify_crc();
            try self._chunks.append(chunk);
            if (std.mem.eql(u8, chunk.chunk_type, "IEND")) {
                break;
            }
        }
        std.debug.print("all chunks read\n", .{});
    }
    fn handle_chunks(self: *PNGImage) void {
        for (self._chunks.items) |*chunk| {
            if (std.mem.eql(u8, chunk.chunk_type, "IHDR")) {
                self.handle_IHDR(chunk);
            }
        }
    }
    fn handle_IHDR(self: *PNGImage, chunk: *Chunk) void {
        self.width = (@as(u32, @intCast(chunk.chunk_data[0])) << 24) | (@as(u32, @intCast(chunk.chunk_data[1])) << 16) | (@as(u32, @intCast(chunk.chunk_data[2])) << 8) | (@as(u32, @intCast(chunk.chunk_data[3])));
        self.height = (@as(u32, @intCast(chunk.chunk_data[4])) << 24) | (@as(u32, @intCast(chunk.chunk_data[5])) << 16) | (@as(u32, @intCast(chunk.chunk_data[6])) << 8) | (@as(u32, @intCast(chunk.chunk_data[7])));
        self.bit_depth = chunk.chunk_data[8];
        self.color_type = chunk.chunk_data[9];
        self.compression_method = chunk.chunk_data[10];
        self.filter_method = chunk.chunk_data[11];
        self.interlace_method = chunk.chunk_data[12];
        std.debug.print("width {d}, height {d}, bit_depth {d}, color_type {d}, compression_method {d}, filter_method {d}, interlace_method {d}\n", .{ self.width, self.height, self.bit_depth, self.color_type, self.compression_method, self.filter_method, self.interlace_method });
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
        self.handle_chunks();
    }

    pub fn deinit(self: *PNGImage) void {
        self._file_data.deinit();
        for (self._chunks.items) |*chunk| {
            chunk.deinit();
        }
        std.ArrayList(Chunk).deinit(self._chunks);
    }
};

test "SHIELD" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load_PNG("shield.png", &allocator);
    //try image.write_BMP("shield.png");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
