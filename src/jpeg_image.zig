//https://www.youtube.com/watch?v=CPT4FSkFUgs&list=PLpsTn9TA_Q8VMDyOPrDKmSJYt1DLgDZU4&index=1
const std = @import("std");
const utils = @import("utils.zig");
const image_core = @import("image_core.zig");

pub const ConvolMat = image_core.ConvolMat;
pub const ImageCore = image_core.ImageCore;
const JPEG_LOG = std.log.scoped(.jpeg_image);

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
    const m0: f64 = 2.0 * std.math.cos(1.0 / 16.0 * 2.0 * std.math.pi);
    const m1: f64 = 2.0 * std.math.cos(2.0 / 16.0 * 2.0 * std.math.pi);
    const m3: f64 = 2.0 * std.math.cos(2.0 / 16.0 * 2.0 * std.math.pi);
    const m5: f64 = 2.0 * std.math.cos(3.0 / 16.0 * 2.0 * std.math.pi);
    const m2: f64 = 2.0 * std.math.cos(1.0 / 16.0 * 2.0 * std.math.pi) - 2.0 * std.math.cos(3.0 / 16.0 * 2.0 * std.math.pi);
    const m4: f64 = 2.0 * std.math.cos(1.0 / 16.0 * 2.0 * std.math.pi) + 2.0 * std.math.cos(3.0 / 16.0 * 2.0 * std.math.pi);
    const s0: f64 = std.math.cos(0.0 / 16.0 * std.math.pi) / std.math.sqrt(8.0);
    const s1: f64 = std.math.cos(1.0 / 16.0 * std.math.pi) / 2.0;
    const s2: f64 = std.math.cos(2.0 / 16.0 * std.math.pi) / 2.0;
    const s3: f64 = std.math.cos(3.0 / 16.0 * std.math.pi) / 2.0;
    const s4: f64 = std.math.cos(4.0 / 16.0 * std.math.pi) / 2.0;
    const s5: f64 = std.math.cos(5.0 / 16.0 * std.math.pi) / 2.0;
    const s6: f64 = std.math.cos(6.0 / 16.0 * std.math.pi) / 2.0;
    const s7: f64 = std.math.cos(7.0 / 16.0 * std.math.pi) / 2.0;
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
    symbols: [176]u8 = [_]u8{0} ** 176,
    offsets: [17]u8 = [_]u8{0} ** 17,
    set: bool = false,
    codes: [176]u32 = [_]u32{0} ** 176,
    pub fn print(self: *const HuffmanTable) void {
        if (self.set) {
            JPEG_LOG.info("Symbols: \n", .{});
            for (0..16) |i| {
                JPEG_LOG.info("{d}: ", .{i + 1});
                for (self.offsets[i]..self.offsets[i + 1]) |j| {
                    JPEG_LOG.info("{d} ", .{self.symbols[j]});
                }
                JPEG_LOG.info("\n", .{});
            }
        }
    }
};

const QuantizationTable = struct {
    table: [64]u16 = [_]u16{0} ** 64,
    set: bool = false,
    pub fn print(self: *const QuantizationTable) void {
        for (0.., self.table) |i, item| {
            JPEG_LOG.info("{x} ", .{item});
            if (i != 0 and i % 8 == 0) {
                JPEG_LOG.info("\n", .{});
            }
        }
        JPEG_LOG.info("\n", .{});
    }
};

const ColorComponent = struct {
    horizontal_sampling_factor: u8 = 1,
    vertical_sampling_factor: u8 = 1,
    quantization_table_id: u8 = 0,
    huffman_dct_table_id: u8 = 0,
    huffman_act_table_id: u8 = 0,
    used_in_frame: bool = false,
    used_in_scan: bool = false,
};

//TODO vectorize
fn Block(comptime T: type) type {
    return struct {
        y: [64]T = [_]T{0} ** 64,
        r: []T = undefined,
        cb: [64]T = [_]T{0} ** 64,
        g: []T = undefined,
        cr: [64]T = [_]T{0} ** 64,
        b: []T = undefined,
        const Self = @This();
        pub fn init(self: *Self) void {
            for (&self.y) |*val| {
                val.* = 0;
            }
            for (&self.cb) |*val| {
                val.* = 0;
            }
            for (&self.cr) |*val| {
                val.* = 0;
            }
            self.r = &self.y;
            self.g = &self.cb;
            self.b = &self.cr;
        }
        pub fn get(self: *Self, index: usize) *[64]T {
            switch (index) {
                0 => return &self.y,
                1 => return &self.cb,
                2 => return &self.cr,
                else => unreachable,
            }
        }
    };
}

