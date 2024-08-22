//https://www.w3.org/TR/PNG-Structure.html
//https://iter.ca/post/png/
//https://pyokagan.name/blog/2019-10-18-zlibinflate/
//https://datatracker.ietf.org/doc/html/rfc1951
//https://github.com/madler/zlib/blob/master/contrib/puff/puff.c
//http://www.schaik.com/pngsuite/
//https://www.w3.org/TR/2024/CRD-png-3-20240718/#13Progressive-display
const std = @import("std");
const utils = @import("utils.zig");

pub const Error = error{
    INVALID_SIGNATURE,
    INVALID_CRC,
    INVALID_COMPRESSION_METHOD,
    INVALID_WINDOW_SIZE,
    INVALID_DEFLATE_CHECKSUM,
    INVALID_PRESET_DICT,
    INVALID_BTYPE,
    INVALID_HUFFMAN_SYMBOL,
    INVALID_FILTER,
    INVALID_COLOR_TYPE,
    NOT_LOADED,
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
    data: []u8 = undefined,
    allocator: std.mem.Allocator = undefined,
    length: u32 = undefined,
    chunk_type: []u8 = undefined,
    chunk_data: []u8 = undefined,
    crc_check: u32 = undefined,
    pub fn init(self: *Chunk, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
    }

    pub fn read_chunk(self: *Chunk, file_data: *utils.ByteStream) (std.mem.Allocator.Error || utils.ByteStream.Error)!void {
        self.length = (@as(u32, @intCast(try file_data.readByte())) << 24) | (@as(u32, @intCast(try file_data.readByte())) << 16) | (@as(u32, @intCast(try file_data.readByte())) << 8) | (@as(u32, @intCast(try file_data.readByte())));
        std.debug.print("length {d}\n", .{self.length});
        self.data = try self.allocator.alloc(u8, self.length + 4);
        self.data[0] = try file_data.readByte();
        self.data[1] = try file_data.readByte();
        self.data[2] = try file_data.readByte();
        self.data[3] = try file_data.readByte();
        self.chunk_type = self.data[0..4];
        std.debug.print("chunk type {s}\n", .{self.chunk_type});
        for (4..self.data.len) |i| {
            self.data[i] = try file_data.readByte();
            //std.debug.print("{x} ", .{self._data[i]});
        }
        //std.debug.print("\n", .{});
        self.chunk_data = self.data[4..self.data.len];
        self.crc_check = (@as(u32, @intCast(try file_data.readByte())) << 24) | (@as(u32, @intCast(try file_data.readByte())) << 16) | (@as(u32, @intCast(try file_data.readByte())) << 8) | (@as(u32, @intCast(try file_data.readByte())));
        std.debug.print("crc {d}\n", .{self.crc_check});
    }
    pub fn verify_crc(self: *Chunk) Error!void {
        const calced_crc = calc_crc(self.data, @as(u32, @intCast(self.data.len)));
        std.debug.print("calculated crc {d}\n", .{calced_crc});
        if (calced_crc != self.crc_check) {
            return Error.INVALID_CRC;
        }
    }
    pub fn deinit(self: *Chunk) void {
        self.allocator.free(self.data);
    }
};

