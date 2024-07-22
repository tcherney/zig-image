//https://www.w3.org/TR/PNG-Structure.html
//https://iter.ca/post/png/
//https://pyokagan.name/blog/2019-10-18-zlibinflate/
const std = @import("std");
const utils = @import("utils.zig");

pub const PNGImage_Error = error{
    INVALID_SIGNATURE,
    INVALID_CRC,
    INVALID_COMPRESSION_METHOD,
    INVALID_WINDOW_SIZE,
    INVALID_DEFLATE_CHECKSUM,
    INVALID_PRESET_DICT,
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

    pub fn read_chunk(self: *Chunk, file_data: *utils.ByteStream) (std.mem.Allocator.Error || utils.ByteStream_Error)!void {
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
    pub fn verify_crc(self: *Chunk) PNGImage_Error!void {
        const calced_crc = calc_crc(self._data, @as(u32, @intCast(self._data.len)));
        std.debug.print("calculated crc {d}\n", .{calced_crc});
        if (calced_crc != self.crc_check) {
            return PNGImage_Error.INVALID_CRC;
        }
    }
    pub fn deinit(self: *Chunk) void {
        self._allocator.free(self._data);
    }
};

pub const PNGImage = struct {
    _file_data: utils.ByteStream = undefined,
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
    _plte_data: ?[]u8 = null,
    _idat_data: []u8 = undefined,
    _idat_data_len: usize = 0,

    fn read_chucks(self: *PNGImage) (utils.ByteStream_Error || PNGImage_Error || std.mem.Allocator.Error)!void {
        self._chunks = std.ArrayList(Chunk).init(self._allocator.*);
        while (self._file_data.getPos() != self._file_data.getEndPos()) {
            var chunk: Chunk = Chunk{};
            chunk.init(self._allocator);
            try chunk.read_chunk(&self._file_data);
            try chunk.verify_crc();
            try self._chunks.append(chunk);
            if (std.mem.eql(u8, chunk.chunk_type, "IDAT")) {
                self._idat_data_len += chunk.chunk_data.len;
            } else if (std.mem.eql(u8, chunk.chunk_type, "IEND")) {
                break;
            }
        }
        std.debug.print("all chunks read\n", .{});
    }
    fn handle_chunks(self: *PNGImage) std.mem.Allocator.Error!void {
        self._idat_data = try self._allocator.alloc(u8, self._idat_data_len);
        var index: usize = 0;
        for (self._chunks.items) |*chunk| {
            if (std.mem.eql(u8, chunk.chunk_type, "IHDR")) {
                self.handle_IHDR(chunk);
            } else if (std.mem.eql(u8, chunk.chunk_type, "PLTE")) {
                self._plte_data.? = chunk.chunk_data;
            } else if (std.mem.eql(u8, chunk.chunk_type, "IDAT")) {
                self.handle_IDAT(chunk, &index);
            }
        }
        std.debug.print("index = {d}, len = {d}\n", .{ index, self._idat_data_len });
    }
    fn handle_IDAT(self: *PNGImage, chunk: *Chunk, index: *usize) void {
        for (chunk.chunk_data) |data| {
            self._idat_data[index.*] = data;
            index.* += 1;
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
    fn read_sig(self: *PNGImage) (utils.ByteStream_Error || PNGImage_Error)!void {
        std.debug.print("reading signature\n", .{});
        const signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
        for (signature) |sig| {
            const current = try self._file_data.readByte();
            if (current != sig) {
                return PNGImage_Error.INVALID_SIGNATURE;
            }
        }
    }
    fn decompress(self: *PNGImage) (std.mem.Allocator.Error || utils.ByteStream_Error || PNGImage_Error)![]u8 {
        var bit_reader: utils.BitReader(PNGImage) = utils.BitReader(PNGImage){};
        bit_reader.init(self._idat_data);
        defer bit_reader.deinit();
        const CMF = try bit_reader.read_byte();
        const CM = CMF & 0xF;
        std.debug.print("compression method {d}\n", .{CM});
        if (CM != 8) {
            return PNGImage_Error.INVALID_COMPRESSION_METHOD;
        }
        const CINFO = (CMF >> 4) & 0xF;
        if (CINFO > 7) {
            return PNGImage_Error.INVALID_WINDOW_SIZE;
        }
        const FLG = bit_reader.read_byte();
        if ((CMF * 256 + FLG) % 0x1F != 0) {
            return PNGImage_Error.INVALID_DEFLATE_CHECKSUM;
        }
        const FDICT = (FLG >> 5) & 1;
        if (FDICT != 0) {
            return PNGImage_Error.INVALID_PRESET_DICT;
        }
        const ret = self.inflate(&bit_reader);
        var ADLER32 = bit_reader.read_byte();
        ADLER32 |= bit_reader.read_byte() << 8;
        ADLER32 |= bit_reader.read_byte() << 16;
        ADLER32 |= bit_reader.read_byte() << 24;
        return ret;
    }
    fn inflate(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage)) std.ArrayList(u8) {
        var BFINAL = 0;
        var ret = std.ArrayList(u8).init(self._allocator);
    }
    pub fn load_PNG(self: *PNGImage, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._file_data = utils.ByteStream{};
        try self._file_data.init_file(file_name, self._allocator);
        std.debug.print("reading png\n", .{});
        try self.read_sig();
        try self.read_chucks();
        try self.handle_chunks();
        var ret = try self.decompress();
        defer std.ArrayList(u8).deinit(ret);
    }

    pub fn deinit(self: *PNGImage) void {
        self._file_data.deinit();
        for (self._chunks.items) |*chunk| {
            chunk.deinit();
        }
        std.ArrayList(Chunk).deinit(self._chunks);
        self._allocator.free(self._idat_data);
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
