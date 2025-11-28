const std = @import("std");
const common = @import("common");
const image_core = @import("image_core.zig");
const _image = @import("image.zig");

pub const Image = _image.Image;
const SVG_LOG = std.log.scoped(.svg_image);

const IMPLEMENTED = false;

pub const SVGBuilder = struct {
    file_data: common.BitReader = undefined,
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    data: std.ArrayList(common.Pixel) = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    grayscale: bool = false,
    pub const Error = error{ NotLoaded, NotImplmented } || common.BitReader.Error || std.mem.Allocator.Error || image_core.Error;

    pub const Tokenizer = struct {
        first: TerminalList,
        follow: TerminalList,
        pub const Grammar = [_][]u8{
            "S -> <B>",
            "B -> ε",
        };
        pub const TerminalList = std.ArrayList(u8);
    };

    pub fn load(self: *SVGBuilder, file_name: []const u8, allocator: std.mem.Allocator) Error!Image {
        if (IMPLEMENTED) return Error.NotImplmented;
        self.allocator = allocator;
        self.file_data = try common.BitReader.init(.{ .file_name = file_name, .allocator = self.allocator, .little_endian = true });
        SVG_LOG.info("reading svg\n", .{});
        //TODO PARSE SVG
        self.parse();
        self.data = try std.ArrayList(common.Pixel).initCapacity(self.allocator, self.height * self.width);
        self.data.expandToCapacity();
        //TODO FILL IN DATA FROM PARSED SVG
        try self.read_color_data();
        self.loaded = true;
        return Image{
            .allocator = self.allocator,
            .data = self.data,
            .grayscale = self.grayscale,
            .height = self.height,
            .width = self.width,
            .loaded = true,
        };
    }

    fn parse(self: *SVGBuilder) Error!void {
        const xml = std.xml;
        const reader = try xml.Reader.init(self.allocator, "");
        _ = reader;
    }

    fn read_color_data(self: *SVGBuilder) Error!void {
        _ = self;
    }

    pub fn deinit(self: *SVGBuilder) void {
        self.file_data.deinit();
    }
};

// test "SVG" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     var image = try Image.init_load(allocator, "tests/svg/test.svg", .SVG);
//     try image.write_BMP("test_output/svg_test.bmp");
//     image.deinit();
//     if (gpa.deinit() == .leak) {
//         SVG_LOG.warn("Leaked!\n", .{});
//     }
// }