pub const JPEGImage = struct {
    data: std.ArrayList(utils.Pixel) = undefined,
    quantization_tables: [4]QuantizationTable = [_]QuantizationTable{.{}} ** 4,
    height: u32 = 0,
    width: u32 = 0,
    allocator: std.mem.Allocator = undefined,
    frame_type: JPEG_HEADERS = JPEG_HEADERS.SOF0,
    num_components: u8 = 0,
    restart_interval: u16 = 0,
    zero_based: bool = false,
    color_components: [3]ColorComponent = [_]ColorComponent{.{}} ** 3,
    huffman_dct_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    huffman_act_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    start_of_selection: u8 = 0,
    end_of_selection: u8 = 63,
    succcessive_approximation_high: u8 = 0,
    succcessive_approximation_low: u8 = 0,
    loaded: bool = false,
    components_in_scan: u8 = 0,
    blocks: []Block(i32) = undefined,
    block_height: u32 = 0,
    block_width: u32 = 0,
    block_height_real: u32 = 0,
    block_width_real: u32 = 0,
    horizontal_sampling_factor: u32 = 1,
    vertical_sampling_factor: u32 = 1,
    grayscale: bool = false,
    pub const Error = error{
        InvalidHeader,
        InvalidDQTID,
        InvalidDQT,
        CMYKNotSupported,
        YIQNotSupported,
        InvalidComponentID,
        InvalidRestartMarker,
        InvalidHuffmanID,
        TooManyHuffmanSymbols,
        InvalidHuffmanLength,
        HuffmanDecoding,
        DuplicateColorComponentID,
        InvalidSOS,
        InvalidSuccessiveApproximation,
        InvalidSpectralSelection,
        InvalidEOI,
        InvalidArithmeticCoding,
        InvalidSOFMarker,
        InvalidMarker,
        InvalidComponentLength,
        InvalidSamplingFactor,
        NotLoaded,
        ThreadQuotaExceeded,
        LockedMemoryLimitExceeded,
    } || utils.BitReader.Error || utils.ByteStream.Error || ImageCore.Error || std.mem.Allocator.Error || std.time.Timer.Error;

    fn thread_compute(self: *JPEGImage, start: usize, block_height: u32) Error!void {
        try self.de_quant_data(start, block_height);
        self.inverse_dct(start, block_height);
        self.ycb_rgb(start, block_height);
    }
    fn read_start_of_frame(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        JPEG_LOG.info("Reading SOF marker\n", .{});
        if (self.num_components != 0) {
            return Error.InvalidHeader;
        }

        const length: u16 = try bit_reader.read(u16);

        const precision: u8 = try bit_reader.read(u8);
        if (precision != 8) {
            return Error.InvalidHeader;
        }
        self.height = try bit_reader.read(u16);
        self.width = try bit_reader.read(u16);
        JPEG_LOG.info("width {d} height {d}\n", .{ self.width, self.height });
        if (self.height == 0 or self.width == 0) {
            return Error.InvalidHeader;
        }

        self.block_height = (self.height + 7) / 8;
        self.block_width = (self.width + 7) / 8;
        self.block_height_real = self.block_height;
        self.block_width_real = self.block_width;

        self.num_components = try bit_reader.read(u8);
        JPEG_LOG.info("num_components {d}\n", .{self.num_components});
        if (self.num_components == 4) {
            return Error.CMYKNotSupported;
        }
        if (self.num_components == 0) {
            return Error.InvalidHeader;
        }
        for (0..self.num_components) |_| {
            var component_id = try bit_reader.read(u8);
            if (component_id == 0) {
                self.zero_based = true;
            }
            if (self.zero_based) {
                component_id += 1;
            }
            if (component_id == 4 or component_id == 5) {
                return Error.YIQNotSupported;
            }
            if (component_id == 0 or component_id > 3) {
                return Error.InvalidComponentID;
            }

            if (self.color_components[component_id - 1].used_in_frame) {
                return Error.InvalidComponentID;
            }

            self.color_components[component_id - 1].used_in_frame = true;
            const sampling_factor: u8 = try bit_reader.read(u8);
            JPEG_LOG.info("sampling factor {x}\n", .{sampling_factor});
            self.color_components[component_id - 1].horizontal_sampling_factor = sampling_factor >> 4;
            self.color_components[component_id - 1].vertical_sampling_factor = sampling_factor & 0x0F;
            self.color_components[component_id - 1].quantization_table_id = try bit_reader.read(u8);
            JPEG_LOG.info("sampling factor vert {d} horizontal {d}\n", .{ self.color_components[component_id - 1].vertical_sampling_factor, self.color_components[component_id - 1].horizontal_sampling_factor });
            if (component_id == 1) {
                if ((self.color_components[component_id - 1].horizontal_sampling_factor != 1 and self.color_components[component_id - 1].horizontal_sampling_factor != 2) or
                    (self.color_components[component_id - 1].vertical_sampling_factor != 1 and self.color_components[component_id - 1].vertical_sampling_factor != 2))
                {
                    return Error.InvalidSamplingFactor;
                }
                if (self.color_components[component_id - 1].horizontal_sampling_factor == 2 and self.block_width % 2 == 1) {
                    self.block_width_real += 1;
                    JPEG_LOG.info("incrementing real\n", .{});
                }
                if (self.color_components[component_id - 1].vertical_sampling_factor == 2 and self.block_height % 2 == 1) {
                    self.block_height_real += 1;
                    JPEG_LOG.info("incrementing real\n", .{});
                }
                self.horizontal_sampling_factor = self.color_components[component_id - 1].horizontal_sampling_factor;
                self.vertical_sampling_factor = self.color_components[component_id - 1].vertical_sampling_factor;
            } else {
                if (self.color_components[component_id - 1].horizontal_sampling_factor != 1 or self.color_components[component_id - 1].vertical_sampling_factor != 1) {
                    return Error.InvalidSamplingFactor;
                }
            }
            if (self.color_components[component_id - 1].quantization_table_id > 3) {
                return Error.InvalidComponentID;
            }
        }
        JPEG_LOG.info("length {d} - 8 - (3 * {d})\n", .{ length, self.num_components });
        if (length - 8 - (3 * self.num_components) != 0) {
            return Error.InvalidHeader;
        }
    }
    fn read_quant_table(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        var length: i16 = try bit_reader.read(i16);
        length -= 2;
        while (length > 0) {
            JPEG_LOG.info("Reading a Quant table\n", .{});
            const table_info = try bit_reader.read(u8);
            length -= 1;
            const table_id = table_info & 0x0F;

            if (table_id > 3) {
                return Error.InvalidDQTID;
            }
            self.quantization_tables[table_id].set = true;
            if (table_info >> 4 != 0) {
                // 16 bit values
                for (0..64) |i| {
                    self.quantization_tables[table_id].table[zig_zag_map[i]] = try bit_reader.read(u16);
                }
                length -= 128;
            } else {
                // 8 bit values
                for (0..64) |i| {
                    self.quantization_tables[table_id].table[zig_zag_map[i]] = try bit_reader.read(u8);
                }
                length -= 64;
            }
        }
        if (length != 0) {
            return Error.InvalidDQT;
        }
    }
    fn read_restart_interval(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        JPEG_LOG.info("Reading DRI marker\n", .{});
        const length: i16 = try bit_reader.read(i16);
        self.restart_interval = try bit_reader.read(u16);
        if (length - 4 != 0) {
            return Error.InvalidRestartMarker;
        }
        JPEG_LOG.info("Restart interval {d}\n", .{self.restart_interval});
    }
    fn read_start_of_scan(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        JPEG_LOG.info("Reading SOS marker\n", .{});
        if (self.num_components == 0) {
            return Error.InvalidHeader;
        }
        const length: u16 = try bit_reader.read(u16);
        for (0..self.num_components) |i| {
            self.color_components[i].used_in_scan = false;
        }
        self.components_in_scan = try bit_reader.read(u8);
        if (self.components_in_scan == 0) {
            return Error.InvalidComponentLength;
        }
        for (0..self.components_in_scan) |_| {
            var component_id = try bit_reader.read(u8);
            if (self.zero_based) {
                component_id += 1;
            }
            if (component_id > self.num_components) {
                return Error.InvalidComponentID;
            }
            var color_component: *ColorComponent = &self.color_components[component_id - 1];
            if (!color_component.used_in_frame) {
                return Error.InvalidComponentID;
            }
            if (color_component.used_in_scan) {
                return Error.DuplicateColorComponentID;
            }
            color_component.used_in_scan = true;
            const huffman_table_ids = try bit_reader.read(u8);
            color_component.huffman_dct_table_id = huffman_table_ids >> 4;
            color_component.huffman_act_table_id = huffman_table_ids & 0x0F;
            if (color_component.huffman_act_table_id == 3 or color_component.huffman_dct_table_id == 3) {
                return Error.InvalidHuffmanID;
            }
        }
        self.start_of_selection = try bit_reader.read(u8);
        self.end_of_selection = try bit_reader.read(u8);
        const succ_approx = try bit_reader.read(u8);
        self.succcessive_approximation_high = succ_approx >> 4;
        self.succcessive_approximation_low = succ_approx & 0x0F;
        JPEG_LOG.info("start {d} end {d} high {d} low {d}\n", .{ self.start_of_selection, self.end_of_selection, self.succcessive_approximation_high, self.succcessive_approximation_low });
        if (self.frame_type == JPEG_HEADERS.SOF0) {
            if (self.start_of_selection != 0 or self.end_of_selection != 63) {
                return Error.InvalidSpectralSelection;
            }

            if (self.succcessive_approximation_high != 0 or self.succcessive_approximation_low != 0) {
                return Error.InvalidSuccessiveApproximation;
            }
        } else if (self.frame_type == JPEG_HEADERS.SOF2) {
            if (self.start_of_selection > self.end_of_selection) {
                return Error.InvalidSpectralSelection;
            }
            if (self.end_of_selection > 63) {
                return Error.InvalidSpectralSelection;
            }
            if (self.start_of_selection == 0 and self.end_of_selection != 0) {
                return Error.InvalidSpectralSelection;
            }
            if (self.start_of_selection != 0 and self.components_in_scan != 1) {
                return Error.InvalidSpectralSelection;
            }
            if (self.succcessive_approximation_high != 0 and self.succcessive_approximation_low != self.succcessive_approximation_high - 1) {
                return Error.InvalidSuccessiveApproximation;
            }
        }

        if (length - 6 - (2 * self.components_in_scan) != 0) {
            return Error.InvalidSOS;
        }
    }
    fn read_huffman(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        JPEG_LOG.info("Reading DHT marker\n", .{});
        var length: i16 = try bit_reader.read(i16);
        length -= 2;
        while (length > 0) {
            const table_info: u8 = try bit_reader.read(u8);
            const table_id = table_info & 0x0F;
            const act_table: bool = (table_info >> 4) != 0;

            var huff_table: *HuffmanTable = undefined;
            if (table_id > 3) {
                return Error.InvalidHuffmanID;
            }
            if (act_table) {
                huff_table = &self.huffman_act_tables[table_id];
            } else {
                huff_table = &self.huffman_dct_tables[table_id];
            }
            huff_table.set = true;
            huff_table.offsets[0] = 0;
            var all_symbols: u8 = 0;
            for (1..17) |i| {
                all_symbols += try bit_reader.read(u8);
                huff_table.offsets[i] = all_symbols;
            }
            if (all_symbols > 176) {
                return Error.TooManyHuffmanSymbols;
            }
            for (0..all_symbols) |j| {
                huff_table.symbols[j] = try bit_reader.read(u8);
            }
            self.generate_huffman_codes(huff_table);
            length -= 17 + all_symbols;
        }
        if (length != 0) {
            return Error.InvalidHuffmanLength;
        }
    }
    fn skippable_header(_: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        _ = try bit_reader.read(u16);
    }
    fn read_appn(_: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        const length: u16 = try bit_reader.read(u16);
        if (length < 2) {
            return Error.InvalidHeader;
        }

        for (0..length - 2) |_| {
            _ = try bit_reader.read(u8);
        }
    }
    fn read_headers(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        var last: u8 = try bit_reader.read(u8);
        var current: u8 = try bit_reader.read(u8);
        if (last == @intFromEnum(JPEG_HEADERS.HEADER) and current == @intFromEnum(JPEG_HEADERS.SOI)) {
            JPEG_LOG.info("Start of image\n", .{});
        } else {
            return Error.InvalidHeader;
        }
        last = try bit_reader.read(u8);
        current = try bit_reader.read(u8);
        while (bit_reader.has_bits()) {
            // Expecting header
            JPEG_LOG.info("Reading header {x} {x}\n", .{ last, current });
            if (last == @intFromEnum(JPEG_HEADERS.HEADER)) {
                if (current <= @intFromEnum(JPEG_HEADERS.APP15) and current >= @intFromEnum(JPEG_HEADERS.APP0)) {
                    JPEG_LOG.info("Application header {x} {x}\n", .{ last, current });
                    try self.read_appn(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.COM)) {
                    // comment
                    try self.skippable_header(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.DQT)) {
                    JPEG_LOG.info("Reading Quant table\n", .{});
                    try self.read_quant_table(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.DRI)) {
                    try self.read_restart_interval(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.SOS)) {
                    break;
                } else if (current == @intFromEnum(JPEG_HEADERS.DHT)) {
                    try self.read_huffman(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.EOI)) {
                    JPEG_LOG.info("End of image\n", .{});
                    return Error.InvalidEOI;
                } else if (current == @intFromEnum(JPEG_HEADERS.SOF0)) {
                    self.frame_type = JPEG_HEADERS.SOF0;
                    try self.read_start_of_frame(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.SOF2)) {
                    self.frame_type = JPEG_HEADERS.SOF2;
                    try self.read_start_of_frame(bit_reader);
                } else if ((current >= @intFromEnum(JPEG_HEADERS.JPG0) and current <= @intFromEnum(JPEG_HEADERS.JPG13)) or
                    current == @intFromEnum(JPEG_HEADERS.DNL) or
                    current == @intFromEnum(JPEG_HEADERS.DHP) or
                    current == @intFromEnum(JPEG_HEADERS.EXP))
                {
                    // unusued that can be skipped
                    try self.skippable_header(bit_reader);
                } else if (current == @intFromEnum(JPEG_HEADERS.DAC)) {
                    return Error.InvalidArithmeticCoding;
                } else if (current >= @intFromEnum(JPEG_HEADERS.SOF1) and current <= @intFromEnum(JPEG_HEADERS.SOF15)) {
                    return Error.InvalidSOFMarker;
                } else if (current >= @intFromEnum(JPEG_HEADERS.RST0) and current <= @intFromEnum(JPEG_HEADERS.RST7)) {
                    return Error.InvalidHeader;
                } else if (current == @intFromEnum(JPEG_HEADERS.TEM)) {} else if (current == @intFromEnum(JPEG_HEADERS.HEADER)) {
                    // allowed to have run of 0xFF
                    last = current;
                    current = try bit_reader.read(u8);
                    continue;
                } else {
                    return Error.InvalidHeader;
                }
                // handled valid header move to next
                last = try bit_reader.read(u8);
                current = try bit_reader.read(u8);
            } else {
                //expected header
                return Error.InvalidHeader;
            }
        }
    }
    fn read_scans(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        try self.read_start_of_scan(bit_reader);
        JPEG_LOG.info("next header {x} {x}\n", .{ bit_reader.byte_stream.buffer[bit_reader.byte_stream.index], bit_reader.byte_stream.buffer[bit_reader.byte_stream.index + 1] });
        //self.print();
        try self.decode_huffman_data(bit_reader);
        JPEG_LOG.info("next header {x} {x}\n", .{ bit_reader.byte_stream.buffer[bit_reader.byte_stream.index], bit_reader.byte_stream.buffer[bit_reader.byte_stream.index + 1] });
        var last: u8 = try bit_reader.read(u8);
        var current: u8 = try bit_reader.read(u8);
        while (true) {
            if (last != @intFromEnum(JPEG_HEADERS.HEADER)) {
                return Error.InvalidHeader;
            }
            if (current == @intFromEnum(JPEG_HEADERS.EOI)) {
                break;
            } else if (current == @intFromEnum(JPEG_HEADERS.DHT)) {
                try self.read_huffman(bit_reader);
            } else if (current == @intFromEnum(JPEG_HEADERS.SOS) and self.frame_type == JPEG_HEADERS.SOF2) {
                try self.read_start_of_scan(bit_reader);
                try self.decode_huffman_data(bit_reader);
            } else if (current == @intFromEnum(JPEG_HEADERS.DRI) and self.frame_type == JPEG_HEADERS.SOF2) {
                try self.read_restart_interval(bit_reader);
            } else if (current >= @intFromEnum(JPEG_HEADERS.RST0) and current <= @intFromEnum(JPEG_HEADERS.RST7)) {} else if (current == 0xFF) {
                current = try bit_reader.read(u8);
                continue;
            }
            JPEG_LOG.info("next header {x} {x}\n", .{ bit_reader.byte_stream.buffer[bit_reader.byte_stream.index], bit_reader.byte_stream.buffer[bit_reader.byte_stream.index + 1] });
            last = try bit_reader.read(u8);
            current = try bit_reader.read(u8);
        }
    }
    fn read_JPEG(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        try self.read_headers(bit_reader);
        self.blocks = try self.allocator.alloc(Block(i32), self.block_height_real * self.block_width_real);
        for (self.blocks) |*block| {
            block.*.init();
        }

        JPEG_LOG.info("next header {x} {x}\n", .{ bit_reader.byte_stream.buffer[bit_reader.byte_stream.index], bit_reader.byte_stream.buffer[bit_reader.byte_stream.index + 1] });
        try self.read_scans(bit_reader);
    }
    pub fn deinit(self: *JPEGImage) void {
        std.ArrayList(utils.Pixel).deinit(self.data);
    }
    pub fn print(self: *JPEGImage) void {
        JPEG_LOG.info("Quant Tables:\n", .{});
        for (self.quantization_tables) |table| {
            table.print();
        }
        JPEG_LOG.info("DC Tables:\n", .{});
        for (0.., self.huffman_dct_tables) |i, table| {
            JPEG_LOG.info("Table ID: {d}\n", .{i});
            table.print();
        }
        JPEG_LOG.info("AC Tables:\n", .{});
        for (0.., self.huffman_act_tables) |i, table| {
            JPEG_LOG.info("Table ID: {d}\n", .{i});
            table.print();
        }
    }
    fn generate_huffman_codes(_: *JPEGImage, h_table: *HuffmanTable) void {
        var code: u32 = 0;
        for (0..h_table.offsets.len - 1) |i| {
            for (h_table.offsets[i]..h_table.offsets[i + 1]) |j| {
                h_table.codes[j] = code;
                code += 1;
            }
            code <<= 1;
        }
    }
    fn decode_huffman_data(self: *JPEGImage, bit_reader: *utils.BitReader) Error!void {
        JPEG_LOG.info("{d} {d} real {d} {d}\n", .{ self.block_width, self.block_height, self.block_width_real, self.block_height_real });

        var previous_dcs: [3]i32 = [_]i32{0} ** 3;
        var skips: u32 = 0;
        var y: usize = 0;
        var x: usize = 0;

        const luminance_only: bool = self.components_in_scan == 1 and self.color_components[0].used_in_scan;
        const y_step: u32 = if (luminance_only) 1 else self.vertical_sampling_factor;
        const x_step: u32 = if (luminance_only) 1 else self.horizontal_sampling_factor;
        const restart_interval: u32 = self.restart_interval * x_step * y_step;

        while (y < self.block_height) : (y += y_step) {
            while (x < self.block_width) : (x += x_step) {
                if (restart_interval != 0 and (y * self.block_width_real + x) % restart_interval == 0) {
                    previous_dcs[0] = 0;
                    previous_dcs[1] = 0;
                    previous_dcs[2] = 0;
                    skips = 0;
                    bit_reader.align_reader();
                }
                for (0..self.num_components) |j| {
                    if (self.color_components[j].used_in_scan) {
                        const v_max: u32 = if (luminance_only) 1 else self.color_components[j].vertical_sampling_factor;
                        const h_max: u32 = if (luminance_only) 1 else self.color_components[j].horizontal_sampling_factor;
                        for (0..v_max) |v| {
                            for (0..h_max) |h| {
                                try decode_block_component(self, bit_reader, self.blocks[(y + v) * self.block_width_real + (x + h)].get(j), &previous_dcs[j], &skips, &self.huffman_dct_tables[self.color_components[j].huffman_dct_table_id], &self.huffman_act_tables[self.color_components[j].huffman_act_table_id]);
                            }
                        }
                    }
                }
            }
            x = 0;
        }
    }
    fn get_next_symbol(_: *JPEGImage, bit_reader: *utils.BitReader, h_table: *HuffmanTable) Error!u8 {
        var current_code: i32 = 0;
        for (0..h_table.offsets.len - 1) |i| {
            const bit: i32 = @as(i32, @bitCast(try bit_reader.read_bit()));
            current_code = (current_code << 1) | bit;
            for (h_table.offsets[i]..h_table.offsets[i + 1]) |j| {
                if (current_code == h_table.codes[j]) {
                    return h_table.symbols[j];
                }
            }
        }
        return Error.HuffmanDecoding;
    }
    fn decode_block_component(self: *JPEGImage, bit_reader: *utils.BitReader, color_channel: []i32, previous_dc: *i32, skips: *u32, dct_table: *HuffmanTable, act_table: *HuffmanTable) Error!void {
        if (self.frame_type == JPEG_HEADERS.SOF0) {
            const length: u8 = try get_next_symbol(self, bit_reader, dct_table);
            if (length > 11) {
                return Error.HuffmanDecoding;
            }
            var coeff: i32 = @as(i32, @bitCast(try bit_reader.read_bits(length)));
            if (length != 0 and coeff < (@as(i32, 1) << @as(u5, @intCast(length - 1)))) {
                coeff -= (@as(i32, 1) << @as(u5, @intCast(length))) - 1;
            }
            color_channel[0] = coeff + previous_dc.*;
            previous_dc.* = color_channel[0];

            var i: u32 = 1;
            while (i < color_channel.len) {
                const symbol: u8 = try self.get_next_symbol(bit_reader, act_table);
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
                //JPEG_LOG.info("{d} {d} {d}\n", .{ num_zeroes, i + num_zeroes, color_channel.len });
                if (i + num_zeroes >= color_channel.len) {
                    return Error.HuffmanDecoding;
                }

                for (0..num_zeroes) |_| {
                    color_channel[zig_zag_map[i]] = 0;
                    i += 1;
                }

                if (coeff_length > 10) {
                    return Error.HuffmanDecoding;
                }

                if (coeff_length != 0) {
                    coeff = @as(i32, @bitCast(try bit_reader.read_bits(coeff_length)));
                    if (coeff < (@as(i32, 1) << @as(u5, @intCast(coeff_length - 1)))) {
                        coeff -= (@as(i32, 1) << @as(u5, @intCast(coeff_length))) - 1;
                    }
                    color_channel[zig_zag_map[i]] = coeff;
                    i += 1;
                }
            }
        } else {
            // S0F2
            if (self.start_of_selection == 0 and self.succcessive_approximation_high == 0) {

                // dc first
                const length: u8 = try get_next_symbol(self, bit_reader, dct_table);
                if (length > 11) {
                    return Error.HuffmanDecoding;
                }
                var coeff: i32 = @as(i32, @bitCast(try bit_reader.read_bits(length)));
                if (length != 0 and coeff < (@as(i32, 1) << @as(u5, @intCast(length - 1)))) {
                    coeff -= (@as(i32, 1) << @as(u5, @intCast(length))) - 1;
                }
                coeff += previous_dc.*;
                previous_dc.* = coeff;
                color_channel[0] = @as(i32, coeff) << @as(u5, @intCast(self.succcessive_approximation_low));
            } else if (self.start_of_selection == 0 and self.succcessive_approximation_high != 0) {
                // dc refinement
                const bit: i32 = @bitCast(try bit_reader.read_bit());
                color_channel[0] |= bit << @as(u5, @intCast(self.succcessive_approximation_low));
            } else if (self.start_of_selection != 0 and self.succcessive_approximation_high == 0) {
                // ac first
                if (skips.* > 0) {
                    skips.* -= 1;
                    return;
                }
                var i: usize = self.start_of_selection;
                while (i <= self.end_of_selection) {
                    const symbol: u8 = try self.get_next_symbol(bit_reader, act_table);
                    const num_zeroes: u8 = symbol >> 4;
                    const coeff_length: u8 = symbol & 0x0F;
                    if (coeff_length != 0) {
                        //JPEG_LOG.info("{d} {d} {d}\n", .{ num_zeroes, i + num_zeroes, color_channel.len });
                        if (i + num_zeroes > self.end_of_selection) {
                            return Error.HuffmanDecoding;
                        }

                        for (0..num_zeroes) |_| {
                            color_channel[zig_zag_map[i]] = 0;
                            i += 1;
                        }

                        if (coeff_length > 10) {
                            return Error.HuffmanDecoding;
                        }
                        var coeff = @as(i32, @bitCast(try bit_reader.read_bits(coeff_length)));
                        if (coeff < (@as(i32, 1) << @as(u5, @intCast(coeff_length - 1)))) {
                            coeff -= (@as(i32, 1) << @as(u5, @intCast(coeff_length))) - 1;
                        }
                        color_channel[zig_zag_map[i]] = coeff << @as(u5, @intCast(self.succcessive_approximation_low));
                    } else {
                        //JPEG_LOG.info("num zeroes = {d}\n", .{num_zeroes});
                        if (num_zeroes == 15) {
                            if (i + num_zeroes > self.end_of_selection) {
                                return Error.HuffmanDecoding;
                            }
                            for (0..num_zeroes) |_| {
                                color_channel[zig_zag_map[i]] = 0;
                                i += 1;
                            }
                        } else {
                            skips.* = (@as(u32, 1) << @as(u5, @intCast(num_zeroes))) - 1;
                            skips.* += try bit_reader.read_bits(num_zeroes);
                            break;
                        }
                    }
                    i += 1;
                }
            } else if (self.start_of_selection != 0 and self.succcessive_approximation_high != 0) {
                // ac refinement
                const positive: i32 = (@as(i32, 1) << @as(u5, @intCast(self.succcessive_approximation_low)));
                var negative: i32 = -1;
                negative = @as(i32, @bitCast(@as(u32, @bitCast(negative)) << @as(u5, @intCast(self.succcessive_approximation_low))));
                //JPEG_LOG.info("pos {x} neg {x}\n", .{ positive, negative });
                var i: usize = self.start_of_selection;
                if (skips.* == 0) {
                    while (i <= self.end_of_selection) {
                        const symbol: u8 = try self.get_next_symbol(bit_reader, act_table);
                        var num_zeroes: u8 = symbol >> 4;
                        const coeff_length: u8 = symbol & 0x0F;
                        var coeff: i32 = 0;

                        if (coeff_length != 0) {
                            switch (try bit_reader.read_bit()) {
                                1 => coeff = positive,
                                0 => coeff = negative,
                                else => unreachable,
                            }
                        } else {
                            if (num_zeroes != 15) {
                                skips.* = (@as(u32, 1) << @as(u5, @intCast(num_zeroes)));
                                skips.* += try bit_reader.read_bits(num_zeroes);
                                break;
                            }
                        }
                        while (i <= self.end_of_selection) {
                            if (color_channel[zig_zag_map[i]] != 0) {
                                switch (try bit_reader.read_bit()) {
                                    1 => {
                                        if ((color_channel[zig_zag_map[i]] & positive) == 0) {
                                            if (color_channel[zig_zag_map[i]] >= 0) {
                                                color_channel[zig_zag_map[i]] += positive;
                                            } else {
                                                color_channel[zig_zag_map[i]] += negative;
                                            }
                                        }
                                    },
                                    0 => {},
                                    else => unreachable,
                                }
                            } else {
                                if (num_zeroes == 0) {
                                    break;
                                }
                                num_zeroes -= 1;
                            }
                            i += 1;
                        }
                        if (coeff != 0 and i <= self.end_of_selection) {
                            color_channel[zig_zag_map[i]] = coeff;
                        }

                        i += 1;
                    }
                }
                if (skips.* > 0) {
                    while (i <= self.end_of_selection) {
                        if (color_channel[zig_zag_map[i]] != 0) {
                            switch (try bit_reader.read_bit()) {
                                1 => {
                                    if ((color_channel[zig_zag_map[i]] & positive) == 0) {
                                        if (color_channel[zig_zag_map[i]] >= 0) {
                                            color_channel[zig_zag_map[i]] += positive;
                                        } else {
                                            color_channel[zig_zag_map[i]] += negative;
                                        }
                                    }
                                },
                                0 => {},
                                else => unreachable,
                            }
                        }
                        i += 1;
                    }
                    skips.* -= 1;
                }
            }
        }
    }
    fn de_quant_data(self: *JPEGImage, start: usize, block_height: u32) Error!void {
        var y: usize = start;
        var x: usize = 0;
        //JPEG_LOG.info("sampling factor {d} {d}\n", .{ self.vertical_sampling_factor, self.horizontal_sampling_factor });
        while (y < block_height) : (y += self.vertical_sampling_factor) {
            while (x < self.block_width) : (x += self.horizontal_sampling_factor) {
                for (0..self.num_components) |j| {
                    for (0..self.color_components[j].vertical_sampling_factor) |v| {
                        for (0..self.color_components[j].horizontal_sampling_factor) |h| {
                            for (0..64) |k| {
                                //JPEG_LOG.info("multiplying {d} and {d} at ({d},{d},{d},{d})\n", .{ self._blocks[(y + v) * self._block_width_real + (x + h)].get(j)[k], self._quantization_tables[self._color_components[j].quantization_table_id].table[k], y, x, j, k });
                                self.blocks[(y + v) * self.block_width_real + (x + h)].get(j)[k] *= self.quantization_tables[self.color_components[j].quantization_table_id].table[k];
                            }
                        }
                    }
                }
            }
            x = 0;
        }
    }
    // inverse dct based on AAN
    fn inverse_dct_component(_: *JPEGImage, block: *[64]i32) void {
        var intermediate: [64]f64 = [_]f64{0} ** 64;
        for (0..8) |i| {
            const g0: f64 = @as(f64, @floatFromInt(block[0 * 8 + i])) * IDCT_SCALING_FACTORS.s0;
            const g1: f64 = @as(f64, @floatFromInt(block[4 * 8 + i])) * IDCT_SCALING_FACTORS.s4;
            const g2: f64 = @as(f64, @floatFromInt(block[2 * 8 + i])) * IDCT_SCALING_FACTORS.s2;
            const g3: f64 = @as(f64, @floatFromInt(block[6 * 8 + i])) * IDCT_SCALING_FACTORS.s6;
            const g4: f64 = @as(f64, @floatFromInt(block[5 * 8 + i])) * IDCT_SCALING_FACTORS.s5;
            const g5: f64 = @as(f64, @floatFromInt(block[1 * 8 + i])) * IDCT_SCALING_FACTORS.s1;
            const g6: f64 = @as(f64, @floatFromInt(block[7 * 8 + i])) * IDCT_SCALING_FACTORS.s7;
            const g7: f64 = @as(f64, @floatFromInt(block[3 * 8 + i])) * IDCT_SCALING_FACTORS.s3;

            const f0: f64 = g0;
            const f1: f64 = g1;
            const f2: f64 = g2;
            const f3: f64 = g3;
            const f4: f64 = g4 - g7;
            const f5: f64 = g5 + g6;
            const f6: f64 = g5 - g6;
            const f7: f64 = g4 + g7;

            const e0: f64 = f0;
            const e1: f64 = f1;
            const e2: f64 = f2 - f3;
            const e3: f64 = f2 + f3;
            const e4: f64 = f4;
            const e5: f64 = f5 - f7;
            const e6: f64 = f6;
            const e7: f64 = f5 + f7;
            const e8: f64 = f4 + f6;

            const d0: f64 = e0;
            const d1: f64 = e1;
            const d2: f64 = e2 * IDCT_SCALING_FACTORS.m1;
            const d3: f64 = e3;
            const d4: f64 = e4 * IDCT_SCALING_FACTORS.m2;
            const d5: f64 = e5 * IDCT_SCALING_FACTORS.m3;
            const d6: f64 = e6 * IDCT_SCALING_FACTORS.m4;
            const d7: f64 = e7;
            const d8: f64 = e8 * IDCT_SCALING_FACTORS.m5;

            const c0: f64 = d0 + d1;
            const c1: f64 = d0 - d1;
            const c2: f64 = d2 - d3;
            const c3: f64 = d3;
            const c4: f64 = d4 + d8;
            const c5: f64 = d5 + d7;
            const c6: f64 = d6 - d8;
            const c7: f64 = d7;
            const c8: f64 = c5 - c6;

            const b0: f64 = c0 + c3;
            const b1: f64 = c1 + c2;
            const b2: f64 = c1 - c2;
            const b3: f64 = c0 - c3;
            const b4: f64 = c4 - c8;
            const b5: f64 = c8;
            const b6: f64 = c6 - c7;
            const b7: f64 = c7;

            intermediate[0 * 8 + i] = b0 + b7;
            intermediate[1 * 8 + i] = b1 + b6;
            intermediate[2 * 8 + i] = b2 + b5;
            intermediate[3 * 8 + i] = b3 + b4;
            intermediate[4 * 8 + i] = b3 - b4;
            intermediate[5 * 8 + i] = b2 - b5;
            intermediate[6 * 8 + i] = b1 - b6;
            intermediate[7 * 8 + i] = b0 - b7;
        }

        for (0..8) |i| {
            const g0: f64 = intermediate[i * 8 + 0] * IDCT_SCALING_FACTORS.s0;
            const g1: f64 = intermediate[i * 8 + 4] * IDCT_SCALING_FACTORS.s4;
            const g2: f64 = intermediate[i * 8 + 2] * IDCT_SCALING_FACTORS.s2;
            const g3: f64 = intermediate[i * 8 + 6] * IDCT_SCALING_FACTORS.s6;
            const g4: f64 = intermediate[i * 8 + 5] * IDCT_SCALING_FACTORS.s5;
            const g5: f64 = intermediate[i * 8 + 1] * IDCT_SCALING_FACTORS.s1;
            const g6: f64 = intermediate[i * 8 + 7] * IDCT_SCALING_FACTORS.s7;
            const g7: f64 = intermediate[i * 8 + 3] * IDCT_SCALING_FACTORS.s3;

            const f0: f64 = g0;
            const f1: f64 = g1;
            const f2: f64 = g2;
            const f3: f64 = g3;
            const f4: f64 = g4 - g7;
            const f5: f64 = g5 + g6;
            const f6: f64 = g5 - g6;
            const f7: f64 = g4 + g7;

            const e0: f64 = f0;
            const e1: f64 = f1;
            const e2: f64 = f2 - f3;
            const e3: f64 = f2 + f3;
            const e4: f64 = f4;
            const e5: f64 = f5 - f7;
            const e6: f64 = f6;
            const e7: f64 = f5 + f7;
            const e8: f64 = f4 + f6;

            const d0: f64 = e0;
            const d1: f64 = e1;
            const d2: f64 = e2 * IDCT_SCALING_FACTORS.m1;
            const d3: f64 = e3;
            const d4: f64 = e4 * IDCT_SCALING_FACTORS.m2;
            const d5: f64 = e5 * IDCT_SCALING_FACTORS.m3;
            const d6: f64 = e6 * IDCT_SCALING_FACTORS.m4;
            const d7: f64 = e7;
            const d8: f64 = e8 * IDCT_SCALING_FACTORS.m5;

            const c0: f64 = d0 + d1;
            const c1: f64 = d0 - d1;
            const c2: f64 = d2 - d3;
            const c3: f64 = d3;
            const c4: f64 = d4 + d8;
            const c5: f64 = d5 + d7;
            const c6: f64 = d6 - d8;
            const c7: f64 = d7;
            const c8: f64 = c5 - c6;

            const b0: f64 = c0 + c3;
            const b1: f64 = c1 + c2;
            const b2: f64 = c1 - c2;
            const b3: f64 = c0 - c3;
            const b4: f64 = c4 - c8;
            const b5: f64 = c8;
            const b6: f64 = c6 - c7;
            const b7: f64 = c7;

            block[i * 8 + 0] = @as(i32, @intFromFloat(b0 + b7 + 0.5));
            block[i * 8 + 1] = @as(i32, @intFromFloat(b1 + b6 + 0.5));
            block[i * 8 + 2] = @as(i32, @intFromFloat(b2 + b5 + 0.5));
            block[i * 8 + 3] = @as(i32, @intFromFloat(b3 + b4 + 0.5));
            block[i * 8 + 4] = @as(i32, @intFromFloat(b3 - b4 + 0.5));
            block[i * 8 + 5] = @as(i32, @intFromFloat(b2 - b5 + 0.5));
            block[i * 8 + 6] = @as(i32, @intFromFloat(b1 - b6 + 0.5));
            block[i * 8 + 7] = @as(i32, @intFromFloat(b0 - b7 + 0.5));
        }
    }
    fn inverse_dct(self: *JPEGImage, start: usize, block_height: u32) void {
        var y: usize = start;
        var x: usize = 0;
        while (y < block_height) : (y += self.vertical_sampling_factor) {
            while (x < self.block_width) : (x += self.horizontal_sampling_factor) {
                for (0..self.num_components) |j| {
                    for (0..self.color_components[j].vertical_sampling_factor) |v| {
                        for (0..self.color_components[j].horizontal_sampling_factor) |h| {
                            self.inverse_dct_component(self.blocks[(y + v) * self.block_width_real + (x + h)].get(j));
                        }
                    }
                }
            }
            x = 0;
        }
    }
    fn ycb_rgb_block(self: *JPEGImage, block: *Block(i32), cbcr: *Block(i32), v: usize, h: usize) void {
        var y: usize = 7;
        var x: usize = 7;
        while (y >= 0) : (y -= 1) {
            while (x >= 0) : (x -= 1) {
                const pixel: usize = y * 8 + x;
                const cbcr_pixel_row: usize = (y / self.vertical_sampling_factor) + 4 * v;
                const cbcr_pixel_col: usize = (x / self.horizontal_sampling_factor) + 4 * h;
                const cbcr_pixel = cbcr_pixel_row * 8 + cbcr_pixel_col;
                var r: f64 = @as(f64, @floatFromInt(block.y[pixel])) + 1.402 * @as(f64, @floatFromInt(cbcr.cr[cbcr_pixel])) + 128.0;
                var g: f64 = @as(f64, @floatFromInt(block.y[pixel])) - 0.344 * @as(f64, @floatFromInt(cbcr.cb[cbcr_pixel])) - 0.714 * @as(f64, @floatFromInt(cbcr.cr[cbcr_pixel])) + 128.0;
                var b: f64 = @as(f64, @floatFromInt(block.y[pixel])) + 1.722 * @as(f64, @floatFromInt(cbcr.cb[cbcr_pixel])) + 128.0;
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
                block.r[pixel] = @as(i32, @intFromFloat(r));
                block.g[pixel] = @as(i32, @intFromFloat(g));
                block.b[pixel] = @as(i32, @intFromFloat(b));
                if (x == 0) break;
            }
            x = 7;
            if (y == 0) break;
        }
    }
    fn ycb_rgb(self: *JPEGImage, start: usize, block_height: u32) void {
        var y: usize = start;
        var x: usize = 0;
        while (y < block_height) : (y += self.vertical_sampling_factor) {
            while (x < self.block_width) : (x += self.horizontal_sampling_factor) {
                const cbcr: *Block(i32) = &self.blocks[y * self.block_width_real + x];
                var v: usize = self.vertical_sampling_factor - 1;
                var h: usize = self.horizontal_sampling_factor - 1;
                while (v < self.vertical_sampling_factor) : (v -= 1) {
                    while (h < self.horizontal_sampling_factor) : (h -= 1) {
                        const block: *Block(i32) = &self.blocks[(y + v) * self.block_width_real + (x + h)];
                        self.ycb_rgb_block(block, cbcr, v, h);
                        if (h == 0) break;
                    }
                    h = self.horizontal_sampling_factor - 1;
                    if (v == 0) break;
                }
            }
            x = 0;
        }
    }

    fn gen_rgb_data(self: *JPEGImage) Error!void {
        self.data = std.ArrayList(utils.Pixel).init(self.allocator);
        defer self.allocator.free(self.blocks);

        //JPEG_LOG.info("block height {d}\n", .{self._block_height});
        try utils.timer_start();
        var num_threads: usize = 10;
        while (num_threads > 0 and (self.block_height / num_threads) < num_threads) {
            num_threads -= 2;
        }
        //JPEG_LOG.info("running on {d} threads\n", .{num_threads});
        if (num_threads == 0) {
            // single thread
            try JPEGImage.thread_compute(self, 0, self.block_height);
        } else {
            // multi thread
            const data_split = if ((self.block_height / num_threads) % 2 == 1) (self.block_height / num_threads) + 1 else self.block_height / num_threads;
            //JPEG_LOG.info("data split {d} block_height {d}\n", .{ data_split, self._block_height });
            var threads: []std.Thread = try self.allocator.alloc(std.Thread, num_threads);
            for (0..num_threads) |i| {
                var end: u32 = @as(u32, @intCast((i + 1) * data_split));
                if (end > self.block_height or i == num_threads - 1) {
                    end = self.block_height;
                }
                //JPEG_LOG.info("start {d} end {d}\n", .{ i * data_split, end });
                threads[i] = try std.Thread.spawn(.{}, JPEGImage.thread_compute, .{
                    self,
                    i * data_split,
                    end,
                });
            }
            for (threads) |thread| {
                thread.join();
            }
            self.allocator.free(threads);
        }

        utils.timer_end();

        // store color data to be used later in either writing to another file or direct access in code
        var i: usize = 0;
        while (i < self.height) {
            const block_row: u32 = @as(u32, @intCast(i)) / 8;
            const pixel_row: u32 = @as(u32, @intCast(i)) % 8;
            for (0..self.width) |j| {
                const block_col: u32 = @as(u32, @intCast(j)) / 8;
                const pixel_col: u32 = @as(u32, @intCast(j)) % 8;
                const block_index = block_row * self.block_width_real + block_col;
                //JPEG_LOG.info("writing index {d}\n", .{block_index});
                const pixel_index = pixel_row * 8 + pixel_col;
                //JPEG_LOG.info("pixel ({d}) ({d}) ({d})\n", .{ blocks[block_index].r[pixel_index], blocks[block_index].g[pixel_index], blocks[block_index].b[pixel_index] });
                try self.data.append(utils.Pixel.init(
                    @truncate(@as(u32, @bitCast(self.blocks[block_index].r[pixel_index]))),
                    @truncate(@as(u32, @bitCast(self.blocks[block_index].g[pixel_index]))),
                    @truncate(@as(u32, @bitCast(self.blocks[block_index].b[pixel_index]))),
                    null,
                ));
            }
            i += 1;
        }
        JPEG_LOG.info("number of pixels {d}\n", .{self.data.items.len});
    }
    pub fn convert_grayscale(self: *JPEGImage) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().grayscale();
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
            self.grayscale = true;
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn reflection(self: *JPEGImage, comptime axis: @Type(.EnumLiteral)) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().reflection(axis);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn edge_detection(self: *JPEGImage) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().edge_detection();
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn rotate(self: *JPEGImage, degrees: f64) Error!void {
        if (self.loaded) {
            var core = self.image_core();
            const data = try core.rotate(degrees);
            const data_copy = data.data;
            self.width = data.width;
            self.height = data.height;
            defer self.allocator.free(data_copy);
            self.data.clearRetainingCapacity();
            for (0..data_copy.len) |i| {
                try self.data.append(data_copy[i]);
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn histogram_equalization(self: *JPEGImage) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().histogram_equalization();
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn shear(self: *JPEGImage, c_x: f64, c_y: f64) Error!void {
        if (self.loaded) {
            var core = self.image_core();
            const data = try core.shear(c_x, c_y);
            const data_copy = data.data;
            self.width = data.width;
            self.height = data.height;
            defer self.allocator.free(data_copy);
            self.data.clearRetainingCapacity();
            for (0..data_copy.len) |i| {
                try self.data.append(data_copy[i]);
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn convol(self: *JPEGImage, kernel: ConvolMat) Error!void {
        if (self.loaded) {
            const data_copy = try self.image_core().convol(kernel);
            defer self.allocator.free(data_copy);
            for (0..self.data.items.len) |i| {
                self.data.items[i].v = data_copy[i].v;
            }
        } else {
            return Error.NotLoaded;
        }
    }

    pub fn image_core(self: *JPEGImage) ImageCore {
        return ImageCore.init(self.allocator, self.width, self.height, self.data.items);
    }
    pub fn write_BMP(self: *JPEGImage, file_name: []const u8) Error!void {
        if (!self.loaded) {
            return Error.NotLoaded;
        }
        try self.image_core().write_BMP(file_name);
    }
    pub fn get(self: *const JPEGImage, x: usize, y: usize) *utils.Pixel {
        return &self.data.items[y * self.width + x];
    }
    pub fn load(self: *JPEGImage, file_name: []const u8, allocator: std.mem.Allocator) Error!void {
        var bit_reader: utils.BitReader = try utils.BitReader.init(.{ .file_name = file_name, .allocator = allocator, .jpeg_filter = true });
        self.allocator = allocator;
        try self.read_JPEG(&bit_reader);
        JPEG_LOG.info("finished reading jpeg\n", .{});
        try self.gen_rgb_data();
        JPEG_LOG.info("finished processing jpeg\n", .{});
        self.loaded = true;
        bit_reader.deinit();
    }
};

test "CAT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.convert_grayscale();
    try image.write_BMP("test_output/cat.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.info("Leaked!\n", .{});
    }
}

test "HISTOGRAM EQUALIZATION" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.histogram_equalization();
    try image.write_BMP("test_output/cat_histogram_equal_jpeg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "EDGE DETECTION" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.edge_detection();
    try image.write_BMP("test_output/cat_edge_detection_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "SHEAR" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.shear(0.5, 0);
    try image.write_BMP("test_output/cat_shear_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "ROTATE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.rotate(45);
    try image.write_BMP("test_output/cat_rotate_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "CAT_REFLECT_X" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.reflection(.x);
    try image.write_BMP("test_output/cat_reflectx_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.info("Leaked!\n", .{});
    }
}

test "CAT_REFLECT_Y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.reflection(.y);
    try image.write_BMP("test_output/cat_reflecty_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.info("Leaked!\n", .{});
    }
}

test "CAT_REFLECT_XY" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/cat.jpg", allocator);
    try image.reflection(.xy);
    try image.write_BMP("test_output/cat_reflectxy_jpg.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.info("Leaked!\n", .{});
    }
}

test "GORILLA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/gorilla.jpg", allocator);
    try image.write_BMP("test_output/gorilla.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "FISH2_1V" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/sub/goldfish_2to1V.jpg", allocator);
    try image.write_BMP("test_output/goldfish_2to1V.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "FISH2_1H" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/sub/goldfish_2to1H.jpg", allocator);
    try image.write_BMP("test_output/goldfish_2to1H.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "FISH2_1" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/sub/goldfish_2to1.jpg", allocator);
    try image.write_BMP("test_output/goldfish_2to1.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/test.jpg", allocator);
    try image.write_BMP("test_output/test.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "PARROT" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/prog/parrot.jpg", allocator);
    try image.write_BMP("test_output/parrot.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "EARTH" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/prog/earth.jpg", allocator);
    try image.write_BMP("test_output/earth.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "PENGUIN" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/prog/sub/penguin.jpg", allocator);
    try image.write_BMP("test_output/penguin.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "SLOTH" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/prog/sub/sloth.jpg", allocator);
    try image.write_BMP("test_output/sloth.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "TIGER" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = JPEGImage{};
    try image.load("tests/jpeg/prog/sub/tiger.jpg", allocator);
    try image.write_BMP("test_output/tiger.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        JPEG_LOG.warn("Leaked!\n", .{});
    }
}

test "block" {
    var block: Block(i32) = Block(i32){};
    block.init();
    block.r[1] = 5;
    try std.testing.expect(block.r[1] == 5 and block.y[1] == 5);
}
