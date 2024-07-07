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

const IDCT_SCALING_FACTORS = struct {
    const m0: f32 = 2.0 * std.math.cos(1 / 16 * 2 * std.math.pi);
    const m1: f32 = 2.0 * std.math.cos(2 / 16 * 2 * std.math.pi);
    const m5: f32 = 2.0 * std.math.cos(3 / 16 * 2 * std.math.pi);
    const m2: f32 = 2.0 * std.math.cos(1 / 16 * 2 * std.math.pi) - 2.0 * std.math.cos(3 / 16 * 2 * std.math.pi);
    const m4: f32 = 2.0 * std.math.cos(1 / 16 * 2 * std.math.pi) + 2.0 * std.math.cos(3 / 16 * 2 * std.math.pi);
    const s0: f32 = std.math.cos(0.0 / 16.0 * std.math.pi) / std.math.sqrt(8.0);
    const s1: f32 = std.math.cos(1.0 / 16.0 * std.math.pi) / 2.0;
    const s2: f32 = std.math.cos(2.0 / 16.0 * std.math.pi) / 2.0;
    const s3: f32 = std.math.cos(3.0 / 16.0 * std.math.pi) / 2.0;
    const s4: f32 = std.math.cos(4.0 / 16.0 * std.math.pi) / 2.0;
    const s5: f32 = std.math.cos(5.0 / 16.0 * std.math.pi) / 2.0;
    const s6: f32 = std.math.cos(6.0 / 16.0 * std.math.pi) / 2.0;
    const s7: f32 = std.math.cos(7.0 / 16.0 * std.math.pi) / 2.0;
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
    HUFFMAN_DECODING,
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
    INVALID_SAMPLING_FACTOR,
};

