const std = @import("std");
const utils = @import("utils.zig");
//TODO add inverse calculation to support solving systems of linear equations
pub fn Mat(comptime S: comptime_int, comptime T: type) type {
    return struct {
        data: [S * S]T = undefined,
        size: usize = S,
        pub const Self = @This();
        pub const Vec: type = @Vector(S, T);
        pub const Error = error{
            TransformationUndefined,
            ArgError,
        };
        pub fn init(data: [S * S]T) Self {
            return Self{
                .data = data,
            };
        }
        pub fn print(self: *const Self) void {
            std.log.debug("{any}\n", .{self.data});
            for (0..S) |i| {
                const v: Vec = self.data[i * S .. i * S + S][0..S].*;
                std.log.debug("{any}\n", .{v});
            }
        }
        pub fn scale(s: T) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = s;
            ret.data[1] = 0;
            ret.data[2] = 0;

            ret.data[S] = 0;
            ret.data[S + 1] = s;
            ret.data[S + 2] = 0;
            ret.fill_identity(2);
            return ret;
        }
        pub fn fill_identity(self: *Self, rc_start: usize) void {
            for (rc_start..S) |i| {
                for (0..S - 1) |j| {
                    self.data[j * S + i] = 0;
                    self.data[i * S + j] = 0;
                }
                self.data[i * S + i] = 1;
            }
        }

        pub fn clamp_vector(v: Vec, min: T, max: T) Vec {
            const min_v: Vec = @splat(min);
            const max_v: Vec = @splat(max);
            var pred: @Vector(S, bool) = v < min_v;
            var res: Vec = @select(T, pred, min_v, v);
            pred = res > max_v;
            res = @select(T, pred, max_v, res);
            return res;
        }

        pub fn fill_x(self: *Self, rc_start: usize, x: T) void {
            for (rc_start..S) |i| {
                for (rc_start..S) |j| {
                    self.data[i * S + j] = x;
                }
            }
        }
        pub fn rotate(comptime axis: @Type(.enum_literal), degrees: T) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            const rad = degrees * std.math.rad_per_deg;
            var ret = Self{};
            switch (axis) {
                .x => {
                    if (S < 4) return Error.TransformationUndefined;
                    ret.data[0] = 1;
                    ret.data[1] = 0;
                    ret.data[2] = 0;

                    ret.data[S] = 0;
                    ret.data[S + 1] = std.math.cos(rad);
                    ret.data[S + 2] = std.math.sin(rad);

                    ret.data[2 * S] = 0;
                    ret.data[2 * S + 1] = -std.math.sin(rad);
                    ret.data[2 * S + 2] = std.math.cos(rad);
                    ret.fill_identity(3);
                },
                .y => {
                    if (S < 4) return Error.TransformationUndefined;
                    ret.data[0] = std.math.cos(rad);
                    ret.data[1] = 0;
                    ret.data[2] = -std.math.sin(rad);

                    ret.data[S] = 0;
                    ret.data[S + 1] = 1;
                    ret.data[S + 2] = 0;

                    ret.data[2 * S] = std.math.sin(rad);
                    ret.data[2 * S + 1] = 0;
                    ret.data[2 * S + 2] = std.math.cos(rad);
                    ret.fill_identity(3);
                },
                .z => {
                    ret.data[0] = std.math.cos(rad);
                    ret.data[1] = -std.math.sin(rad);

                    ret.data[S] = std.math.sin(rad);
                    ret.data[S + 1] = std.math.cos(rad);
                    ret.fill_identity(2);
                },
                else => return Error.TransformationUndefined,
            }
            return ret;
        }
        pub fn shear(x: T, y: T) Error!Self {
            if (S < 2) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 1;
            ret.data[1] = y;
            ret.data[2] = 0;

            ret.data[S] = x;
            ret.data[S + 1] = 1;
            ret.data[S + 2] = 0;
            ret.fill_identity(2);
            return ret;
        }
        pub fn translate(x: T, y: T) Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 1;
            ret.data[1] = 0;
            ret.data[2] = x;

            ret.data[S] = 0;
            ret.data[S + 1] = 1;
            ret.data[S + 2] = y;

            ret.data[2 * S] = 0;
            ret.data[2 * S + 1] = 0;
            ret.data[2 * S + 2] = 1;
            ret.fill_identity(3);
            return ret;
        }
        pub fn identity() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.fill_identity(0);
            return ret;
        }

        pub fn edge_detection() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = -1;
            ret.data[1] = -1;
            ret.data[2] = -1;

            ret.data[S] = -1;
            ret.data[S + 1] = 8;
            ret.data[S + 2] = -1;

            ret.data[2 * S] = -1;
            ret.data[2 * S + 1] = -1;
            ret.data[2 * S + 2] = -1;
            ret.fill_identity(3);
            return ret;
        }

        pub fn vertical_edge_detection() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = -1;
            ret.data[1] = 0;
            ret.data[2] = 1;

            ret.data[S] = -1;
            ret.data[S + 1] = 0;
            ret.data[S + 2] = 1;

            ret.data[2 * S] = -1;
            ret.data[2 * S + 1] = 0;
            ret.data[2 * S + 2] = 1;
            ret.fill_identity(3);
            return ret;
        }
        pub fn horizontal_edge_detection() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = -1;
            ret.data[1] = -1;
            ret.data[2] = -1;

            ret.data[S] = 0;
            ret.data[S + 1] = 0;
            ret.data[S + 2] = 0;

            ret.data[2 * S] = 1;
            ret.data[2 * S + 1] = 1;
            ret.data[2 * S + 2] = 1;
            ret.fill_identity(3);
            return ret;
        }
        pub fn sharpen() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 0;
            ret.data[1] = -1;
            ret.data[2] = 0;

            ret.data[S] = -1;
            ret.data[S + 1] = 4;
            ret.data[S + 2] = -1;

            ret.data[2 * S] = 0;
            ret.data[2 * S + 1] = -1;
            ret.data[2 * S + 2] = 0;
            ret.fill_identity(3);
            return ret;
        }
        pub fn box_blur() Error!Self {
            if (S < 3) return Error.TransformationUndefined;
            var ret = Self{};
            ret.data[0] = 1.0 / 9.0;
            ret.data[1] = 1.0 / 9.0;
            ret.data[2] = 1.0 / 9.0;

            ret.data[S] = 1.0 / 9.0;
            ret.data[S + 1] = 1.0 / 9.0;
            ret.data[S + 2] = 1.0 / 9.0;

            ret.data[2 * S] = 1.0 / 9.0;
            ret.data[2 * S + 1] = 1.0 / 9.0;
            ret.data[2 * S + 2] = 1.0 / 9.0;
            ret.fill_identity(3);
            return ret;
        }

        pub fn vectorize(args: anytype) Error!Vec {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .@"struct") {
                @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
            }
            if (args_type_info.Struct.fields.len != S - 1) {
                return Error.ArgError;
            }
            var res: Vec = undefined;
            inline for (0..args_type_info.Struct.fields.len) |i| {
                res[i] = @field(args, args_type_info.Struct.fields[i].name);
            }
            res[S - 1] = 1;
            //std.log.warn("vectorized {any}\n", .{res});
            return res;
        }
        pub fn row(self: *const Self, r: usize) Vec {
            return self.data[r * S .. r * S + S][0..S].*;
        }
        pub fn transpose(self: *Self) void {
            for (0..S - 1) |i| {
                for (i + 1..S) |j| {
                    const temp = self.data[i * S + j];
                    self.data[i * S + j] = self.data[j * S + i];
                    self.data[j * S + i] = temp;
                }
            }
        }
        pub fn mul_v(self: *const Self, v: Vec) Vec {
            var res: Vec = undefined;
            for (0..S) |i| {
                const mat_r: Vec = self.data[i * S .. i * S + S][0..S].*;
                res[i] = @reduce(.Add, mat_r * v);
            }
            //std.log.warn("matrix vector {any}\n", .{res});
            return res;
        }
        pub fn mul(self: *const Self, other: Self) Self {
            return self.naive_mul(other);
        }
        //TODO fix to work with 0.14
        // pub fn mul_by_col(self: *const Self, other: Self) Self {
        //     var res: Self = undefined;
        //     for (0..S) |i| {
        //         const mat_r: Vec = self.data[i * S .. i * S + S][0..S].*;
        //         for (0..S) |j| {
        //             var mat_c: Vec = undefined;
        //             for (0..S) |k| {
        //                 mat_c[k] = other.data[k * S + j];
        //             }
        //             res.data[i * S + j] = @reduce(.Add, mat_r * mat_c);
        //         }
        //     }
        //     std.log.debug("matrix matrix by col {any}\n", .{res.data});
        //     return res;
        // }
        // pub fn mul_by_row(self: *const Self, other: Self) Self {
        //     var res: Self = Self.init(.{0} ** (S * S));
        //     for (0..S) |i| {
        //         const mat_r: Vec = self.data[i * S .. i * S + S][0..S].*;
        //         for (0..S) |j| {
        //             const mat_other_r: Vec = other.data[j * S .. j * S + S][0..S].*;
        //             res.data[i * S .. i * S + S][0..S].* += mat_r * mat_other_r;
        //         }
        //     }
        //     std.log.debug("matrix matrix by row {any}\n", .{res.data});
        //     return res;
        // }
        pub fn naive_mul(self: *const Self, other: Self) Self {
            var res: Self = undefined;
            for (0..S) |i| {
                for (0..S) |j| {
                    res.data[i * S + j] = 0;
                    //std.debug.print("C{d}{d} = ", .{ i, j });
                    for (0..S) |k| {
                        //std.debug.print("{d} x {d}", .{ self.data[i * S + k], other.data[k * S + j] });
                        res.data[i * S + j] += self.data[i * S + k] * other.data[k * S + j];
                        if (k < S - 1) {
                            //std.debug.print(" + ", .{});
                        }
                    }
                    //std.debug.print(" = {d}\n", .{res.data[i * S + j]});
                }
            }
            //std.log.warn("matrix matrix {any}\n", .{res.data});
            return res;
        }
        pub fn naive_mul_v(self: *const Self, v: [S]f64) [S]f64 {
            var res: [S]f64 = undefined;
            for (0..S) |i| {
                res[i] = 0;
                for (0..S) |j| {
                    res[i] += self.data[i * S + j] * v[j];
                }
            }
            //std.log.warn("matrix vector {any}\n", .{res});
            return res;
        }
    };
}

