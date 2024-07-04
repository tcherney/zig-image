//https://yasoob.me/posts/understanding-and-writing-jpeg-decoder-in-python/#jpeg-decoding
//https://www.youtube.com/watch?v=CPT4FSkFUgs&list=PLpsTn9TA_Q8VMDyOPrDKmSJYt1DLgDZU4

const std = @import("std");

const JPEG_HEADERS = enum(u8) {
    HEADER = 0xFF,
    SOI = 0xD8,
    EOI = 0xD9,
    DQT = 0xDB,
    SOF0 = 0xC0,
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
};

const JPEG_ERRORS = error{
    INVALID_HEADER,
    INVALID_DQT_ID,
    INVALID_DQT,
    CMYK_NOT_SUPPORTED,
    YIQ_NOT_SUPPORTED,
    INVALID_COMPONENT_ID,
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
    used: bool = false,
};

const Image = struct {
    data: ?std.ArrayList(u8) = null,
    _quantization_tables: [4]QuantizationTable = [_]QuantizationTable{.{}} ** 4,
    height: u32 = 0,
    width: u32 = 0,
    _frame_type: JPEG_HEADERS = JPEG_HEADERS.SOF0,
    _num_components: u8 = 0,
    _color_components: [3]ColorComponent = [_]ColorComponent{.{}} ** 3,
    pub fn _read_start_of_frame(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
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
            const component_id = buffer[index.* + 1];
            index.* += 1;
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
    pub fn _read_quant_table(self: *Image, buffer: []u8, index: *u32) JPEG_ERRORS!void {
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
    pub fn load_JPEG(self: *Image, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self.data = std.ArrayList(u8).init(allocator.*);
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
                    last = buffer[i + 1];
                    current = buffer[i + 2];
                    i += (@as(u16, last) << 8) + current + 1;
                    std.debug.print("Amount to skip {x} {x} {x}\n", .{ last, current, i });
                    last = buffer[i];
                    i += 1;
                    current = buffer[i];
                } else if (current == @intFromEnum(JPEG_HEADERS.DQT)) {
                    std.debug.print("Reading Quant table\n", .{});
                    std.debug.print("index {d}\n", .{i});
                    try self._read_quant_table(buffer, &i);
                    for (self._quantization_tables) |table| {
                        table.print();
                    }
                    last = buffer[i + 1];
                    current = buffer[i + 2];
                    i += 2;
                } else if (current == @intFromEnum(JPEG_HEADERS.EOI)) {
                    std.debug.print("End of image\n", .{});
                    break;
                } else if (current == @intFromEnum(JPEG_HEADERS.SOF0)) {
                    self._frame_type = JPEG_HEADERS.SOF0;
                    try self._read_start_of_frame(buffer, &i);
                    last = buffer[i + 1];
                    current = buffer[i + 2];
                    i += 2;
                } else if (current == @intFromEnum(JPEG_HEADERS.HEADER)) {
                    // allowed to have run of 0xFF
                    last = current;
                    i += 1;
                    current = buffer[i];
                } else {
                    return JPEG_ERRORS.INVALID_HEADER;
                }
            } else {
                //expected header
                return JPEG_ERRORS.INVALID_HEADER;
            }
        }
    }
    pub fn clean_up(self: *Image) void {
        std.ArrayList(u8).deinit(self.data.?);
    }
    pub fn print(self: *Image) void {
        if (self.data) |data| {
            for (data.items) |item| {
                std.debug.print("{x} ", .{item});
            }
            std.debug.print("\n", .{});
        }
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