const LengthExtraBits = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
const LengthBase = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
const DistanceExtraBits = [_]u16{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
const DistanceBase = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
const CodeLengthCodesOrder = [_]u16{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
const StartingRow = [_]u8{ 0, 0, 4, 0, 2, 0, 1 };
const StartingCol = [_]u8{ 0, 4, 0, 2, 0, 1, 0 };
const RowIncrement = [_]u8{ 8, 8, 8, 4, 4, 2, 2 };
const ColIncrement = [_]u8{ 8, 8, 4, 4, 2, 2, 1 };
const BlockHeight = [_]u8{ 8, 8, 4, 4, 2, 2, 1 };
const BlockWidth = [_]u8{ 8, 4, 4, 2, 2, 1, 1 };

pub const PNGImage = struct {
    file_data: utils.ByteStream = undefined,
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    chunks: std.ArrayList(Chunk) = undefined,
    data: std.ArrayList(utils.Pixel(u8)) = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    bit_depth: u8 = undefined,
    color_type: u8 = undefined,
    compression_method: u8 = undefined,
    filter_method: u8 = undefined,
    interlace_method: u8 = undefined,
    gamma: f32 = undefined,
    plte_data: ?[]u8 = null,
    idat_data: []u8 = undefined,
    idat_data_len: usize = 0,

    fn read_chucks(self: *PNGImage) (utils.ByteStream.Error || Error || std.mem.Allocator.Error)!void {
        self.chunks = std.ArrayList(Chunk).init(self.allocator);
        while (self.file_data.getPos() != self.file_data.getEndPos()) {
            var chunk: Chunk = Chunk{};
            chunk.init(self.allocator);
            try chunk.read_chunk(&self.file_data);
            try chunk.verify_crc();
            try self.chunks.append(chunk);
            if (std.mem.eql(u8, chunk.chunk_type, "IDAT")) {
                self.idat_data_len += chunk.chunk_data.len;
            } else if (std.mem.eql(u8, chunk.chunk_type, "IEND")) {
                break;
            }
        }
        std.debug.print("all chunks read\n", .{});
    }
    fn handle_chunks(self: *PNGImage) std.mem.Allocator.Error!void {
        self.idat_data = try self.allocator.alloc(u8, self.idat_data_len);
        var index: usize = 0;
        for (self.chunks.items) |*chunk| {
            if (std.mem.eql(u8, chunk.chunk_type, "IHDR")) {
                self.handle_IHDR(chunk);
            } else if (std.mem.eql(u8, chunk.chunk_type, "PLTE")) {
                self.plte_data = chunk.chunk_data;
            } else if (std.mem.eql(u8, chunk.chunk_type, "IDAT")) {
                self.handle_IDAT(chunk, &index);
            } else if (std.mem.eql(u8, chunk.chunk_type, "gAMA")) {
                var gamma_int: u32 = chunk.chunk_data[0];
                gamma_int = (gamma_int << 8) | chunk.chunk_data[1];
                gamma_int = (gamma_int << 8) | chunk.chunk_data[2];
                gamma_int = (gamma_int << 8) | chunk.chunk_data[3];
                self.gamma = @as(f32, @floatFromInt(gamma_int)) / 100000.0;
                std.debug.print("gamma {d}\n", .{self.gamma});
            }
        }
        std.debug.print("index = {d}, len = {d}\n", .{ index, self.idat_data_len });
    }
    fn handle_IDAT(self: *PNGImage, chunk: *Chunk, index: *usize) void {
        for (chunk.chunk_data) |data| {
            self.idat_data[index.*] = data;
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
    fn read_sig(self: *PNGImage) (utils.ByteStream.Error || Error)!void {
        std.debug.print("reading signature\n", .{});
        const signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
        for (signature) |sig| {
            const current = try self.file_data.readByte();
            if (current != sig) {
                return Error.INVALID_SIGNATURE;
            }
        }
    }
    fn decompress(self: *PNGImage) (utils.Max_error || std.mem.Allocator.Error || utils.ByteStream.Error || Error || utils.BitReader.Error)!std.ArrayList(u8) {
        var bit_reader: utils.BitReader = try utils.BitReader.init(.{ .data = self.idat_data, .reverse_bit_order = true, .little_endian = true });
        std.debug.print("idat data len {d}\n", .{self.idat_data.len});
        defer bit_reader.deinit();
        const CMF = try bit_reader.read_byte();
        const CM = CMF & 0xF;
        std.debug.print("compression method {d}\n", .{CM});
        if (CM != 8) {
            return Error.INVALID_COMPRESSION_METHOD;
        }
        const CINFO = (CMF >> 4) & 0xF;
        if (CINFO > 7) {
            return Error.INVALID_WINDOW_SIZE;
        }
        const FLG = try bit_reader.read_byte();
        if ((@as(u32, @intCast(CMF)) * 256 + @as(u32, @intCast(FLG))) % 0x1F != 0) {
            return Error.INVALID_DEFLATE_CHECKSUM;
        }
        const FDICT = (FLG >> 5) & 1;
        if (FDICT != 0) {
            return Error.INVALID_PRESET_DICT;
        }
        const ret: std.ArrayList(u8) = try self.inflate(&bit_reader);
        var ADLER32: u32 = try bit_reader.read_byte();
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 8;
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 16;
        ADLER32 |= @as(u32, @intCast(try bit_reader.read_byte())) << 24;
        return ret;
    }
    fn inflate(self: *PNGImage, bit_reader: *utils.BitReader) (utils.Max_error || std.mem.Allocator.Error || utils.BitReader.Error || utils.ByteStream.Error || Error)!std.ArrayList(u8) {
        var BFINAL: u32 = 0;
        var ret: std.ArrayList(u8) = std.ArrayList(u8).init(self.allocator);
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
                return Error.INVALID_BTYPE;
            }
        }
        return ret;
    }
    fn decode_symbol(_: *PNGImage, bit_reader: *utils.BitReader, tree: *utils.HuffmanTree(u16)) !u16 {
        var node = tree.root;
        while (node.left != null and node.right != null) {
            const bit = try bit_reader.read_bit();
            node = if (bit != 0) node.right.?.* else node.left.?.*;
        }
        return node.symbol;
    }
    fn inflate_block_no_compression(_: *PNGImage, bit_reader: *utils.BitReader, ret: *std.ArrayList(u8)) (utils.Max_error || std.mem.Allocator.Error || utils.BitReader.Error || utils.ByteStream.Error || Error)!void {
        std.debug.print("inflate no compression\n", .{});
        const LEN = try bit_reader.read_word();
        std.debug.print("LEN {d}\n", .{LEN});
        const NLEN = try bit_reader.read_word();
        std.debug.print("NLEN {d}\n", .{NLEN});
        for (0..LEN) |_| {
            try ret.append(try bit_reader.read_byte());
        }
    }
    fn bit_length_list_to_tree(self: *PNGImage, bit_length_list: []u16, alphabet: []u16) !*utils.HuffmanTree(u16) {
        const MAX_BITS = try utils.max_array(u16, bit_length_list);
        var bl_count: []u16 = try self.allocator.alloc(u16, MAX_BITS + 1);
        defer self.allocator.free(bl_count);
        for (0..bl_count.len) |i| {
            var sum: u16 = 0;
            for (bit_length_list) |j| {
                if (j == @as(u16, @intCast(i)) and i != 0) {
                    sum += 1;
                }
            }
            bl_count[i] = sum;
        }
        var next_code: std.ArrayList(u16) = std.ArrayList(u16).init(self.allocator);
        defer std.ArrayList(u16).deinit(next_code);
        try next_code.append(0);
        try next_code.append(0);
        for (2..MAX_BITS + 1) |bits| {
            try next_code.append((next_code.items[bits - 1] + bl_count[bits - 1]) << 1);
        }
        var tree: *utils.HuffmanTree(u16) = try self.allocator.create(utils.HuffmanTree(u16));
        tree.* = try utils.HuffmanTree(u16).init(self.allocator);
        const min_len = @min(alphabet.len, bit_length_list.len);
        for (0..min_len) |i| {
            if (bit_length_list[i] != 0) {
                try tree.insert(next_code.items[bit_length_list[i]], bit_length_list[i], alphabet[i]);
                next_code.items[bit_length_list[i]] += 1;
            }
        }
        return tree;
    }
    fn inflate_block_data(self: *PNGImage, bit_reader: *utils.BitReader, literal_length_tree: *utils.HuffmanTree(u16), distance_tree: *utils.HuffmanTree(u16), ret: *std.ArrayList(u8)) !void {
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
    fn decode_trees(self: *PNGImage, bit_reader: *utils.BitReader) !struct { literal_length_tree: *utils.HuffmanTree(u16), distance_tree: *utils.HuffmanTree(u16) } {
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
        var bit_length_list: std.ArrayList(u16) = std.ArrayList(u16).init(self.allocator);
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
                return Error.INVALID_HUFFMAN_SYMBOL;
            }
        }
        code_length_tree.deinit();
        self.allocator.destroy(code_length_tree);
        var literal_length_alphabet: [288]u16 = [_]u16{0} ** 288;
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
    fn inflate_block_fixed(self: *PNGImage, bit_reader: *utils.BitReader, ret: *std.ArrayList(u8)) !void {
        std.debug.print("inflate fixed \n", .{});
        var bit_length_list: std.ArrayList(u16) = std.ArrayList(u16).init(self.allocator);
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
        var literal_length_alphabet: [288]u16 = [_]u16{0} ** 288;
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
        self.allocator.destroy(literal_length_tree);
        distance_tree.deinit();
        self.allocator.destroy(distance_tree);
    }
    fn inflate_block_dynamic(self: *PNGImage, bit_reader: *utils.BitReader, ret: *std.ArrayList(u8)) !void {
        std.debug.print("inflate dynamic \n", .{});
        var trees = try self.decode_trees(bit_reader);
        try self.inflate_block_data(bit_reader, trees.literal_length_tree, trees.distance_tree, ret);
        trees.literal_length_tree.deinit();
        self.allocator.destroy(trees.literal_length_tree);
        trees.distance_tree.deinit();
        self.allocator.destroy(trees.distance_tree);
    }
    fn paeth_predictor(_: *PNGImage, a: u8, b: u8, c: u8) u8 {
        //std.debug.print("a {d}, b {d}, c {d}\n", .{ a, b, c });
        var p: i16 = @as(i16, @intCast(b)) - @as(i16, @intCast(c));
        p += a;
        const pa = @as(u8, @truncate(@abs(@as(i16, @intCast(p)) - @as(i16, @intCast(a)))));
        const pb = @as(u8, @truncate(@abs(@as(i16, @intCast(p)) - @as(i16, @intCast(b)))));
        //std.debug.print("p {d} c {d}\n", .{ p, c });
        const pc = @as(u8, @truncate(@abs(@as(i16, @intCast(p)) - @as(i16, @intCast(c)))));
        if (pa <= pb and pa <= pc) {
            return a;
        } else if (pb <= pc) {
            return b;
        }
        return c;
    }
    fn filter_scanline(self: *PNGImage, filter_type: u8, scanline: []u8, previous_scanline: ?[]u8, num_bytes_per_pixel: usize) void {
        if (filter_type == 0) return;
        // sub
        if (filter_type == 1) {
            for (0..scanline.len) |i| {
                if (i >= num_bytes_per_pixel) {
                    scanline[i] = @as(u8, @intCast((@as(u16, @intCast(scanline[i])) + @as(u16, @intCast(scanline[i - num_bytes_per_pixel]))) % 256));
                }
            }
        }
        // up
        else if (filter_type == 2) {
            for (0..scanline.len) |i| {
                const prior = if (previous_scanline != null) previous_scanline.?[i] else 0;
                scanline[i] = @as(u8, @intCast((@as(u16, @intCast(scanline[i])) + @as(u16, @intCast(prior))) % 256));
            }
        }
        // avg
        else if (filter_type == 3) {
            for (0..scanline.len) |i| {
                const left = if (i >= num_bytes_per_pixel) scanline[i - num_bytes_per_pixel] else 0;
                const prior = if (previous_scanline != null) previous_scanline.?[i] else 0;
                scanline[i] = @as(u8, @intCast((@as(u16, @intCast(scanline[i])) + (@as(u16, @intCast(left)) + @as(u16, @intCast(prior))) / 2) % 256));
            }
        }
        // paeth
        else if (filter_type == 4) {
            for (0..scanline.len) |i| {
                const left = if (i >= num_bytes_per_pixel) scanline[i - num_bytes_per_pixel] else 0;
                const prior = if (previous_scanline != null) previous_scanline.?[i] else 0;
                const prior_left = if (i >= num_bytes_per_pixel and previous_scanline != null) previous_scanline.?[i - num_bytes_per_pixel] else 0;
                //std.debug.print("left {d}, prior {d}, prior_left {d}\n", .{ left, prior, prior_left });
                scanline[i] = @as(u8, @intCast((@as(u16, @intCast(scanline[i])) + @as(u16, @intCast(self.paeth_predictor(left, prior, prior_left)))) % 256));
            }
        }
    }
    fn add_filtered_pixel(self: *PNGImage, ret: *std.ArrayList(u8), buffer_index: *usize, bit_index: *u3, data_index: usize, num_bytes_per_pixel: usize) (std.mem.Allocator.Error || Error)!void {
        switch (self.color_type) {
            0 => {
                switch (self.bit_depth) {
                    1 => {
                        const rgb: u8 = if (((ret.items[buffer_index.*] >> bit_index.*) & 1) == 1) 255 else 0;
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = rgb,
                            .g = rgb,
                            .b = rgb,
                        };
                        if (bit_index.* == 0) {
                            bit_index.* = 7;
                            buffer_index.* += num_bytes_per_pixel;
                        } else {
                            bit_index.* -= 1;
                        }
                    },
                    2 => {
                        const bits: u2 = (@as(u2, @truncate((ret.items[buffer_index.*] >> bit_index.*) & 1)) << 1) | (@as(u2, @truncate(ret.items[buffer_index.*] >> bit_index.* - 1)) & 1);
                        const rgb: u8 = @as(u8, @intFromFloat(255.0 * (@as(f32, @floatFromInt(bits)) / 3.0)));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = rgb,
                            .g = rgb,
                            .b = rgb,
                        };
                        if (bit_index.* == 1) {
                            bit_index.* = 7;
                            buffer_index.* += num_bytes_per_pixel;
                        } else {
                            bit_index.* -= 2;
                        }
                    },
                    4 => {
                        const bits: u4 = (@as(u4, @truncate((ret.items[buffer_index.*] >> bit_index.*) & 1)) << 3) | (@as(u4, @truncate((ret.items[buffer_index.*] >> bit_index.* - 1) & 1)) << 2) | (@as(u4, @truncate((ret.items[buffer_index.*] >> bit_index.* - 2) & 1)) << 1) | (@as(u4, @truncate(ret.items[buffer_index.*] >> bit_index.* - 3)) & 1);
                        const rgb: u8 = @as(u8, @intFromFloat(255.0 * (@as(f32, @floatFromInt(bits)) / 15.0)));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = rgb,
                            .g = rgb,
                            .b = rgb,
                        };
                        if (bit_index.* == 3) {
                            bit_index.* = 7;
                            buffer_index.* += num_bytes_per_pixel;
                        } else {
                            bit_index.* -= 4;
                        }
                    },
                    8 => {
                        const rgb: u8 = ret.items[buffer_index.*];
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = rgb,
                            .g = rgb,
                            .b = rgb,
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    16 => {
                        const rgb: u16 = (@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1];
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb)) * (255.0 / 65535.0))),
                            .g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb)) * (255.0 / 65535.0))),
                            .b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb)) * (255.0 / 65535.0))),
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    else => unreachable,
                }
            },
            2 => {
                switch (self.bit_depth) {
                    8 => {
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = ret.items[buffer_index.*],
                            .g = ret.items[buffer_index.* + 1],
                            .b = ret.items[buffer_index.* + 2],
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    16 => {
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1])) * (255.0 / 65535.0))),
                            .g = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 2])) << 8) | ret.items[buffer_index.* + 3])) * (255.0 / 65535.0))),
                            .b = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 4])) << 8) | ret.items[buffer_index.* + 5])) * (255.0 / 65535.0))),
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    else => unreachable,
                }
            },
            3 => {
                switch (self.bit_depth) {
                    1 => {},
                    2 => {},
                    4 => {},
                    8 => {},
                    else => unreachable,
                }
            },
            4 => {
                switch (self.bit_depth) {
                    8 => {
                        // const alpha = @as(f32, @floatFromInt(ret.items[buffer_index.* + 1]));
                        // const max_pixel = std.math.pow(f32, 2, @as(f32, @floatFromInt(self.bit_depth))) - 1;
                        // const bkgd = max_pixel;
                        // var rgb: u8 = if (alpha == 0) 0 else @as(u8, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt(ret.items[buffer_index.*]))));
                        // rgb += @as(u8, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = ret.items[buffer_index.*],
                            .g = ret.items[buffer_index.*],
                            .b = ret.items[buffer_index.*],
                            .a = ret.items[buffer_index.* + 1],
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    16 => {
                        // next 3 bytes are rgb followed by alpha
                        const alpha = @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 2])) << 8) | ret.items[buffer_index.* + 3]));
                        // const max_pixel = std.math.pow(f32, 2, @as(f32, @floatFromInt(self.bit_depth))) - 1;
                        // const bkgd = max_pixel;
                        // var rgb: u16 = if (alpha == 0) 0 else @as(u16, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1]))));
                        // rgb += @as(u16, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1])) * (255.0 / 65535.0))),
                            .g = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1])) * (255.0 / 65535.0))),
                            .b = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1])) * (255.0 / 65535.0))),
                            .a = @as(u8, @intFromFloat(alpha * (255.0 / 65535.0))),
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    else => unreachable,
                }
            },
            6 => {
                switch (self.bit_depth) {
                    8 => {
                        // next 3 bytes are rgb followed by alpha
                        //const alpha = @as(f32, @floatFromInt(ret.items[buffer_index.* + 3]));
                        // const max_pixel = std.math.pow(f32, 2, @as(f32, @floatFromInt(self.bit_depth))) - 1;
                        // const bkgd = max_pixel;
                        // //std.debug.print("alpha {d} r {d} g {d} b {d} max {d}\n", .{ alpha, ret.items[i], ret.items[i + 1], ret.items[i + 2], max_pixel });
                        // var r: u8 = if (alpha == 0) 0 else @as(u8, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt(ret.items[buffer_index.*]))));
                        // var g: u8 = if (alpha == 0) 0 else @as(u8, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt(ret.items[buffer_index.* + 1]))));
                        // var b: u8 = if (alpha == 0) 0 else @as(u8, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt(ret.items[buffer_index.* + 2]))));
                        // //std.debug.print("more red {d} {d}\n", .{ r, @as(u8, @intFromFloat((1 - (alpha / max_pixel)) * bkgd)) });
                        // r += @as(u8, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        // g += @as(u8, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        // b += @as(u8, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = ret.items[buffer_index.*],
                            .g = ret.items[buffer_index.* + 1],
                            .b = ret.items[buffer_index.* + 2],
                            .a = ret.items[buffer_index.* + 3],
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    16 => {
                        //TODO figure out scuffed corner in 16 bit alpha images
                        // next 3 bytes are rgb followed by alpha
                        const alpha = @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 6])) << 8) | ret.items[buffer_index.* + 7]));
                        // const max_pixel = std.math.pow(f32, 2, @as(f32, @floatFromInt(self.bit_depth))) - 1;
                        // const bkgd = max_pixel;
                        // //std.debug.print("alpha {d} r {d} g {d} b {d} max {d}\n", .{ alpha, ret.items[i], ret.items[i + 1], ret.items[i + 2], max_pixel });
                        // var r: u16 = if (alpha == 0) 0 else @as(u16, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1]))));
                        // var g: u16 = if (alpha == 0) 0 else @as(u16, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 2])) << 8) | ret.items[buffer_index.* + 3]))));
                        // var b: u16 = if (alpha == 0) 0 else @as(u16, @intFromFloat((alpha / max_pixel) * @as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 4])) << 8) | ret.items[buffer_index.* + 5]))));
                        // //std.debug.print("more red {d} {d}\n", .{ r, @as(u16, @intFromFloat((1 - (alpha / max_pixel)) * bkgd)) });
                        // r += @as(u16, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        // g += @as(u16, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        // b += @as(u16, @intFromFloat((1 - (alpha / max_pixel)) * bkgd));
                        self.data.items[data_index] = utils.Pixel(u8){
                            .r = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.*])) << 8) | ret.items[buffer_index.* + 1])) * (255.0 / 65535.0))),
                            .g = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 2])) << 8) | ret.items[buffer_index.* + 3])) * (255.0 / 65535.0))),
                            .b = @as(u8, @intFromFloat(@as(f32, @floatFromInt((@as(u16, @intCast(ret.items[buffer_index.* + 4])) << 8) | ret.items[buffer_index.* + 5])) * (255.0 / 65535.0))),
                            .a = @as(u8, @intFromFloat(alpha * (255.0 / 65535.0))),
                        };
                        buffer_index.* += num_bytes_per_pixel;
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
        }
    }
    fn data_stream_to_rgb(self: *PNGImage, ret: *std.ArrayList(u8)) (std.mem.Allocator.Error || Error)!void {
        self.data = try std.ArrayList(utils.Pixel(u8)).initCapacity(self.allocator, self.height * self.width);
        self.data.expandToCapacity();
        var buffer_index: usize = 0;
        var previous_index: usize = 0;
        var num_bytes_per_pixel: usize = undefined;
        switch (self.color_type) {
            0 => num_bytes_per_pixel = @as(usize, @intFromFloat(@ceil(@as(f32, @floatFromInt(self.bit_depth)) / 8.0))),
            2 => num_bytes_per_pixel = 3 * (self.bit_depth / 8),
            3 => num_bytes_per_pixel = 1,
            4 => num_bytes_per_pixel = 2 * (self.bit_depth / 8),
            6 => num_bytes_per_pixel = 4 * (self.bit_depth / 8),
            else => return Error.INVALID_COLOR_TYPE,
        }
        var scanline_width: usize = if (self.bit_depth >= 8) self.width * num_bytes_per_pixel else @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.width)) * ((1.0 * @as(f32, @floatFromInt(self.bit_depth))) / 8.0)));
        std.debug.print("bytes per pixel {d}\n", .{num_bytes_per_pixel});
        buffer_index = 0;
        var data_index: usize = 0;
        if (self.interlace_method == 0) {
            for (0..self.height) |_| {
                const filter_type: u8 = ret.items[buffer_index];
                //std.debug.print("filter type {d} at position {d}\n", .{ filter_type, i });
                buffer_index += 1;
                const previous_scanline: ?[]u8 = if (previous_index > 0) ret.items[previous_index .. scanline_width + previous_index] else null;
                previous_index = buffer_index;
                self.filter_scanline(filter_type, ret.items[buffer_index .. scanline_width + buffer_index], previous_scanline, num_bytes_per_pixel);
                var bit_index: u3 = 7;
                for (0..self.width) |_| {
                    try self.add_filtered_pixel(ret, &buffer_index, &bit_index, data_index, num_bytes_per_pixel);
                    data_index += 1;
                }
            }
        }
        //TODO improve interlacing support
        // adam7
        else if (self.interlace_method == 1) {
            var pass: u3 = 0;
            while (pass < 7) : (pass += 1) {
                var row: usize = StartingRow[pass];
                previous_index = 0;
                while (row < self.height) : (row += RowIncrement[pass]) {
                    var col: usize = StartingCol[pass];
                    var bit_index: u3 = 7;
                    const filter_type: u8 = ret.items[buffer_index];
                    //std.debug.print("filter type {d} at position {d}\n", .{ filter_type, i });
                    buffer_index += 1;
                    scanline_width = if (self.bit_depth >= 8) ((self.width - col) / ColIncrement[pass]) * num_bytes_per_pixel else @as(usize, @intFromFloat(@as(f32, @floatFromInt(((self.width - col) / ColIncrement[pass]))) * ((1.0 * @as(f32, @floatFromInt(self.bit_depth))) / 8.0)));
                    const previous_scanline: ?[]u8 = if (previous_index > 0) ret.items[previous_index .. scanline_width + previous_index] else null;
                    previous_index = buffer_index;
                    self.filter_scanline(filter_type, ret.items[buffer_index .. scanline_width + buffer_index], previous_scanline, num_bytes_per_pixel);
                    while (col < self.width) : (col += ColIncrement[pass]) {
                        try self.add_filtered_pixel(ret, &buffer_index, &bit_index, ((row * self.width) + col), num_bytes_per_pixel);
                    }
                }
            }
        }
        std.debug.print("index {d}\n", .{buffer_index});
    }
    pub fn convert_grayscale(self: *PNGImage) !void {
        if (self.loaded) {
            for (0..self.data.items.len) |i| {
                const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].r)) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].g)) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.items[i].b)) * 0.1140));
                self.data.items[i].r = gray;
                self.data.items[i].g = gray;
                self.data.items[i].b = gray;
            }
        } else {
            return Error.NOT_LOADED;
        }
    }
    pub fn load(self: *PNGImage, file_name: []const u8, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.file_data = try utils.ByteStream.init(.{ .file_name = file_name, .allocator = self.allocator });
        std.debug.print("reading png\n", .{});
        try self.read_sig();
        try self.read_chucks();
        try self.handle_chunks();
        var ret: std.ArrayList(u8) = try self.decompress();
        std.debug.print("uncompressed bytes {d}\n", .{ret.items.len});
        try self.data_stream_to_rgb(&ret);
        std.debug.print("num pixels {d}\n", .{self.data.items.len});
        defer std.ArrayList(u8).deinit(ret);
        self.loaded = true;
    }

    pub fn get(self: *PNGImage, x: usize, y: usize) *utils.Pixel(u8) {
        return &self.data.items[y * self.width + x];
    }

    pub fn image_core(self: *PNGImage) utils.ImageCore {
        return utils.ImageCore.init(self.allocator, self.width, self.height, self.data.items);
    }

    pub fn write_BMP(self: *PNGImage, file_name: []const u8) !void {
        if (!self.loaded) {
            return Error.NOT_LOADED;
        }
        try self.image_core().write_BMP(file_name);
    }

    pub fn deinit(self: *PNGImage) void {
        self.file_data.deinit();
        for (self.chunks.items) |*chunk| {
            chunk.deinit();
        }
        std.ArrayList(Chunk).deinit(self.chunks);
        self.allocator.free(self.idat_data);
        std.ArrayList(utils.Pixel(u8)).deinit(self.data);
    }
};