test "MATRIX" {
    const size: comptime_int = 3;
    const Matrix = Mat(size, f64);
    var m: Matrix = undefined;
    for (0..size) |i| {
        for (0..size) |j| {
            m.data[i * size + j] = 2;
        }
    }
    m.print();
    var m2: Matrix = undefined;
    for (0..size) |i| {
        for (0..size) |j| {
            m2.data[i * size + j] = 2;
        }
    }
    m2.print();
    var v: Matrix.Vec = undefined;
    for (0..size) |i| {
        v[i] = 2;
    }
    var v_a: [size]f64 = undefined;
    for (0..size) |i| {
        v_a[i] = 2;
    }
    _ = m.mul_v(v);
    _ = m.naive_mul_v(v_a);
    _ = m.mul(m2);
    _ = m.naive_mul(m2);
    const rotate = try Matrix.rotate(.z, 45);
    rotate.print();
    _ = rotate.mul_v(.{ 5, 5, 1 });
    _ = try Matrix.vectorize(.{ 2, 4 });
    const scale = try Mat(4, f64).scale(5);
    scale.print();
}

// test "MATRIX mult" {
//     const size: comptime_int = 128;
//     const Matrix = Mat(size, f64);
//     var m: Matrix = Matrix{};
//     m.fill_x(0, 2);
//     m.print();
//     var m2: Matrix = Matrix{};
//     m2.fill_x(0, 2);
//     m2.print();

//     try utils.timer_start();
//     _ = m.mul_by_row(m2);
//     utils.timer_end();
//     _ = m.mul_by_col(m2);
//     utils.timer_end();
// }

test "Transpose" {
    const size: comptime_int = 3;
    const Matrix = Mat(size, f64);
    var m = Matrix.init(.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 });
    m.print();
    m.transpose();
    m.print();
}
