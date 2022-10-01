const std = @import("std");

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

pub fn at(self: *@This(), x: usize, y: usize) *Tile {
    std.debug.assert(x < self.board_w and y < self.board_h);
    return &self.tiles[y * self.board_w + x];
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
