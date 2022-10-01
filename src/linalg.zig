const std = @import("std");
const C = @import("C.zig");

pub fn Mat4(comptime FloatT: type) type {
    return struct {
        data: [16]FloatT,
        pub fn identity() @This() {
            return @This(){ .data = [_]FloatT{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            } };
        }
        pub fn translation(x: FloatT, y: FloatT, z: FloatT) @This() {
            var ret = @This().identity();
            ret.data[12] = x;
            ret.data[13] = y;
            ret.data[14] = z;
            return ret;
        }
        pub fn ortho(l: FloatT, r: FloatT, b: FloatT, t: FloatT, n: FloatT, f: FloatT) @This() {
            var res = @This().identity();
            res.data[0] = 2.0 / (r - l);
            res.data[5] = 2 / (t - b);
            res.data[10] = -2 / (f - n);
            res.data[12] = -(r + l) / (r - l);
            res.data[13] = -(t + b) / (t - b);
            res.data[14] = -(f + n) / (f - n);
            res.data[15] = 1;
            return res;
        }
        pub fn persp(fovy: FloatT, aspect: FloatT, n: FloatT, f: FloatT) @This() {
            var ret = std.mem.zeroes(@This());
            var tan_fovy_2 = std.math.tan(fovy / 2.0);
            ret.data[0] = 1.0 / aspect * tan_fovy_2;
            ret.data[5] = 1.0 / tan_fovy_2;
            ret.data[10] = -(f + n) / (f - n);
            ret.data[11] = -1.0;
            ret.data[14] = -(2.0 * f * n) / (f - n);
            return ret;
        }

        pub fn rotationX(radians: FloatT) @This() {
            var ret = @This().identity();
            const s = std.math.sin(radians);
            const c = std.math.cos(radians);
            ret.data[5] = c;
            ret.data[6] = -s;
            ret.data[9] = s;
            ret.data[10] = c;
            return ret;
        }
        pub fn rotationY(radians: FloatT) @This() {
            var ret = @This().identity();
            const s = std.math.sin(radians);
            const c = std.math.cos(radians);
            ret.data[0] = c;
            ret.data[2] = s;
            ret.data[8] = -s;
            ret.data[10] = c;
            return ret;
        }
        pub fn rotationZ(radians: FloatT) @This() {
            var ret = @This().identity();
            const s = std.math.sin(radians);
            const c = std.math.cos(radians);
            ret.data[0] = c;
            ret.data[1] = -s;
            ret.data[4] = s;
            ret.data[5] = c;
            return ret;
        }
        pub fn rotateX(self: *@This(), rad: FloatT) void {
            self.* = @This().rotationX(rad).mul(self.*);
        }
        pub fn rotateY(self: *@This(), rad: FloatT) void {
            self.* = @This().rotationY(rad).mul(self.*);
        }
        pub fn rotateZ(self: *@This(), rad: FloatT) void {
            self.* = @This().rotationZ(rad).mul(self.*);
        }
        pub fn translate(self: *@This(), x: FloatT, y: FloatT, z: FloatT) void {
            self.* = @This().translation(x, y, z).mul(self.*);
        }
        pub fn at(self: @This(), x: usize, y: usize) FloatT {
            return self.data[y * 4 + x];
        }
        pub fn mul(self: @This(), other: @This()) @This() {
            var ret: Mat4f = undefined;
            var ii: usize = 0;
            while (ii < 4) : (ii += 1) {
                var jj: usize = 0;
                while (jj < 4) : (jj += 1) {
                    const ix = jj * 4 + ii;
                    ret.data[ix] = 0.0;
                    var kk: usize = 0;
                    while (kk < 4) : (kk += 1) {
                        ret.data[ix] += self.at(kk, jj) * other.at(ii, kk);
                    }
                }
            }
            return ret;
        }
    };
}

pub fn Vec4(comptime FloatT: type) type {
    return struct {
        x: FloatT,
        y: FloatT,
        z: FloatT,
        w: FloatT,
        pub fn cast(self: @This(), comptime T: type) Vec2(T) {
            return Vec4(T){ .x = @floatCast(T, self.x), .y = @floatCast(T, self.y), .z = @floatCast(T, self.z), .w = @floatCast(T, self.w) };
        }
    };
}

pub fn Vec3(comptime FloatT: type) type {
    return struct {
        x: FloatT,
        y: FloatT,
        z: FloatT,
        pub fn cast(self: @This(), comptime T: type) Vec3(T) {
            return Vec3(T){ .x = @floatCast(T, self.x), .y = @floatCast(T, self.y), .z = @floatCast(T, self.z) };
        }
        pub fn add(self: @This(), other: @This()) @This() {
            return @This(){
                .x = self.x + other.x,
                .y = self.y + other.y,
                .z = self.z + other.z,
            };
        }
        pub fn sub(self: @This(), other: @This()) @This() {
            return self.add(other.scl(-1));
        }
        pub fn len2(self: @This()) FloatT {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }
        pub fn len(self: @This()) FloatT {
            return std.math.sqrt(self.len2());
        }
        pub fn scl(self: @This(), val: FloatT) @This() {
            return @This(){
                .x = val * self.x,
                .y = val * self.y,
                .z = val * self.z,
            };
        }
        pub fn normalize(self: *@This()) void {
            const l = self.len();
            self.x /= l;
            self.y /= l;
            self.z /= l;
        }
    };
}

pub fn Vec2(comptime FloatT: type) type {
    return struct {
        x: FloatT,
        y: FloatT,
        pub fn cast(self: @This(), comptime T: type) Vec2(T) {
            return Vec2(T){ .x = @floatCast(T, self.x), .y = @floatCast(T, self.y) };
        }
        pub fn len2(self: @This()) FloatT {
            return self.x * self.x + self.y * self.y;
        }
        pub fn len(self: @This()) FloatT {
            return std.math.sqrt(self.len2());
        }
        pub fn mul(self: @This(), x: FloatT) @This() {
            return @This(){ .x = self.x * x, .y = self.y * x };
        }
        pub fn add(self: @This(), other: @This()) @This() {
            return @This(){ .x = self.x + other.x, .y = self.y + other.y };
        }
        pub fn sub(self: @This(), other: @This()) @This() {
            return @This(){ .x = self.x - other.x, .y = self.y - other.y };
        }
        pub fn floor(self: @This()) @This() {
            return @This(){ .x = std.math.floor(self.x), .y = std.math.floor(self.y) };
        }
        pub fn ceil(self: @This()) @This() {
            return @This(){ .x = std.math.ceil(self.x), .y = std.math.ceil(self.y) };
        }
        pub fn fromRaylib(rl: C.Vector2) @This() {
            return @This(){ .x = rl.x, .y = rl.y };
        }
        pub fn toRaylib(self: @This()) C.Vector2 {
            return C.Vector2{ .x = self.x, .y = self.y };
        }
    };
}

pub const Vec2f = Vec2(f32);
pub const Vec2d = Vec2(f64);
pub const Vec3f = Vec3(f32);
pub const Vec3d = Vec3(f64);
pub const Vec4f = Vec4(f32);
pub const Vec4d = Vec4(f64);
pub const Mat4f = Mat4(f32);
