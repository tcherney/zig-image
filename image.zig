//https://yasoob.me/posts/understanding-and-writing-jpeg-decoder-in-python/#jpeg-decoding
//https://www.youtube.com/watch?v=CPT4FSkFUgs&list=PLpsTn9TA_Q8VMDyOPrDKmSJYt1DLgDZU4

const std = @import("std");

const JPEG_HEADERS = enum(u16) {
    START_FILE = 0xFFD8,
    END_FILE = 0xFFD9,
    QUANT_TABLE = 0xFFDB,
    START_FRAME = 0xFFC0,
};

const Image = struct {
    data: ?std.ArrayList(u8) = null,
    pub fn loadJPEG(self: *Image, file_name: []const u8, allocator: *std.mem.Allocator) !void {
        self.data = std.ArrayList(u8).init(allocator.*);
        const image_file = try std.fs.cwd().openFile(file_name, .{});
        defer image_file.close();
        var buf_reader = std.io.bufferedReader(image_file.reader());
        var buffer: [2]u8 = undefined;
        while (try buf_reader.reader().read(&buffer) > 0) {
            var chunk: u16 = buffer[0];
            chunk <<= 8;
            chunk += buffer[1];
            try self.data.?.append(buffer[0]);
            try self.data.?.append(buffer[1]);
            switch (chunk) {
                @intFromEnum(JPEG_HEADERS.START_FILE) => std.debug.print("Start of image\n", .{}),
                @intFromEnum(JPEG_HEADERS.END_FILE) => {
                    std.debug.print("End of image\n", .{});
                    break;
                },
                else => {},
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
    try image.loadJPEG("test.jpg", &allocator);
    image.print();
    image.clean_up();
    if (gpa.deinit() == .leak) {
        std.debug.print("Leaked!", .{});
    }
}