const IMAGE_ERRORS = error{
    NOT_LOADED,
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
    codes: [162]u32 = [_]u32{0} ** 162,
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

const Pixel = struct {
    r: u8,
    g: u8,
    b: u8,
};

const ColorComponent = struct {
    horizontal_sampling_factor: u8 = 1,
    vertical_sampling_factor: u8 = 1,
    quantization_table_id: u8 = 0,
    huffman_dct_table_id: u8 = 0,
    huffman_act_table_id: u8 = 0,
    used: bool = false,
};

const MCU = struct {
    y: [64]i32 = [_]i32{0} ** 64,
    r: []i32 = undefined,
    cb: [64]i32 = [_]i32{0} ** 64,
    g: []i32 = undefined,
    cr: [64]i32 = [_]i32{0} ** 64,
    b: []i32 = undefined,
    pub fn init(self: *MCU) void {
        self.r = &self.y;
        self.g = &self.cb;
        self.b = &self.cr;
    }
    pub fn get(self: *MCU, index: usize) *[64]i32 {
        switch (index) {
            0 => return &self.y,
            1 => return &self.cb,
            2 => return &self.cr,
            else => unreachable,
        }
    }
};

const BITREADER_ERRORS = error{
    INVALID_READ,
};

const BitReader = struct {
    next_byte: u32 = 0,
    next_bit: u32 = 0,
    data: *std.ArrayList(u8),
    pub fn read_bit(self: *BitReader) BITREADER_ERRORS!u32 {
        if (self.next_byte >= self.data.items.len) {
            return BITREADER_ERRORS.INVALID_READ;
        }
        const bit: u32 = (self.data.items[self.next_byte] >> @as(u3, @intCast(7 - self.next_bit))) & 1;
        self.next_bit += 1;
        if (self.next_bit == 8) {
            self.next_bit = 0;
            self.next_byte += 1;
        }
        return bit;
    }
    pub fn read_bits(self: *BitReader, length: u32) BITREADER_ERRORS!u32 {
        var bits: u32 = 0;
        for (0..length) |_| {
            const bit = try self.read_bit();
            bits = (bits << 1) | bit;
        }
        return bits;
    }
    pub fn align_reader(self: *BitReader) void {
        if (self.next_byte >= self.data.items.len) {
            return;
        }
        if (self.next_bit != 0) {
            self.next_bit = 0;
            self.next_byte += 1;
        }
    }
};

const Image = struct {
    data: ?std.ArrayList(Pixel) = null,
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
    _loaded: bool = false,

    mcu_height: u32 = 0,
    mcu_width: u32 = 0,
    mcu_height_real: u32 = 0,
    mcu_width_real: u32 = 0,
    horizontal_sampling_factor: u8 = 1,
    vertical_sampling_factor: u8 = 1,
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

        self.mcu_height = (self.height + 7) / 8;
        self.mcu_width = (self.width + 7) / 8;
        self.mcu_height_real = self.mcu_height;
        self.mcu_width_real = self.mcu_width;

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
            if (component_id == 1) {
                if ((self._color_components[component_id - 1].horizontal_sampling_factor != 1 and self._color_components[component_id - 1] != 2) or
                    (self._color_components[component_id - 1].vertical_sampling_factor != 1 and self._color_components[component_id - 1].vertical_sampling_factor != 2))
                {
                    return JPEG_ERRORS.INVALID_SAMPLING_FACTOR;
                }
                if (self._color_components[component_id - 1].horizontal_sampling_factor == 2 and self.mcu_width % 2 == 1) {
                    self.mcu_width_real += 1;
                }
                if (self._color_components[component_id - 1].vertical_sampling_factor == 2 and self.mcu_height % 2 == 1) {
                    self.mcu_height_real += 1;
                }
            } else {
                if (self._color_components[component_id - 1].horizontal_sampling_facto != 1 or self._color_components[component_id - 1].vertical_sampling_factor != 1) {
                    return JPEG_ERRORS.INVALID_SAMPLING_FACTOR;
                }
            }
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
                all_symbols += buffer[index.* + 1];
                index.* += 1;
                huff_table.offsets[i] = all_symbols;
            }
            if (all_symbols > 162) {
                return JPEG_ERRORS.TOO_MANY_HUFFMAN_SYMBOLS;
            }
            for (0..all_symbols) |j| {
                huff_table.symbols[j] = buffer[index.* + 1];
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
                    try self._read_quant_table(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.DRI)) {
                    try self._read_restart_interval(buffer, &i);
                } else if (current == @intFromEnum(JPEG_HEADERS.SOS)) {
                    try self._read_start_of_scan(buffer, &i, allocator);
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
    }
    pub fn clean_up(self: *Image) void {
        std.ArrayList(Pixel).deinit(self.data.?);
        std.ArrayList(u8).deinit(self._huffman_data.?);
    }
    pub fn print(self: *Image) void {
        std.debug.print("Quant Tables:\n", .{});
        for (self._quantization_tables) |table| {
            table.print();
        }
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
        // if (self.data) |data| {
        //     for (data.items) |item| {
        //         std.debug.print("({d},{d},{d}) ", .{item.r});
        //     }
        //     std.debug.print("\n", .{});
        // }
        std.debug.print("Huffman data length: {d}\n", .{self._huffman_data.?.items.len});
    }
    fn _generate_huffman_codes(_: *Image, h_table: *HuffmanTable) void {
        var code: u32 = 0;
        for (0..h_table.offsets.len - 1) |i| {
            for (h_table.offsets[i]..h_table.offsets[i + 1]) |j| {
                h_table.codes[j] = code;
                code += 1;
            }
            code <<= 1;
        }
    }
    fn _decode_huffman_data(self: *Image, allocator: *std.mem.Allocator) (error{OutOfMemory} || JPEG_ERRORS || BITREADER_ERRORS)![]MCU {
        const mcus: []MCU = try allocator.alloc(MCU, self.mcu_height_real * self.mcu_width_real);
        for (mcus) |*mcu| {
            mcu.*.init();
        }
        for (&self._huffman_dct_tables) |*table| {
            if (table.*.set) {
                self._generate_huffman_codes(table);
            }
        }

        for (&self._huffman_act_tables) |*table| {
            if (table.*.set) {
                self._generate_huffman_codes(table);
            }
        }

        var bit_reader: BitReader = BitReader{ .data = &self._huffman_data.? };
        var previous_dcs: [3]i32 = [_]i32{0} ** 3;
        var y: usize = 0;
        var x: usize = 0;
        while (y < self.mcu_height) : (y += self.vertical_sampling_factor) {
            while (x < self.mcu_width) : (x += self.horizontal_sampling_factor) {
                if (self._restart_interval != 0 and (y * self.mcu_width_real + x) % self._restart_interval == 0) {
                    previous_dcs[0] = 0;
                    previous_dcs[1] = 0;
                    previous_dcs[2] = 0;
                    bit_reader.align_reader();
                }
                for (0..self._num_components) |j| {
                    for (0..self._color_components[j].vertical_sampling_factor) |v| {
                        for (0..self._color_components[j].horizontal_sampling_factor) |h| {
                            try _decode_MCU_component(self, &bit_reader, mcus[(y + v) * self.mcu_width_real + (x + h)].get(j), &previous_dcs[j], &self._huffman_dct_tables[self._color_components[j].huffman_dct_table_id], &self._huffman_act_tables[self._color_components[j].huffman_act_table_id]);
                        }
                    }
                }
            }
        }

        return mcus;
    }
    fn _get_next_symbol(_: *Image, bit_reader: *BitReader, h_table: *HuffmanTable) (JPEG_ERRORS || BITREADER_ERRORS)!u8 {
        var current_code: i32 = 0;
        for (0..h_table.offsets.len - 1) |i| {
            const bit: i32 = @as(i32, @intCast(try bit_reader.read_bit()));
            current_code = (current_code << 1) | bit;
            for (h_table.offsets[i]..h_table.offsets[i + 1]) |j| {
                if (current_code == h_table.codes[j]) {
                    return h_table.symbols[j];
                }
            }
        }
        return JPEG_ERRORS.HUFFMAN_DECODING;
    }
    fn _decode_MCU_component(self: *Image, bit_reader: *BitReader, color_channel: []i32, previous_dc: *i32, dct_table: *HuffmanTable, act_table: *HuffmanTable) (JPEG_ERRORS || BITREADER_ERRORS)!void {
        const length: u8 = try _get_next_symbol(self, bit_reader, dct_table);
        if (length > 11) {
            return JPEG_ERRORS.HUFFMAN_DECODING;
        }
        var coeff: i32 = @as(i32, @intCast(try bit_reader.read_bits(length)));
        if (length != 0 and coeff < (@as(i32, 1) << @as(u5, @intCast(length - 1)))) {
            coeff -= (@as(i32, 1) << @as(u5, @intCast(length))) - 1;
        }
        color_channel[0] = coeff + previous_dc.*;
        previous_dc.* = color_channel[0];

        var i: u32 = 1;
        while (i < color_channel.len) {
            const symbol: u8 = try self._get_next_symbol(bit_reader, act_table);
            if (symbol == 0x00) {
                for (i..color_channel.len) |_| {
                    color_channel[zig_zag_map[i]] = 0;
                    i += 1;
                }
                return;
            }
            var num_zeroes: u8 = symbol >> 4;
            const coeff_length: u8 = symbol & 0x0F;

            if (symbol == 0xF0) {
                num_zeroes = 16;
            }
            //std.debug.print("{d} {d} {d}\n", .{ num_zeroes, i + num_zeroes, color_channel.len });
            if (i + num_zeroes >= color_channel.len) {
                return JPEG_ERRORS.HUFFMAN_DECODING;
            }

            for (0..num_zeroes) |_| {
                color_channel[zig_zag_map[i]] = 0;
                i += 1;
            }

            if (coeff_length > 10) {
                return JPEG_ERRORS.HUFFMAN_DECODING;
            }

            if (coeff_length != 0) {
                coeff = @as(i32, @intCast(try bit_reader.read_bits(coeff_length)));
                if (coeff < (@as(i32, 1) << @as(u5, @intCast(coeff_length - 1)))) {
                    coeff -= (@as(i32, 1) << @as(u5, @intCast(coeff_length))) - 1;
                }
                color_channel[zig_zag_map[i]] = coeff;
                i += 1;
            }
        }
    }
    fn _de_quant_data(self: *Image, mcus: []MCU) !void {
        var y: usize = 0;
        var x: usize = 0;
        while (y < self.mcu_height) : (y += self.vertical_sampling_factor) {
            while (x < self.mcu_width) : (x += self.horizontal_sampling_factor) {
                for (0..self._num_components) |j| {
                    for (0..self._color_components[j].vertical_sampling_factor) |v| {
                        for (0..self._color_components[j].horizontal_sampling_factor) |h| {
                            for (0..mcus[(y + v) * self.mcu_width_real + (x + h)].get(j).len) |k| {
                                mcus[(y + v) * self.mcu_width_real + (x + h)].get(j)[k] *= self._quantization_tables[self._color_components[j].quantization_table_id].table[k];
                            }
                        }
                    }
                }
            }
        }
    }
    // inverse dct based on AAN
    fn _inverse_dct_component(_: *Image, mcu: *[64]i32) void {
        for (0..8) |i| {
            const g0: f32 = @as(f32, @floatFromInt(mcu[0 * 8 + i])) * IDCT_SCALING_FACTORS.s0;
            const g1: f32 = @as(f32, @floatFromInt(mcu[4 * 8 + i])) * IDCT_SCALING_FACTORS.s4;
            const g2: f32 = @as(f32, @floatFromInt(mcu[2 * 8 + i])) * IDCT_SCALING_FACTORS.s2;
            const g3: f32 = @as(f32, @floatFromInt(mcu[6 * 8 + i])) * IDCT_SCALING_FACTORS.s6;
            const g4: f32 = @as(f32, @floatFromInt(mcu[5 * 8 + i])) * IDCT_SCALING_FACTORS.s5;
            const g5: f32 = @as(f32, @floatFromInt(mcu[1 * 8 + i])) * IDCT_SCALING_FACTORS.s1;
            const g6: f32 = @as(f32, @floatFromInt(mcu[7 * 8 + i])) * IDCT_SCALING_FACTORS.s7;
            const g7: f32 = @as(f32, @floatFromInt(mcu[3 * 8 + i])) * IDCT_SCALING_FACTORS.s3;

            const f0: f32 = g0;
            const f1: f32 = g1;
            const f2: f32 = g2;
            const f3: f32 = g3;
            const f4: f32 = g4 - g7;
            const f5: f32 = g5 + g6;
            const f6: f32 = g5 - g6;
            const f7: f32 = g4 + g7;

            const e0: f32 = f0;
            const e1: f32 = f1;
            const e2: f32 = f2 - f3;
            const e3: f32 = f2 + f3;
            const e4: f32 = f4;
            const e5: f32 = f5 - f7;
            const e6: f32 = f6;
            const e7: f32 = f5 + f7;
            const e8: f32 = f4 + f6;

            const d0: f32 = e0;
            const d1: f32 = e1;
            const d2: f32 = e2 * IDCT_SCALING_FACTORS.m1;
            const d3: f32 = e3;
            const d4: f32 = e4 * IDCT_SCALING_FACTORS.m2;
            const d5: f32 = e5 * IDCT_SCALING_FACTORS.m1;
            const d6: f32 = e6 * IDCT_SCALING_FACTORS.m4;
            const d7: f32 = e7;
            const d8: f32 = e8 * IDCT_SCALING_FACTORS.m5;

            const c0: f32 = d0 + d1;
            const c1: f32 = d0 - d1;
            const c2: f32 = d2 - d3;
            const c3: f32 = d3;
            const c4: f32 = d4 + d8;
            const c5: f32 = d5 + d7;
            const c6: f32 = d6 - d8;
            const c7: f32 = d7;
            const c8: f32 = c5 - c6;

            const b0: f32 = c0 + c3;
            const b1: f32 = c1 + c2;
            const b2: f32 = c1 - c2;
            const b3: f32 = c0 - c3;
            const b4: f32 = c4 - c8;
            const b5: f32 = c8;
            const b6: f32 = c6 - c7;
            const b7: f32 = c7;

            mcu[0 * 8 + i] = @as(i32, @intFromFloat(b0 + b7));
            mcu[1 * 8 + i] = @as(i32, @intFromFloat(b1 + b6));
            mcu[2 * 8 + i] = @as(i32, @intFromFloat(b2 + b5));
            mcu[3 * 8 + i] = @as(i32, @intFromFloat(b3 + b4));
            mcu[4 * 8 + i] = @as(i32, @intFromFloat(b3 - b4));
            mcu[5 * 8 + i] = @as(i32, @intFromFloat(b2 - b5));
            mcu[6 * 8 + i] = @as(i32, @intFromFloat(b1 - b6));
            mcu[7 * 8 + i] = @as(i32, @intFromFloat(b0 - b7));
        }

        for (0..8) |i| {
            const g0: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 0])) * IDCT_SCALING_FACTORS.s0;
            const g1: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 4])) * IDCT_SCALING_FACTORS.s4;
            const g2: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 2])) * IDCT_SCALING_FACTORS.s2;
            const g3: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 6])) * IDCT_SCALING_FACTORS.s6;
            const g4: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 5])) * IDCT_SCALING_FACTORS.s5;
            const g5: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 1])) * IDCT_SCALING_FACTORS.s1;
            const g6: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 7])) * IDCT_SCALING_FACTORS.s7;
            const g7: f32 = @as(f32, @floatFromInt(mcu[i * 8 + 3])) * IDCT_SCALING_FACTORS.s3;

            const f0: f32 = g0;
            const f1: f32 = g1;
            const f2: f32 = g2;
            const f3: f32 = g3;
            const f4: f32 = g4 - g7;
            const f5: f32 = g5 + g6;
            const f6: f32 = g5 - g6;
            const f7: f32 = g4 + g7;

            const e0: f32 = f0;
            const e1: f32 = f1;
            const e2: f32 = f2 - f3;
            const e3: f32 = f2 + f3;
            const e4: f32 = f4;
            const e5: f32 = f5 - f7;
            const e6: f32 = f6;
            const e7: f32 = f5 + f7;
            const e8: f32 = f4 + f6;

            const d0: f32 = e0;
            const d1: f32 = e1;
            const d2: f32 = e2 * IDCT_SCALING_FACTORS.m1;
            const d3: f32 = e3;
            const d4: f32 = e4 * IDCT_SCALING_FACTORS.m2;
            const d5: f32 = e5 * IDCT_SCALING_FACTORS.m1;
            const d6: f32 = e6 * IDCT_SCALING_FACTORS.m4;
            const d7: f32 = e7;
            const d8: f32 = e8 * IDCT_SCALING_FACTORS.m5;

            const c0: f32 = d0 + d1;
            const c1: f32 = d0 - d1;
            const c2: f32 = d2 - d3;
            const c3: f32 = d3;
            const c4: f32 = d4 + d8;
            const c5: f32 = d5 + d7;
            const c6: f32 = d6 - d8;
            const c7: f32 = d7;
            const c8: f32 = c5 - c6;

            const b0: f32 = c0 + c3;
            const b1: f32 = c1 + c2;
            const b2: f32 = c1 - c2;
            const b3: f32 = c0 - c3;
            const b4: f32 = c4 - c8;
            const b5: f32 = c8;
            const b6: f32 = c6 - c7;
            const b7: f32 = c7;

            mcu[i * 8 + 0] = @as(i32, @intFromFloat(b0 + b7 + 0.5));
            mcu[i * 8 + 1] = @as(i32, @intFromFloat(b1 + b6 + 0.5));
            mcu[i * 8 + 2] = @as(i32, @intFromFloat(b2 + b5 + 0.5));
            mcu[i * 8 + 3] = @as(i32, @intFromFloat(b3 + b4 + 0.5));
            mcu[i * 8 + 4] = @as(i32, @intFromFloat(b3 - b4 + 0.5));
            mcu[i * 8 + 5] = @as(i32, @intFromFloat(b2 - b5 + 0.5));
            mcu[i * 8 + 6] = @as(i32, @intFromFloat(b1 - b6 + 0.5));
            mcu[i * 8 + 7] = @as(i32, @intFromFloat(b0 - b7 + 0.5));
        }
    }
    fn _inverse_dct(self: *Image, mcus: []MCU) void {
        var y: usize = 0;
        var x: usize = 0;
        while (y < self.mcu_height) : (y += self.vertical_sampling_factor) {
            while (x < self.mcu_width) : (x += self.horizontal_sampling_factor) {
                for (0..self._num_components) |j| {
                    for (0..self._color_components[j].vertical_sampling_factor) |v| {
                        for (0..self._color_components[j].horizontal_sampling_factor) |h| {
                            self._inverse_dct_component(mcus[(y + v) * self.mcu_width_real + (x + h)].get(j));
                        }
                    }
                }
            }
        }
    }
    fn _ycb_rgb(self: *Image, mcus: []MCU) void {
        for (0..(self.mcu_height * self.mcu_width_real)) |i| {
            for (0..64) |j| {
                var r: f32 = @as(f32, @floatFromInt(mcus[i].y[j])) + 1.402 * @as(f32, @floatFromInt(mcus[i].cr[j])) + 128.0;
                var g: f32 = @as(f32, @floatFromInt(mcus[i].y[j])) - 0.344 * @as(f32, @floatFromInt(mcus[i].cb[j])) - 0.714 * @as(f32, @floatFromInt(mcus[i].cr[j])) + 128.0;
                var b: f32 = @as(f32, @floatFromInt(mcus[i].y[j])) + 1.722 * @as(f32, @floatFromInt(mcus[i].cb[j])) + 128.0;
                if (r < 0) {
                    r = 0;
                }
                if (r > 255) {
                    r = 255;
                }
                if (g < 0) {
                    g = 0;
                }
                if (g > 255) {
                    g = 255;
                }
                if (b < 0) {
                    b = 0;
                }
                if (b > 255) {
                    b = 255;
                }
                mcus[i].r[j] = @as(i32, @intFromFloat(r));
                mcus[i].g[j] = @as(i32, @intFromFloat(g));
                mcus[i].b[j] = @as(i32, @intFromFloat(b));
            }
        }
    }
    fn _gen_rgb_data(self: *Image, allocator: *std.mem.Allocator) !void {
        self.data = std.ArrayList(Pixel).init(allocator.*);
        const mcus: []MCU = try self._decode_huffman_data(allocator);
        defer allocator.free(mcus);
        try self._de_quant_data(mcus);
        self._inverse_dct(mcus);
        self._ycb_rgb(mcus);
        // store color data to be used later in either writing to another file or direct access in code
        var i: usize = self.height;
        while (i > 0) {
            i -= 1;
            const mcu_row: u32 = @as(u32, @intCast(i)) / 8;
            const pixel_row: u32 = @as(u32, @intCast(i)) % 8;
            for (0..self.width) |j| {
                const mcu_col: u32 = @as(u32, @intCast(j)) / 8;
                const pixel_col: u32 = @as(u32, @intCast(j)) % 8;
                const mcu_index = mcu_row * self.mcu_width_real + mcu_col;
                const pixel_index = pixel_row * 8 + pixel_col;
                try self.data.?.append(Pixel{
                    .r = @truncate(@as(u32, @bitCast(mcus[mcu_index].r[pixel_index]))),
                    .g = @truncate(@as(u32, @bitCast(mcus[mcu_index].g[pixel_index]))),
                    .b = @truncate(@as(u32, @bitCast(mcus[mcu_index].b[pixel_index]))),
                });
            }
        }
    }
    fn _little_endian(_: *Image, file: *const std.fs.File, num_bytes: comptime_int, i: u32) !void {
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
    pub fn convert_grayscale(self: *Image) !void {
        if (self._loaded) {
            for (0..self.data.?.items.len) |i| {
                const gray: u8 = @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.?.items[i].r)) * 0.2989)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.?.items[i].g)) * 0.5870)) + @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.data.?.items[i].b)) * 0.1140));
                self.data.?.items[i].r = gray;
                self.data.?.items[i].g = gray;
                self.data.?.items[i].b = gray;
            }
        } else {
            return IMAGE_ERRORS.NOT_LOADED;
        }
    }
    pub fn write_BMP(self: *Image, file_name: []const u8) !void {
        if (!self._loaded) {
            return IMAGE_ERRORS.NOT_LOADED;
        }
        const image_file = try std.fs.cwd().createFile(file_name, .{});
        defer image_file.close();
        try image_file.writer().writeByte('B');
        try image_file.writer().writeByte('M');
        const padding_size: u32 = self.width % 4;
        const size: u32 = 14 + 12 + self.height * self.width * 3 + padding_size * self.height;
        try self._little_endian(&image_file, 4, size);
        try self._little_endian(&image_file, 4, 0);
        try self._little_endian(&image_file, 4, 0x1A);
        try self._little_endian(&image_file, 4, 12);
        try self._little_endian(&image_file, 2, self.width);
        try self._little_endian(&image_file, 2, self.height);
        try self._little_endian(&image_file, 2, 1);
        try self._little_endian(&image_file, 2, 24);
        for (0..self.height) |i| {
            for (0..self.width) |j| {
                const pixel: *Pixel = &self.data.?.items[i * self.width + j];
                try image_file.writer().writeByte(pixel.b);
                try image_file.writer().writeByte(pixel.g);
                try image_file.writer().writeByte(pixel.r);
            }
            for (0..padding_size) |_| {
                try image_file.writer().writeByte(0);
            }
        }
    }
    pub fn load_JPEG(self: *Image, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        try self._read_JPEG(file_name, allocator);
        self.print();
        try self._gen_rgb_data(allocator);
        self._loaded = true;
    }
};

test "CAT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image{};
    try image.load_JPEG("cat.jpg", &allocator);
    try image.convert_grayscale();
    try image.write_BMP("cat.bmp");
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "GORILLA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var image = Image{};
    try image.load_JPEG("gorilla.jpg", &allocator);
    try image.write_BMP("gorilla.bmp");
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!\n", .{});
    }
}

test "MCU" {
    var mcu = MCU{};
    mcu.init();
    mcu.r[1] = 5;
    try std.testing.expect(mcu.r[1] == 5 and mcu.y[1] == 5);
}
