//https://www.w3.org/TR/PNG-Structure.html
//https://iter.ca/post/png/
//https://pyokagan.name/blog/2019-10-18-zlibinflate/
//https://datatracker.ietf.org/doc/html/rfc1951
//https://github.com/madler/zlib/blob/master/contrib/puff/puff.c
const std = @import("std");
const utils = @import("utils.zig");

pub const PNGImage_Error = error{
    INVALID_SIGNATURE,
    INVALID_CRC,
    INVALID_COMPRESSION_METHOD,
    INVALID_WINDOW_SIZE,
    INVALID_DEFLATE_CHECKSUM,
    INVALID_PRESET_DICT,
    INVALID_BTYPE,
    INVALID_HUFFMAN_SYMBOL,
    INVALID_FILTER,
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

const LengthExtraBits = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
const LengthBase = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
const DistanceExtraBits = [_]u16{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
const DistanceBase = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
const CodeLengthCodesOrder = [_]u16{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

pub const PNGImage = struct {
    _file_data: utils.ByteStream = undefined,
    _allocator: *std.mem.Allocator = undefined,
    _loaded: bool = false,
    _chunks: std.ArrayList(Chunk) = undefined,
    data: std.ArrayList(utils.Pixel) = undefined,
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
    fn decompress(self: *PNGImage) (utils.Max_error || std.mem.Allocator.Error || utils.ByteStream_Error || PNGImage_Error || utils.BitReader_Error)!std.ArrayList(u8) {
        var bit_reader: utils.BitReader(PNGImage) = utils.BitReader(PNGImage){};
        bit_reader.init(self._idat_data);
        std.debug.print("idat data len {d}\n", .{self._idat_data.len});
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
        const FLG = try bit_reader.read_byte();
        if ((@as(u32, @intCast(CMF)) * 256 + @as(u32, @intCast(FLG))) % 0x1F != 0) {
            return PNGImage_Error.INVALID_DEFLATE_CHECKSUM;
        }
        const FDICT = (FLG >> 5) & 1;
        if (FDICT != 0) {
            return PNGImage_Error.INVALID_PRESET_DICT;
        }
        const ret: std.ArrayList(u8) = try self.inflate(&bit_reader);
        var ADLER32: u32 = try bit_reader.read_byte();
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 8;
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 16;
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 24;
        return ret;
    }
    fn inflate(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage)) (utils.Max_error || std.mem.Allocator.Error || utils.BitReader_Error || utils.ByteStream_Error || PNGImage_Error)!std.ArrayList(u8) {
        var BFINAL: u32 = 0;
        var ret: std.ArrayList(u8) = std.ArrayList(u8).init(self._allocator.*);
        while (BFINAL == 0) {
            BFINAL = try bit_reader.read_bit();
            const BTYPE = try bit_reader.read_bits(2);
            std.debug.print("BFINAL {d}, BTYPE {d}\n", .{ BFINAL, BTYPE });
            if (BTYPE == 0) {
                try self.inflate_block_no_compression(bit_reader, &ret);
            } else if (BTYPE == 1) {
                try self.inflate_block_fixed(bit_reader, &ret);
            } else if (BTYPE == 2) {
                try self.inflate_block_dynamic(bit_reader, &ret);
            } else {
                return PNGImage_Error.INVALID_BTYPE;
            }
        }
        return ret;
    }
    fn decode_symbol(_: *PNGImage, bit_reader: *utils.BitReader(PNGImage), tree: *utils.HuffmanTree(u16)) !u16 {
        var node = tree.root;
        while (node.left != null and node.right != null) {
            const bit = try bit_reader.read_bit();
            node = if (bit != 0) node.right.?.* else node.left.?.*;
        }
        return node.symbol;
    }
    fn inflate_block_no_compression(_: *PNGImage, bit_reader: *utils.BitReader(PNGImage), ret: *std.ArrayList(u8)) (utils.Max_error || std.mem.Allocator.Error || utils.BitReader_Error || utils.ByteStream_Error || PNGImage_Error)!void {
        std.debug.print("inflate no compression\n", .{});
        const LEN = try bit_reader.read_word(.{ .little_endian = false });
        std.debug.print("LEN {d}\n", .{LEN});
        const NLEN = try bit_reader.read_word(.{ .little_endian = true });
        std.debug.print("NLEN {d}\n", .{NLEN});
        for (0..LEN) |_| {
            try ret.append(try bit_reader.read_byte());
        }
    }
    fn bit_length_list_to_tree(self: *PNGImage, bit_length_list: []u16, alphabet: []u16) !*utils.HuffmanTree(u16) {
        const MAX_BITS = try utils.max_array(u16, bit_length_list);
        var bl_count: []u16 = try self._allocator.alloc(u16, MAX_BITS + 1);
        defer self._allocator.free(bl_count);
        for (0..bl_count.len) |i| {
            var sum: u16 = 0;
            for (bit_length_list) |j| {
                if (j == @as(u16, @intCast(i)) and i != 0) {
                    sum += 1;
                }
            }
            bl_count[i] = sum;
        }
        var next_code: std.ArrayList(u16) = std.ArrayList(u16).init(self._allocator.*);
        defer std.ArrayList(u16).deinit(next_code);
        try next_code.append(0);
        try next_code.append(0);
        for (2..MAX_BITS + 1) |bits| {
            try next_code.append((next_code.items[bits - 1] + bl_count[bits - 1]) << 1);
        }
        var tree: *utils.HuffmanTree(u16) = try self._allocator.create(utils.HuffmanTree(u16));
        tree.* = try utils.HuffmanTree(u16).init(self._allocator.*);
        const min_len = @min(alphabet.len, bit_length_list.len);
        for (0..min_len) |i| {
            if (bit_length_list[i] != 0) {
                try tree.insert(next_code.items[bit_length_list[i]], bit_length_list[i], alphabet[i]);
                next_code.items[bit_length_list[i]] += 1;
            }
        }
        return tree;
    }
    fn inflate_block_data(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage), literal_length_tree: *utils.HuffmanTree(u16), distance_tree: *utils.HuffmanTree(u16), ret: *std.ArrayList(u8)) !void {
        while (true) {
            var symbol = try self.decode_symbol(bit_reader, literal_length_tree);
            if (symbol <= 255) {
                try ret.append(@as(u8, @intCast(symbol)));
            } else if (symbol == 256) {
                return;
            } else {
                symbol -= 257;
                const length = @as(u16, @intCast(try bit_reader.read_bits(LengthExtraBits[symbol]) + LengthBase[symbol]));
                const distance_symbol = try self.decode_symbol(bit_reader, distance_tree);
                const distance = @as(u16, @intCast(try bit_reader.read_bits(DistanceExtraBits[distance_symbol]) + DistanceBase[distance_symbol]));
                //std.debug.print("ret.items.len {d}, distance {d}\n", .{ ret.items.len, distance });
                for (0..length) |_| {
                    try ret.append(ret.items[ret.items.len - distance]);
                }
            }
        }
    }
    fn decode_trees(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage)) !struct { literal_length_tree: *utils.HuffmanTree(u16), distance_tree: *utils.HuffmanTree(u16) } {
        const HLIT: u16 = @as(u16, @intCast(try bit_reader.read_bits(5))) + 257;
        const HDIST: u16 = @as(u16, @intCast(try bit_reader.read_bits(5))) + 1;
        const HCLEN: u16 = @as(u16, @intCast(try bit_reader.read_bits(4))) + 4;
        var code_length_bit_list: [19]u16 = [_]u16{0} ** 19;
        for (0..HCLEN) |i| {
            code_length_bit_list[CodeLengthCodesOrder[i]] = @as(u16, @intCast(try bit_reader.read_bits(3)));
        }
        var alphabet: [19]u16 = [_]u16{0} ** 19;
        for (0..alphabet.len) |i| {
            alphabet[i] = @as(u16, @intCast(i));
        }
        const code_length_tree = try self.bit_length_list_to_tree(&code_length_bit_list, &alphabet);
        var bit_length_list: std.ArrayList(u16) = std.ArrayList(u16).init(self._allocator.*);
        defer std.ArrayList(u16).deinit(bit_length_list);
        while (bit_length_list.items.len < HLIT + HDIST) {
            const symbol = try self.decode_symbol(bit_reader, code_length_tree);
            if (symbol <= 15) {
                try bit_length_list.append(symbol);
            } else if (symbol == 16) {
                const prev_code_length = bit_length_list.getLast();
                const repeat_length = @as(u16, @intCast(try bit_reader.read_bits(2))) + 3;
                for (0..repeat_length) |_| {
                    try bit_length_list.append(prev_code_length);
                }
            } else if (symbol == 17) {
                const repeat_length = @as(u16, @intCast(try bit_reader.read_bits(3))) + 3;
                for (0..repeat_length) |_| {
                    try bit_length_list.append(0);
                }
            } else if (symbol == 18) {
                const repeat_length = @as(u16, @intCast(try bit_reader.read_bits(7))) + 11;
                for (0..repeat_length) |_| {
                    try bit_length_list.append(0);
                }
            } else {
                return PNGImage_Error.INVALID_HUFFMAN_SYMBOL;
            }
        }
        code_length_tree.deinit();
        self._allocator.destroy(code_length_tree);
        var literal_length_alphabet: [286]u16 = [_]u16{0} ** 286;
        for (0..literal_length_alphabet.len) |i| {
            literal_length_alphabet[i] = @as(u16, @intCast(i));
        }
        const literal_length_tree = try self.bit_length_list_to_tree(bit_length_list.items[0..HLIT], &literal_length_alphabet);
        var distance_tree_alphabet: [30]u16 = [_]u16{0} ** 30;
        for (0..distance_tree_alphabet.len) |i| {
            distance_tree_alphabet[i] = @as(u16, @intCast(i));
        }
        const distance_tree = try self.bit_length_list_to_tree(bit_length_list.items[HLIT..], &distance_tree_alphabet);
        return .{ .literal_length_tree = literal_length_tree, .distance_tree = distance_tree };
    }
    fn inflate_block_fixed(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage), ret: *std.ArrayList(u8)) !void {
        std.debug.print("inflate fixed \n", .{});
        var bit_length_list: std.ArrayList(u16) = std.ArrayList(u16).init(self._allocator.*);
        defer std.ArrayList(u16).deinit(bit_length_list);
        for (0..144) |_| {
            try bit_length_list.append(8);
        }
        for (144..256) |_| {
            try bit_length_list.append(9);
        }
        for (256..280) |_| {
            try bit_length_list.append(7);
        }
        for (280..288) |_| {
            try bit_length_list.append(8);
        }
        var literal_length_alphabet: [286]u16 = [_]u16{0} ** 286;
        for (0..literal_length_alphabet.len) |i| {
            literal_length_alphabet[i] = @as(u16, @intCast(i));
        }
        var literal_length_tree = try self.bit_length_list_to_tree(bit_length_list.items, &literal_length_alphabet);
        var distance_tree_alphabet: [30]u16 = [_]u16{0} ** 30;
        for (0..distance_tree_alphabet.len) |i| {
            distance_tree_alphabet[i] = @as(u16, @intCast(i));
        }
        var bit_list_distance: [30]u16 = [_]u16{5} ** 30;
        var distance_tree = try self.bit_length_list_to_tree(&bit_list_distance, &distance_tree_alphabet);
        try self.inflate_block_data(bit_reader, literal_length_tree, distance_tree, ret);
        literal_length_tree.deinit();
        self._allocator.destroy(literal_length_tree);
        distance_tree.deinit();
        self._allocator.destroy(distance_tree);
    }
    fn inflate_block_dynamic(self: *PNGImage, bit_reader: *utils.BitReader(PNGImage), ret: *std.ArrayList(u8)) !void {
        std.debug.print("inflate dynamic \n", .{});
        var trees = try self.decode_trees(bit_reader);
        try self.inflate_block_data(bit_reader, trees.literal_length_tree, trees.distance_tree, ret);
        trees.literal_length_tree.deinit();
        self._allocator.destroy(trees.literal_length_tree);
        trees.distance_tree.deinit();
        self._allocator.destroy(trees.distance_tree);
    }
    fn filter_scanline(_: *PNGImage, filter_type: u8, scanline: []u8, num_bytes_per_pixel: usize) void {
        if (filter_type == 0) return;
        if (filter_type == 1) {
            for (0..scanline.len) |i| {
                if (i >= num_bytes_per_pixel) {
                    scanline[i] = @as(u8, @intCast((@as(u16, @intCast(scanline[i])) + @as(u16, @intCast(scanline[i - num_bytes_per_pixel]))) % 256));
                }
            }
        }
    }
    fn data_stream_to_rgb(self: *PNGImage, ret: *std.ArrayList(u8)) (std.mem.Allocator.Error || PNGImage_Error)!void {
        self.data = std.ArrayList(utils.Pixel).init(self._allocator.*);
        var i: usize = 0;
        for (0..self.height) |_| {
            const filter_type: u8 = ret.items[i];
            std.debug.print("filter type {d} at position {d}\n", .{ filter_type, i });
            i += 1;
            const num_bytes_per_pixel: usize = if (self.color_type == 2) 3 else 4;
            self.filter_scanline(filter_type, ret.items[i .. (self.width * num_bytes_per_pixel) + i], num_bytes_per_pixel);
            for (0..self.width) |_| {
                // next 3 bytes are rgb followed by alpha
                if (self.color_type == 6) {
                    try self.data.append(utils.Pixel{
                        .r = ret.items[i],
                        .g = ret.items[i + 1],
                        .b = ret.items[i + 2],
                    });
                    i += 4;
                }
                // next 3 bytes are rgb
                else if (self.color_type == 2) {
                    try self.data.append(utils.Pixel{
                        .r = ret.items[i],
                        .g = ret.items[i + 1],
                        .b = ret.items[i + 2],
                    });
                    i += 3;
                }
            }
        }
    }
    pub fn load_PNG(self: *PNGImage, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self._allocator = allocator;
        self._file_data = utils.ByteStream{};
        try self._file_data.init_file(file_name, self._allocator);
        std.debug.print("reading png\n", .{});
        try self.read_sig();
        try self.read_chucks();
        try self.handle_chunks();
        var ret: std.ArrayList(u8) = try self.decompress();
        std.debug.print("filter type sanity {d}\n", .{ret.items[0]});
        std.debug.print("uncompressed bytes {d}\n", .{ret.items.len});
        try self.data_stream_to_rgb(&ret);
        std.debug.print("num pixels {d}\n", .{self.data.items.len});
        defer std.ArrayList(u8).deinit(ret);
    }
    fn _little_endian(_: *PNGImage, file: *const std.fs.File, num_bytes: comptime_int, i: u32) !void {
        switch (num_bytes) {
            2 => {
                try file.writer().writeInt(u16, @as(u16, @intCast(i)), std.builtin.Endian.little);
            },
            4 => {
                try file.writer().writeInt(u32, i, std.builtin.Endian.little);
            },
            else => unreachable,
        }
    }
    pub fn write_BMP(self: *PNGImage, file_name: []const u8) !void {
        // if (!self._loaded) {
        //     return JPEGImage_Error.NOT_LOADED;
        // }
        const image_file = try std.fs.cwd().createFile(file_name, .{});
        defer image_file.close();
        try image_file.writer().writeByte('B');
        try image_file.writer().writeByte('M');
        const padding_size: u32 = self.width % 4;
        const size: u32 = 14 + 12 + self.height * self.width * 3 + padding_size * self.height;

        var buffer: []u8 = try self._allocator.alloc(u8, self.height * self.width * 3 + padding_size * self.height);
        var buffer_pos = buffer[0..buffer.len];
        defer self._allocator.free(buffer);
        try self._little_endian(&image_file, 4, size);
        try self._little_endian(&image_file, 4, 0);
        try self._little_endian(&image_file, 4, 0x1A);
        try self._little_endian(&image_file, 4, 12);
        try self._little_endian(&image_file, 2, self.width);
        try self._little_endian(&image_file, 2, self.height);
        try self._little_endian(&image_file, 2, 1);
        try self._little_endian(&image_file, 2, 24);
        var i: usize = self.height - 1;
        var j: usize = 0;
        while (i >= 0) {
            while (j < self.width) {
                const pixel: *utils.Pixel = &self.data.items[i * self.width + j];
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

    pub fn deinit(self: *PNGImage) void {
        self._file_data.deinit();
        for (self._chunks.items) |*chunk| {
            chunk.deinit();
        }
        std.ArrayList(Chunk).deinit(self._chunks);
        self._allocator.free(self._idat_data);
        std.ArrayList(utils.Pixel).deinit(self.data);
    }
};

// test "BASIC" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//     var image = PNGImage{};
//     try image.load_PNG("basn6a08.png", &allocator);
//     try image.write_BMP("basn6a08.bmp");
//     image.deinit();
//     if (gpa.deinit() == .leak) {
//         std.debug.print("Leaked!\n", .{});
//     }
// }

// test "BASIC NO FILTER" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//     var image = PNGImage{};
//     try image.load_PNG("f00n2c08.png", &allocator);
//     try image.write_BMP("f00n2c08.bmp");
//     image.deinit();
//     if (gpa.deinit() == .leak) {
//         std.debug.print("Leaked!\n", .{});
//     }
// }

test "BASIC SUB FILTER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load_PNG("f01n2c08.png", &allocator);
    try image.write_BMP("f01n2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

// test "SHIELD" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator = gpa.allocator();
//     var image = PNGImage{};
//     try image.load_PNG("shield.png", &allocator);
//     try image.write_BMP("shield.bmp");
//     image.deinit();
//     if (gpa.deinit() == .leak) {
//         std.debug.print("Leaked!\n", .{});
//     }
// }
