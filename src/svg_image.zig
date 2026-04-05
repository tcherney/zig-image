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
        pub fn print_tree(self: *const Tag) void {
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
                        self.children.items[i].print_tree();
                    }
                }
                std.debug.print("</{s}>", .{self.name});
            } else {
                std.debug.print("/>\n", .{});
            }
        }
        pub fn print(self: *const Tag) void {
            std.debug.print("Tag {s}\nProperties\n", .{self.name});
            var iter = self.properties.iterator();
            while (iter.next()) |e| {
                std.debug.print("   {s} = {s}\n", .{ e.key_ptr.*, e.value_ptr.* });
            }
            if (self.closing_tag) {
                if (self.value.len > 0) {
                    std.debug.print("Value\n   {s}\n", .{self.value});
                } else {
                    for (0..self.children.items.len) |i| {
                        self.children.items[i].print();
                    }
                }
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

    fn consume_whitespace(self: *SVGBuilder) Error!bool {
        var white_space = try self.file_data.peek();
        while ((white_space == ' ' or white_space == '\n' or white_space == '\r') and self.file_data.getPos() != self.file_data.getEndPos()) {
            _ = try self.file_data.readByte();
            white_space = try self.file_data.peek();
        }
        return self.file_data.getPos() != self.file_data.getEndPos();
    }

    fn consume(self: *SVGBuilder) Error!bool {
        var white_space = try self.file_data.peek();
        while ((white_space != ' ' and white_space != '\n' and white_space != '\r') and self.file_data.getPos() != self.file_data.getEndPos()) {
            _ = try self.file_data.readByte();
            white_space = try self.file_data.peek();
        }
        return self.file_data.getPos() != self.file_data.getEndPos();
    }

    fn handle_inner(self: *SVGBuilder, curr_tag: *Tag) Error!void {
        if (!try self.consume_whitespace()) return Error.InvalidFormat;
        if (try self.file_data.peek() != '<') {
            const value_start = self.file_data.index;
            while (try self.file_data.peek() != '<') _ = try self.file_data.readByte();
            curr_tag.value = self.file_data.buffer[value_start..self.file_data.index];
        } else {
            while (try self.file_data.peek() == '<') {
                if (self.file_data.buffer[self.file_data.index + 1] == '/') {
                    break;
                }
                const child = try self.allocator.create(Tag);
                child.* = Tag{
                    .name = "",
                    .properties = Tag.Properties.init(self.allocator),
                    .parent = curr_tag,
                    .children = std.ArrayList(*Tag).init(self.allocator),
                    .closed = false,
                    .value = "",
                    .closing_tag = true,
                };
                try curr_tag.children.append(child);
                try self.handle_tag(child);
                if (!try self.find_opening()) return Error.InvalidFormat;
            }
        }
    }

    fn handle_closing_tag(self: *SVGBuilder, curr_tag: *Tag) Error!void {
        if (!try self.find_opening()) return Error.InvalidFormat;
        _ = try self.file_data.readByte();
        if (try self.file_data.peek() == '/') {
            curr_tag.closed = true;
        }
        if (!try self.find_ending()) return Error.InvalidFormat;
        _ = try self.file_data.readByte();
    }

    fn handle_opening_tag(self: *SVGBuilder, curr_tag: *Tag) Error!void {
        if (!try self.find_opening()) return Error.InvalidFormat;
        _ = try self.file_data.readByte();
        //metadata tag
        if (try self.file_data.peek() == '?') {
            _ = try self.file_data.readByte();
        }
        if (!try self.consume_whitespace()) return Error.InvalidFormat;
        const name_start = self.file_data.index;
        if (!try self.consume()) return Error.InvalidFormat;
        const name_end = self.file_data.index;
        curr_tag.name = self.file_data.buffer[name_start..name_end];
        std.debug.print("Tag name {s} parent {s}\n", .{ curr_tag.name, if (curr_tag.parent != null) curr_tag.parent.?.name else "None" });
        if (!try self.consume_whitespace()) return Error.InvalidFormat;
        //std.debug.print("Curr byte {c}\n", .{try self.file_data.peek()});
        while (try self.file_data.peek() != '>' and try self.file_data.peek() != '?' and self.file_data.getPos() != self.file_data.getEndPos()) {
            if (!try self.consume_whitespace()) return Error.InvalidFormat;
            if (try self.file_data.peek() == '>' or try self.file_data.peek() == '/') break;
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
            //std.debug.print("Curr byte {c}\n", .{try self.file_data.peek()});
            if (!try self.consume_whitespace()) return Error.InvalidFormat;
            //std.debug.print("Curr byte {c}\n", .{try self.file_data.peek()});
        }
        //std.debug.print("Curr byte {c} Checking /\n", .{try self.file_data.peek()});
        if (try self.file_data.peek() == '/') {
            curr_tag.closing_tag = false;
            _ = try self.file_data.readByte();
        } else if (self.file_data.buffer[self.file_data.index - 1] == '/') {
            curr_tag.closing_tag = false;
        }
        _ = try self.file_data.readByte();
    }

    fn handle_tag(self: *SVGBuilder, curr_tag: *Tag) Error!void {
        try self.handle_opening_tag(curr_tag);
        if (curr_tag.closing_tag) {
            try self.handle_inner(curr_tag);
            try self.handle_closing_tag(curr_tag);
        }
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
        try self.handle_opening_tag(self.version);

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
        try self.handle_tag(self.tree);
        self.print();
    }

    fn print_tree(self: *SVGBuilder) void {
        std.debug.print("--------------------\n<?{s}", .{self.version.name});
        var iter = self.version.properties.iterator();
        while (iter.next()) |e| {
            std.debug.print(" {s}={s}", .{ e.key_ptr.*, e.value_ptr.* });
        }
        std.debug.print("?>\n", .{});
        self.tree.print_tree();
        std.debug.print("--------------------\n", .{});
    }

    fn print(self: *SVGBuilder) void {
        std.debug.print("--------------------\n{s}\nProperties\n", .{self.version.name});
        var iter = self.version.properties.iterator();
        while (iter.next()) |e| {
            std.debug.print("   {s} = {s}\n", .{ e.key_ptr.*, e.value_ptr.* });
        }
        self.tree.print();
        std.debug.print("--------------------\n", .{});
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
