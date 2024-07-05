//https://yasoob.me/posts/understanding-and-writing-jpeg-decoder-in-python/#jpeg-decoding
//https://www.youtube.com/watch?v=CPT4FSkFUgs&list=PLpsTn9TA_Q8VMDyOPrDKmSJYt1DLgDZU4

const std = @import("std");

const JPEG_HEADERS = enum(u8) {
    HEADER = 0xFF,
    SOI = 0xD8,
    EOI = 0xD9,
    DQT = 0xDB,
    SOF0 = 0xC0,
    SOF1 = 0xC1,
    SOF2 = 0xC2,
    SOF3 = 0xC3,
    SOF5 = 0xC5,
    SOF6 = 0xC6,
    SOF7 = 0xC7,
    SOF9 = 0xC9,
    SOF10 = 0xCA,
    SOF11 = 0xCB,
    SOF13 = 0xCD,
    SOF14 = 0xCE,
    SOF15 = 0xCF,
    APP0 = 0xE0,
    APP1 = 0xE1,
    APP2 = 0xE2,
    APP3 = 0xE3,
    APP4 = 0xE4,
    APP5 = 0xE5,
    APP6 = 0xE6,
    APP7 = 0xE7,
    APP8 = 0xE8,
    APP9 = 0xE9,
    APP10 = 0xEA,
    APP11 = 0xEB,
    APP12 = 0xEC,
    APP13 = 0xED,
    APP14 = 0xEE,
    APP15 = 0xEF,
    DRI = 0xDD,
    DHT = 0xC4,
    SOS = 0xDA,
    RST0 = 0xD0,
    RST1 = 0xD1,
    RST2 = 0xD2,
    RST3 = 0xD3,
    RST4 = 0xD4,
    RST5 = 0xD5,
    RST6 = 0xD6,
    RST7 = 0xD7,
    COM = 0xFE,
    JPG = 0xC8,
    JPG0 = 0xF0,
    JPG1 = 0xF1,
    JPG2 = 0xF2,
    JPG3 = 0xF3,
    JPG4 = 0xF4,
    JPG5 = 0xF5,
    JPG6 = 0xF6,
    JPG7 = 0xF7,
    JPG8 = 0xF8,
    JPG9 = 0xF9,
    JPG10 = 0xFA,
    JPG11 = 0xFB,
    JPG12 = 0xFC,
    JPG13 = 0xFD,
    DNL = 0xDC,
    DHP = 0xDE,
    EXP = 0xDF,
    TEM = 0x01,
    DAC = 0xCC,
};

const JPEG_ERRORS = error{
    INVALID_HEADER,
    INVALID_DQT_ID,
    INVALID_DQT,
    CMYK_NOT_SUPPORTED,
    YIQ_NOT_SUPPORTED,
    INVALID_COMPONENT_ID,
    INVALID_RESTART_MARKER,
    INVALID_HUFFMAN_ID,
    TOO_MANY_HUFFMAN_SYMBOLS,
    INVALID_HUFFMAN_LENGTH,
    DUPLICATE_COLOR_COMPONENT_ID,
    INVALID_SOS,
    INVALID_SUCCESSIVE_APPROXIMATION,
    INVALID_SPECTRAL_SELECTION,
    INVALID_EOI,
    INVALID_ARITHMETIC_CODING,
    INVALID_SOF_MARKER,
    INVALID_MARKER,
    INVALID_COMPONENT_LENGTH,
    UNINITIALIZED_TABLE,
};

