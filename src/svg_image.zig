const std = @import("std");
const common = @import("common");
const image_core = @import("image_core.zig");
const _image = @import("image.zig");

pub const Image = _image.Image;
const SVG_LOG = std.log.scoped(.svg_image);

const IMPLEMENTED = false;
//https://www.w3.org/Graphics/SVG/About.html
//https://www.w3.org/TR/SVG11/intro.html
//https://www.w3.org/TR/SVGTiny12/intro.html#howtoreference
//https://www.w3.org/TR/SVGTiny12/intro.html#howtoreference
//https://www.w3.org/TR/SVGTiny12/intro.html#howtoreference
//https://www.geeksforgeeks.org/compiler-design/why-first-and-follow-in-compiler-design/
//https://www.geeksforgeeks.org/compiler-design/construction-of-ll1-parsing-table/

pub const SVGBuilder = struct {
    file_data: common.ByteStream = undefined,
    allocator: std.mem.Allocator = undefined,
    loaded: bool = false,
    data: std.ArrayList(common.Pixel) = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    grayscale: bool = false,
    tree: *Tag = undefined,
    version: *Tag = undefined,
    pub const Error = error{ InvalidFormat, NotLoaded, NotImplmented } || common.BitReader.Error || std.mem.Allocator.Error || image_core.Error;

    pub const Tokenizer = struct {
        first: TerminalList,
        follow: TerminalList,
        pub const Grammar = [_][]u8{
            "S -> Element",
            "Element -> OTagContentCTag",
            "OTag -> <Properties>",
            "CTag -> </Properties>",
            "Properties -> ε",
            "Content -> ε | Element",
        };
        pub const TerminalList = std.ArrayList(u8);
    };

    //TODO lets start simple, build the parser in a straight forward manner without the formulation
    pub const Tag = struct {
        name: []u8,
        properties: Properties,
        parent: ?*Tag,
        children: std.ArrayList(*Tag),
        closed: bool,
        closing_tag: bool,
        value: []u8,
        pub const Properties = common.StringKeyMap([]const u8);
        pub fn print(self: *const Tag) void {
            std.debug.print("<{s}", .{self.name});
            var iter = self.properties.iterator();
            while (iter.next()) |e| {
                std.debug.print(" {s}={s}", .{ e.key_ptr.*, e.value_ptr.* });
            }
            if (self.closing_tag) {
                std.debug.print(">\n", .{});
                if (self.value.len > 0) {
                    std.debug.print("{s}", .{self.value});
                } else {
                    for (0..self.children.items.len) |i| {
                        self.children.items[i].print();
                    }
                }
                std.debug.print("</{s}>", .{self.name});
            } else {
                std.debug.print("/>\n", .{});
            }
        }
        pub fn deinit(self: *Tag) void {
            self.properties.deinit();
            for (0..self.children.items.len) |i| {
                self.children.items[i].deinit();
            }
            self.children.deinit();
        }
    };

    pub fn load(self: *SVGBuilder, file_name: []const u8, allocator: std.mem.Allocator) Error!Image {
        if (IMPLEMENTED) return Error.NotImplmented;
        self.allocator = allocator;
        self.file_data = try common.ByteStream.init(.{ .file_name = file_name, .allocator = self.allocator });
        SVG_LOG.info("reading svg\n", .{});
        //TODO PARSE SVG
        try self.parse();
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

    fn find_opening(self: *SVGBuilder) Error!bool {
        while (try self.file_data.peek() != '<' and self.file_data.getPos() != self.file_data.getEndPos()) {
            _ = try self.file_data.readByte();
        }
        return self.file_data.getPos() != self.file_data.getEndPos();
    }

    fn find_ending(self: *SVGBuilder) Error!bool {
        while (try self.file_data.peek() != '>' and self.file_data.getPos() != self.file_data.getEndPos()) {
            _ = try self.file_data.readByte();
        }
        return self.file_data.getPos() != self.file_data.getEndPos();
    }

    fn handle_inner(_: *SVGBuilder, curr_tag: *Tag, start: usize, end: usize) Error!void {
        _ = curr_tag;
        _ = start;
        _ = end;
        //TODO check char at end+1 for /, if / done else handle child
    }

    fn handle_tag(self: *SVGBuilder, curr_tag: *Tag, start: usize, end: usize) Error!void {
        std.debug.print("Tag to parse {s}\n", .{self.file_data.buffer[start..end]});
        self.file_data.index = start + 1;
        //metadata tag
        if (try self.file_data.peek() == '?') {
            _ = try self.file_data.readByte();
        } else if (try self.file_data.peek() == '/') {
            curr_tag.closed = true;
            return;
        }
        const name_start = self.file_data.index;
        while (try self.file_data.peek() != ' ') _ = try self.file_data.readByte();
        const name_end = self.file_data.index;
        curr_tag.name = self.file_data.buffer[name_start..name_end];
        std.debug.print("Tag name {s}\n", .{curr_tag.name});
        while (try self.file_data.peek() == ' ') _ = try self.file_data.readByte();
        while (self.file_data.index < end and try self.file_data.peek() != '?' and self.file_data.getPos() != self.file_data.getEndPos()) {
            while (try self.file_data.peek() == ' ') _ = try self.file_data.readByte();
            var property_start: usize = self.file_data.index;
            //std.debug.print("Current byte {c} Looking for equal\n", .{self.file_data.buffer[property_start]});
            while (try self.file_data.peek() != '=') _ = try self.file_data.readByte();
            const eql = self.file_data.index;
            //std.debug.print("Current indx {d}, equal indx {d}, {c}\n", .{ property_start, eql, self.file_data.buffer[eql] });
            const property_name = self.file_data.buffer[property_start..eql];
            std.debug.print("Property name {s}\n", .{property_name});
            while (try self.file_data.peek() != '"') _ = try self.file_data.readByte();
            property_start = self.file_data.index + 1;
            _ = try self.file_data.readByte();
            while (try self.file_data.peek() != '"') _ = try self.file_data.readByte();
            const quote = self.file_data.index;
            _ = try self.file_data.readByte();
            const property_value = self.file_data.buffer[property_start..quote];
            std.debug.print("Property value {s}\n", .{property_value});
            try curr_tag.properties.put(property_name, property_value);
            _ = try self.file_data.readByte();
        }
        if (self.file_data.buffer[end - 1] == '/') curr_tag.closing_tag = false;
        self.file_data.index = end;
    }

    fn parse(self: *SVGBuilder) Error!void {
        self.version = try self.allocator.create(Tag);
        self.version.* = Tag{
            .name = "",
            .properties = Tag.Properties.init(self.allocator),
            .parent = null,
            .children = std.ArrayList(*Tag).init(self.allocator),
            .closed = true,
            .value = "",
            .closing_tag = false,
        };
        if (!try self.find_opening()) return Error.InvalidFormat;
        var start = self.file_data.index + 1;
        if (!try self.find_ending()) return Error.InvalidFormat;
        var end = self.file_data.index;
        try self.handle_tag(self.version, start, end);

        self.tree = try self.allocator.create(Tag);
        self.tree.* = Tag{
            .name = "",
            .properties = Tag.Properties.init(self.allocator),
            .parent = null,
            .children = std.ArrayList(*Tag).init(self.allocator),
            .closed = false,
            .value = "",
            .closing_tag = true,
        };
        if (!try self.find_opening()) return Error.InvalidFormat;
        start = self.file_data.index + 1;
        if (!try self.find_ending()) return Error.InvalidFormat;
        end = self.file_data.index;
        try self.handle_tag(self.tree, start, end);
        self.print();

        start = end + 1;
        if (!try self.find_opening()) return Error.InvalidFormat;
        end = self.file_data.index;
        try self.handle_inner(self.tree, start, end);
        //self.print();

        start = end + 1;
        if (!try self.find_ending()) return Error.InvalidFormat;
        end = self.file_data.index;
        try self.handle_tag(self.tree, start, end);
        //self.print();
    }

    fn print(self: *SVGBuilder) void {
        std.debug.print("----------\n<?{s}", .{self.version.name});
        var iter = self.version.properties.iterator();
        while (iter.next()) |e| {
            std.debug.print(" {s}={s}", .{ e.key_ptr.*, e.value_ptr.* });
        }
        std.debug.print("?>\n", .{});
        self.tree.print();
        std.debug.print("----------\n", .{});
    }

    fn read_color_data(self: *SVGBuilder) Error!void {
        _ = self;
    }

    pub fn deinit(self: *SVGBuilder) void {
        self.file_data.deinit();
    }
};

test "SVG" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var image = try Image.init_load(allocator, "tests/svg/test.svg", .SVG);
    try image.write_BMP("test_output/svg_test.bmp");
    image.deinit();
    if (gpa.deinit() == .leak) {
        SVG_LOG.warn("Leaked!\n", .{});
    }
}
