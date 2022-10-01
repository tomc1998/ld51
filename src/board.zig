const std = @import("std");
const la = @import("linalg.zig");

/// 2x2 blocks make up a Tile
pub const Block = enum { white, black };

pub const Tile = packed struct {
    tl: bool,
    tr: bool,
    br: bool,
    bl: bool,
    present: bool,
    pub inline fn init(tl: bool, tr: bool, bl: bool, br: bool) @This() {
        return @This(){
            .tl = tl,
            .tr = tr,
            .bl = bl,
            .br = br,
            .present = true,
        };
    }

    pub inline fn initEmpty() @This() {
        return @This(){
            .tl = undefined,
            .tr = undefined,
            .bl = undefined,
            .br = undefined,
            .present = false,
        };
    }

    pub fn rotateClockwise(self: *@This()) void {
        const old_tl = self.tl;
        self.tl = self.bl;
        self.bl = self.br;
        self.br = self.tr;
        self.tr = old_tl;
    }

    pub fn rotateAntiClockwise(self: *@This()) void {
        const old_tl = self.tl;
        self.tl = self.tr;
        self.tr = self.br;
        self.br = self.bl;
        self.bl = old_tl;
    }
};

comptime {
    if (@sizeOf(Tile) != 1) {
        @compileError("Tile is not 1 byte");
    }
}

alloc: std.mem.Allocator,
tiles: []Tile,
board_w: usize,
board_h: usize,
score_squares: std.ArrayListUnmanaged(la.Vec2(u16)) = .{},

pub fn at(self: @This(), x: usize, y: usize) Tile {
    std.debug.assert(x < self.board_w and y < self.board_h);
    return self.tiles[y * self.board_w + x];
}

/// Query a specific coordinate for a block (2x2 block makes up a tile)
pub fn blockAt(self: @This(), x: usize, y: usize) ?Block {
    const tile = self.at(@divFloor(x, 2), @divFloor(y, 2));
    if (!tile.present) {
        return null;
    }
    const modx = @rem(x, 2);
    const mody = @rem(y, 2);
    const val: bool = if (modx == 0 and mody == 0)
        tile.tl
    else if (modx == 1 and mody == 0)
        tile.tr
    else if (modx == 0 and mody == 1)
        tile.bl
    else
        tile.br;
    return if (val) Block.white else Block.black;
}

/// Call after modifying the tile at (x,y) to recalculate the score squares
pub fn recalculateScoreSquaresForTile(self: *@This(), x: usize, y: usize) void {
    // first, remove any score squares that intersect this tile
    // TODO this is O(n), might become a problem if we get massive maps
    var squaresToInvalidate: std.BoundedArray(la.Vec2(u16), 9) = .{};
    var yy: usize = 0;
    while (yy < 3) : (yy += 1) {
        if (yy == 0 and y == 0) {
            continue;
        }
        var xx: usize = 0;
        while (xx < 3) : (xx += 1) {
            if (xx == 0 and x == 0) {
                continue;
            }
            squaresToInvalidate.append(la.Vec2(u16){
                .x = @intCast(u16, x * 2 + xx - 1),
                .y = @intCast(u16, y * 2 + yy - 1),
            }) catch unreachable;
        }
    }
    var ii: isize = 0;
    while (ii < @intCast(isize, self.score_squares.items.len)) : (ii += 1) {
        const ss = self.score_squares.items[@intCast(usize, ii)];
        for (squaresToInvalidate.slice()) |s| {
            if (s.x == ss.x and s.y == ss.y) {
                _ = self.score_squares.orderedRemove(@intCast(usize, ii));
                ii -= 1;
                break;
            }
        }
    }

    // Now, add new score squares
    // gather the 4x4 blocks surrounding & including this tile
    var blocks_around: [16]?Block = undefined;
    yy = 0;
    while (yy < 4) : (yy += 1) {
        var xx: usize = 0;
        while (xx < 4) : (xx += 1) {
            const out_ix = yy * 4 + xx;
            if ((x == 0 and xx == 0) or (y == 0 and yy == 0) or x * 2 + xx - 1 >= self.board_w * 2 or y * 2 + yy - 1 >= self.board_h * 2) {
                blocks_around[out_ix] = null;
            } else {
                blocks_around[out_ix] = self.blockAt((x * 2 + xx) - 1, (y * 2 + yy) - 1);
            }
        }
    }
    // Loop over the 3x3 possible new score squares, add each to score_squares if valid
    yy = 0;
    while (yy < 3) : (yy += 1) {
        var xx: usize = 0;
        while (xx < 3) : (xx += 1) {
            const b0 = blocks_around[(yy + 0) * 4 + (xx + 0)] orelse continue;
            const b1 = blocks_around[(yy + 0) * 4 + (xx + 1)] orelse continue;
            const b2 = blocks_around[(yy + 1) * 4 + (xx + 0)] orelse continue;
            const b3 = blocks_around[(yy + 1) * 4 + (xx + 1)] orelse continue;
            if (b0 == b1 and b1 == b2 and b2 == b3) {
                self.score_squares.append(
                    self.alloc,
                    .{ .x = @intCast(u16, x * 2 + xx - 1), .y = @intCast(u16, y * 2 + yy - 1) },
                ) catch {
                    std.log.err("OOM whilst calculating score squares, game is compromised, exiting", .{});
                    std.process.exit(1);
                };
            }
        }
    }
}

pub fn set(self: *@This(), x: usize, y: usize, val: Tile) void {
    std.debug.assert(x < self.board_w and y < self.board_h);
    if (self.at(x, y).present and val.present) {
        @panic("Setting a tile which is already set");
    } else if (!self.at(x, y).present and !val.present) {
        @panic("Erasing a tile which isn't there");
    }
    self.tiles[y * self.board_w + x] = val;
    self.recalculateScoreSquaresForTile(x, y);
}

pub fn rotateClockwise(self: *@This(), x: usize, y: usize) void {
    std.debug.assert(x < self.board_w and y < self.board_h);
    std.debug.assert(self.at(x, y).present);
    self.tiles[y * self.board_h + x].rotateClockwise();
    self.recalculateScoreSquaresForTile(x, y);
}

pub fn rotateAntiClockwise(self: *@This(), x: usize, y: usize) void {
    std.debug.assert(x < self.board_w and y < self.board_h);
    std.debug.assert(self.at(x, y).present);
    self.tiles[y * self.board_h + x].rotateAntiClockwise();
    self.recalculateScoreSquaresForTile(x, y);
}

pub fn init(alloc: std.mem.Allocator, w: usize, h: usize) !@This() {
    const tiles: []Tile = try alloc.alloc(Tile, w * h);
    errdefer alloc.free(tiles);
    std.mem.set(Tile, tiles, Tile.initEmpty());
    return @This(){
        .alloc = alloc,
        .tiles = tiles,
        .board_w = w,
        .board_h = h,
    };
}

pub fn deinit(self: *@This()) void {
    self.alloc.free(self.tiles);
    self.score_squares.deinit(self.alloc);
}