test "BASIC 8" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn2c08.png", allocator);
    try image.write_BMP("basn2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC 16" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn2c16.png", allocator);
    try image.write_BMP("basn2c16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC NO FILTER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/filtering/f00n2c08.png", allocator);
    try image.write_BMP("f00n2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC SUB FILTER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/filtering/f01n2c08.png", allocator);
    try image.write_BMP("f01n2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC UP FILTER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/filtering/f02n2c08.png", allocator);
    try image.write_BMP("f02n2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC AVG FILTER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/filtering/f03n2c08.png", allocator);
    try image.write_BMP("f03n2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC 8 ALPHA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn6a08.png", allocator);
    try image.write_BMP("basn6a08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BASIC 16 ALPHA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn6a16.png", allocator);
    try image.write_BMP("basn6a16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn0g01.png", allocator);
    try image.write_BMP("basn0g01.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn0g02.png", allocator);
    try image.write_BMP("basn0g02.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 4" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn0g04.png", allocator);
    try image.write_BMP("basn0g04.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 8" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn0g08.png", allocator);
    try image.write_BMP("basn0g08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 16" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn0g16.png", allocator);
    try image.write_BMP("basn0g16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 8 ALPHA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn4a08.png", allocator);
    try image.write_BMP("basn4a08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GRAY 16 ALPHA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/basic/basn4a16.png", allocator);
    try image.write_BMP("basn4a16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "PALETTE 8 GRAY" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/palette/ps2n2c16.png", allocator);
    try image.write_BMP("ps2n2c16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi0g01.png", allocator);
    try image.write_BMP("basi0g01.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW 2 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi0g02.png", allocator);
    try image.write_BMP("basi0g02.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW 4 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi0g04.png", allocator);
    try image.write_BMP("basi0g04.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW 8 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi0g08.png", allocator);
    try image.write_BMP("basi0g08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "BW 16 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi0g16.png", allocator);
    try image.write_BMP("basi0g16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "COLOR 8 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi2c08.png", allocator);
    try image.write_BMP("basi2c08.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "COLOR 16 INTERLACE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = PNGImage{};
    try image.load("tests/png/interlacing/basi2c16.png", allocator);
    try image.write_BMP("basi2c16.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