const zig_zag_map: [64]u8 = [_]u8{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

const HuffmanTable = struct {
    symbols: [162]u8 = [_]u8{0} ** 162,
    offsets: [17]u8 = [_]u8{0} ** 17,
    set: bool = false,
    pub fn print(self: *const HuffmanTable) void {
        if (self.set) {
            std.debug.print("Symbols: \n", .{});
            for (0..16) |i| {
                std.debug.print("{d}: ", .{i + 1});
                for (self.offsets[i]..self.offsets[i + 1]) |j| {
                    std.debug.print("{d} ", .{self.symbols[j]});
                }
                std.debug.print("\n", .{});
            }
        }
    }
};

const QuantizationTable = struct {
    table: [64]u16 = [_]u16{0} ** 64,
    set: bool = false,
    pub fn print(self: *const QuantizationTable) void {
        for (0.., self.table) |i, item| {
            std.debug.print("{x} ", .{item});
            if (i != 0 and i % 8 == 0) {
                std.debug.print("\n", .{});
            }
        }
        std.debug.print("\n", .{});
    }
};

const ColorComponent = struct {
    horizontal_sampling_factor: u8 = 1,
    vertical_sampling_factor: u8 = 1,
    quantization_table_id: u8 = 0,
    huffman_dct_table_id: u8 = 0,
    huffman_act_table_id: u8 = 0,
    used: bool = false,
};

const Image = struct {
    data: ?std.ArrayList(u8) = null,
    _quantization_tables: [4]QuantizationTable = [_]QuantizationTable{.{}} ** 4,
    height: u32 = 0,
    width: u32 = 0,
    _frame_type: JPEG_HEADERS = JPEG_HEADERS.SOF0,
    _num_components: u8 = 0,
    _restart_interval: u16 = 0,
    _zero_based: bool = false,
    _color_components: [3]ColorComponent = [_]ColorComponent{.{}} ** 3,
    _huffman_dct_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    _huffman_act_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    _start_of_selection: u8 = 0,
    _end_of_selection: u8 = 63,
    _succcessive_approximation_high: u8 = 0,
    _succcessive_approximation_low: u8 = 0,
    _huffman_data: ?std.ArrayList(u8) = null,
    fn _read_start_of_frame(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
        std.debug.print("Reading SOF marker\n", .{});
        if (self._num_components != 0) {
            return JPEG_ERRORS.INVALID_HEADER;
        }

        const length: u16 = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        const precision: u8 = buffer[index.* + 1];
        index.* += 1;
        if (precision != 8) {
            return JPEG_ERRORS.INVALID_HEADER;
        }
        self.height = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        self.width = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        std.debug.print("width {d} height {d}\n", .{ self.width, self.height });
        if (self.height == 0 or self.width == 0) {
            return JPEG_ERRORS.INVALID_HEADER;
        }

        self._num_components = buffer[index.* + 1];
        std.debug.print("num_components {d}\n", .{self._num_components});
        index.* += 1;
        if (self._num_components == 4) {
            return JPEG_ERRORS.CMYK_NOT_SUPPORTED;
        }
        if (self._num_components == 0) {
            return JPEG_ERRORS.INVALID_HEADER;
        }
        for (0..self._num_components) |_| {
            var component_id = buffer[index.* + 1];
            index.* += 1;
            if (component_id == 0) {
                self._zero_based = true;
            }
            if (self._zero_based) {
                component_id += 1;
            }
            if (component_id == 4 or component_id == 5) {
                return JPEG_ERRORS.YIQ_NOT_SUPPORTED;
            }
            if (component_id == 0 or component_id > 3) {
                return JPEG_ERRORS.INVALID_COMPONENT_ID;
            }

            if (self._color_components[component_id - 1].used) {
                return JPEG_ERRORS.INVALID_COMPONENT_ID;
            }

            self._color_components[component_id - 1].used = true;
            const sampling_factor: u8 = buffer[index.* + 1];
            index.* += 1;
            self._color_components[component_id - 1].horizontal_sampling_factor = sampling_factor >> 4;
            self._color_components[component_id - 1].vertical_sampling_factor = sampling_factor & 0x0F;
            self._color_components[component_id - 1].quantization_table_id = buffer[index.* + 1];
            index.* += 1;
            if (self._color_components[component_id - 1].quantization_table_id > 3) {
                return JPEG_ERRORS.INVALID_COMPONENT_ID;
            }
        }
        std.debug.print("length {d} - 8 - (3 * {d})\n", .{ length, self._num_components });
        if (length - 8 - (3 * self._num_components) != 0) {
            return JPEG_ERRORS.INVALID_HEADER;
        }
    }
    fn _read_quant_table(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
        var length: i16 = (@as(i16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        length -= 2;
        index.* += 2;
        while (length > 0) {
            std.debug.print("Reading a Quant table\n", .{});
            const table_info = buffer[index.* + 1];
            index.* += 1;
            length -= 1;
            const table_id = table_info & 0x0F;

            if (table_id > 3) {
                return JPEG_ERRORS.INVALID_DQT_ID;
            }
            self._quantization_tables[table_id].set = true;
            if (table_info >> 4 != 0) {
                // 16 bit values
                for (0..64) |i| {
                    self._quantization_tables[table_id].table[zig_zag_map[i]] = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
                    index.* += 2;
                }
                length -= 128;
            } else {
                // 8 bit values
                for (0..64) |i| {
                    self._quantization_tables[table_id].table[zig_zag_map[i]] = buffer[index.* + 1];
                    index.* += 1;
                }
                length -= 64;
            }
        }
        if (length != 0) {
            return JPEG_ERRORS.INVALID_DQT;
        }
    }
    fn _read_restart_interval(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
        std.debug.print("Reading DRI marker\n", .{});
        const length: i16 = (@as(i16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        self._restart_interval = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        if (length - 4 != 0) {
            return JPEG_ERRORS.INVALID_RESTART_MARKER;
        }
        std.debug.print("Restart interval {d}", .{self._restart_interval});
    }
    fn _read_start_of_scan(self: *Image, buffer: []u8, index: *u32, allocator: *std.mem.Allocator) JPEG_ERRORS!void {
        std.debug.print("Reading SOS marker\n", .{});
        self._huffman_data = std.ArrayList(u8).init(allocator.*);
        if (self._num_components == 0) {
            return JPEG_ERRORS.INVALID_HEADER;
        }
        const length: u16 = (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        for (0..self._num_components) |i| {
            self._color_components[i].used = false;
        }
        const num_components = buffer[index.* + 1];
        index.* += 1;
        for (0..num_components) |_| {
            var component_id = buffer[index.* + 1];
            index.* += 1;
            if (self._zero_based) {
                component_id += 1;
            }
            if (component_id > self._num_components) {
                return JPEG_ERRORS.INVALID_COMPONENT_ID;
            }
            var color_component: *ColorComponent = &self._color_components[component_id - 1];
            if (color_component.used) {
                return JPEG_ERRORS.DUPLICATE_COLOR_COMPONENT_ID;
            }
            color_component.used = true;
            const huffman_table_ids = buffer[index.* + 1];
            index.* += 1;
            color_component.huffman_dct_table_id = huffman_table_ids >> 4;
            color_component.huffman_act_table_id = huffman_table_ids & 0x0F;
            if (color_component.huffman_act_table_id == 3 or color_component.huffman_dct_table_id == 3) {
                return JPEG_ERRORS.INVALID_HUFFMAN_ID;
            }
        }
        self._start_of_selection = buffer[index.* + 1];
        index.* += 1;
        self._end_of_selection = buffer[index.* + 1];
        index.* += 1;
        const succ_approx = buffer[index.* + 1];
        index.* += 1;
        self._succcessive_approximation_high = succ_approx >> 4;
        self._succcessive_approximation_low = succ_approx & 0x0F;

        if (self._start_of_selection != 0 or self._end_of_selection != 63) {
            return JPEG_ERRORS.INVALID_SPECTRAL_SELECTION;
        }

        if (self._succcessive_approximation_high != 0 or self._succcessive_approximation_low != 0) {
            return JPEG_ERRORS.INVALID_SUCCESSIVE_APPROXIMATION;
        }

        if (length - 6 - (2 * num_components) != 0) {
            return JPEG_ERRORS.INVALID_SOS;
        }
    }
    fn _read_huffman(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
        std.debug.print("Reading DHT marker\n", .{});
        var length: i16 = (@as(i16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
        index.* += 2;
        length -= 2;
        while (length > 0) {
            const table_info: u8 = buffer[index.* + 1];
            index.* += 1;
            const table_id = table_info & 0x0F;
            const act_table: bool = (table_info >> 4) != 0;

            var huff_table: *HuffmanTable = undefined;
            if (table_id > 3) {
                return JPEG_ERRORS.INVALID_HUFFMAN_ID;
            }
            if (act_table) {
                huff_table = &self._huffman_act_tables[table_id];
            } else {
                huff_table = &self._huffman_dct_tables[table_id];
            }
            huff_table.set = true;
            huff_table.offsets[0] = 0;
            var all_symbols: u8 = 0;
            for (1..17) |i| {
                std.debug.print("offset i:{d} \n", .{i});
                std.debug.print("all symbols {x} {d}\n", .{ all_symbols, buffer[index.* + 1] });
                all_symbols += buffer[index.* + 1];
                index.* += 1;
                huff_table.offsets[i] = all_symbols;
            }
            if (all_symbols > 162) {
                return JPEG_ERRORS.TOO_MANY_HUFFMAN_SYMBOLS;
            }
            for (0..all_symbols) |j| {
                huff_table.symbols[j] = buffer[index.* + 1];
                std.debug.print("symbol {d} \n", .{huff_table.symbols[j]});
                index.* += 1;
            }
            length -= 17 + all_symbols;
        }
        if (length != 0) {
            return JPEG_ERRORS.INVALID_HUFFMAN_LENGTH;
        }
    }
    fn _skippable_header(_: *Image, buffer: []u8, index: *u32) void {
        index.* += (@as(u16, buffer[index.* + 1]) << 8) + buffer[index.* + 2];
    }
    fn _read_JPEG(self: *Image, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        const image_file = try std.fs.cwd().openFile(file_name, .{});
        defer image_file.close();
        const size_limit = std.math.maxInt(u32);
        const buffer = try image_file.readToEndAlloc(allocator.*, size_limit);
        defer allocator.free(buffer);
        var current: u8 = buffer[1];
        var last: u8 = buffer[0];

        if (last == @intFromEnum(JPEG_HEADERS.HEADER) and current == @intFromEnum(JPEG_HEADERS.SOI)) {
            std.debug.print("Start of image\n", .{});
        } else {
            return JPEG_ERRORS.INVALID_HEADER;
        }
        last = buffer[2];
        current = buffer[3];
        var i: u32 = 3;
        while (i < buffer.len) {
            // Expecting header
            std.debug.print("Reading header {x} {x}\n", .{ last, current });
            if (last == @intFromEnum(JPEG_HEADERS.HEADER)) {
                if (current <= @intFromEnum(JPEG_HEADERS.APP15) and current >= @intFromEnum(JPEG_HEADERS.APP0)) {
                    std.debug.print("Application header {x} {x}\n", .{ last, current });
                    self._skippable_header(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.COM)) {
                    // comment
                    self._skippable_header(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.DQT)) {
                    std.debug.print("Reading Quant table\n", .{});
                    std.debug.print("index {d}\n", .{i});
                    try self._read_quant_table(buffer, &i);
                    for (self._quantization_tables) |table| {
                        table.print();
                    }
                } else if (current == @intFromEnum(JPEG_HEADERS.DRI)) {
                    try self._read_restart_interval(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.SOS)) {
                    try self._read_start_of_scan(buffer, &i, allocator);
                    self.print();
                    break;
                } else if (current == @intFromEnum(JPEG_HEADERS.DHT)) {
                    try self._read_huffman(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.EOI)) {
                    std.debug.print("End of image\n", .{});
                    return JPEG_ERRORS.INVALID_EOI;
                } else if (current == @intFromEnum(JPEG_HEADERS.SOF0)) {
                    self._frame_type = JPEG_HEADERS.SOF0;
                    try self._read_start_of_frame(buffer, &i);
                } else if ((current >= @intFromEnum(JPEG_HEADERS.JPG0) and current <= @intFromEnum(JPEG_HEADERS.JPG13)) or
                    current == @intFromEnum(JPEG_HEADERS.DNL) or
                    current == @intFromEnum(JPEG_HEADERS.DHP) or
                    current == @intFromEnum(JPEG_HEADERS.EXP))
                {
                    // unusued that can be skipped
                    self._skippable_header(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.DAC)) {
                    return JPEG_ERRORS.INVALID_ARITHMETIC_CODING;
                } else if (current >= @intFromEnum(JPEG_HEADERS.SOF1) and current <= @intFromEnum(JPEG_HEADERS.SOF15)) {
                    return JPEG_ERRORS.INVALID_SOF_MARKER;
                } else if (current >= @intFromEnum(JPEG_HEADERS.RST0) and current <= @intFromEnum(JPEG_HEADERS.RST7)) {
                    return JPEG_ERRORS.INVALID_HEADER;
                } else if (current == @intFromEnum(JPEG_HEADERS.TEM)) {} else if (current == @intFromEnum(JPEG_HEADERS.HEADER)) {
                    // allowed to have run of 0xFF
                    last = current;
                    i += 1;
                    current = buffer[i];
                    continue;
                } else {
                    return JPEG_ERRORS.INVALID_HEADER;
                }
                // handled valid header move to next
                last = buffer[i + 1];
                current = buffer[i + 2];
                i += 2;
            } else {
                //expected header
                return JPEG_ERRORS.INVALID_HEADER;
            }
        }
        current = buffer[i + 1];
        i += 1;
        while (i < buffer.len) {
            last = current;
            current = buffer[i + 1];
            i += 1;
            if (last == @intFromEnum(JPEG_HEADERS.HEADER)) {
                // might be a marker
                if (current == @intFromEnum(JPEG_HEADERS.EOI)) {
                    break;
                } else if (current == 0) {
                    try self._huffman_data.?.append(last);
                    current = buffer[i + 1];
                    i += 1;
                } else if (current >= @intFromEnum(JPEG_HEADERS.RST0) and current <= @intFromEnum(JPEG_HEADERS.RST7)) {
                    current = buffer[i + 1];
                    i += 1;
                } else if (current == @intFromEnum(JPEG_HEADERS.HEADER)) {
                    continue;
                } else {
                    return JPEG_ERRORS.INVALID_MARKER;
                }
            } else {
                try self._huffman_data.?.append(last);
            }
        }
        if (self._num_components != 1 and self._num_components != 3) {
            return JPEG_ERRORS.INVALID_COMPONENT_LENGTH;
        }

        for (0..self._num_components) |j| {
            if (self._quantization_tables[self._color_components[j].quantization_table_id].set == false) {
                return JPEG_ERRORS.UNINITIALIZED_TABLE;
            }
            if (self._huffman_dct_tables[self._color_components[j].huffman_dct_table_id].set == false) {
                return JPEG_ERRORS.UNINITIALIZED_TABLE;
            }
            if (self._huffman_act_tables[self._color_components[j].huffman_act_table_id].set == false) {
                return JPEG_ERRORS.UNINITIALIZED_TABLE;
            }
        }
        std.debug.print("Huffman data length: {d}", .{self._huffman_data.?.items.len});
    }
    pub fn clean_up(self: *Image) void {
        std.ArrayList(u8).deinit(self.data.?);
        std.ArrayList(u8).deinit(self._huffman_data.?);
    }
    pub fn print(self: *Image) void {
        std.debug.print("DC Tables:\n", .{});
        for (0.., self._huffman_dct_tables) |i, table| {
            std.debug.print("Table ID: {d}\n", .{i});
            table.print();
        }
        std.debug.print("AC Tables:\n", .{});
        for (0.., self._huffman_act_tables) |i, table| {
            std.debug.print("Table ID: {d}\n", .{i});
            table.print();
        }
        if (self.data) |data| {
            for (data.items) |item| {
                std.debug.print("{x} ", .{item});
            }
            std.debug.print("\n", .{});
        }
    }
    pub fn load_JPEG(self: *Image, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        try self._read_JPEG(file_name, allocator);
        self.data = std.ArrayList(u8).init(allocator.*);
    }
};

test "JPEG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image{};
    try image.load_JPEG("cat.jpg", &allocator);
    image.print();
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}
