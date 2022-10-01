const std = @import("std");
const la = @import("linalg.zig");
const Board = @import("board.zig");
const C = @import("C.zig");
const g = @import("globals.zig");

pub fn main() !void {
    C.InitWindow(@floatToInt(c_int, g.screen_w), @floatToInt(c_int, g.screen_h), "window_me");
    defer C.CloseWindow();

    var camera = C.Camera2D{
        .offset = .{ .x = g.screen_w / 2, .y = g.screen_h / 2 },
        .target = .{ .x = 0.0, .y = 0.0 },
        .rotation = 0.0,
        .zoom = 1.0,
    };
    var board = try Board.init(std.heap.c_allocator, 10, 10);
    board.at(5, 5).* = Board.Tile.init(true, false, false, true);

    const target_fps: f32 = 60.0;
    const dt: f32 = 1.0 / target_fps;
    C.SetTargetFPS(@floatToInt(c_int, target_fps));

    var rand = std.rand.DefaultPrng.init(123098123098); // TODO choose seed based on something like time

    while (!C.WindowShouldClose()) {
        // Compute mouse position in world
        const mouse_screen = la.Vec2f.fromRaylib(C.GetMousePosition());
        // TODO zoom when calculating mouse_world
        std.debug.assert(camera.zoom == 1.0);
        const mouse_world = mouse_screen
            .add(la.Vec2f.fromRaylib(camera.offset).mul(-1))
            .add(la.Vec2f.fromRaylib(camera.target));
        var mouse_tile_pos = mouse_world.mul(1.0 / g.tile_size).floor();
        mouse_tile_pos = mouse_tile_pos.add(.{
            .x = @intToFloat(f32, @divFloor(board.board_w, 2)),
            .y = @intToFloat(f32, @divFloor(board.board_h, 2)),
        });
        mouse_tile_pos.x = std.math.clamp(mouse_tile_pos.x, 0.0, @intToFloat(f32, board.board_w - 1));
        mouse_tile_pos.y = std.math.clamp(mouse_tile_pos.y, 0.0, @intToFloat(f32, board.board_h - 1));

        if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
            board.at(
                @floatToInt(usize, mouse_tile_pos.x),
                @floatToInt(usize, mouse_tile_pos.y),
            ).* = Board.Tile.init(
                rand.random().boolean(),
                rand.random().boolean(),
                rand.random().boolean(),
                rand.random().boolean(),
            );
        }

        // Scroll camera?
        const camera_scroll_speed: f32 = 400.0; // pixels per second
        if (C.IsKeyDown(C.KEY_A)) {
            camera.target.x -= dt * camera_scroll_speed;
        } else if (C.IsKeyDown(C.KEY_D)) {
            camera.target.x += dt * camera_scroll_speed;
        }
        if (C.IsKeyDown(C.KEY_W)) {
            camera.target.y -= dt * camera_scroll_speed;
        } else if (C.IsKeyDown(C.KEY_S)) {
            camera.target.y += dt * camera_scroll_speed;
        }

        C.BeginDrawing();
        C.ClearBackground(C.BLACK);
        C.BeginMode2D(camera);

        // Given the camera target/offset, figure out which tiles we
        // want to draw from the board (since we don't just want to draw
        // the whole board each frame)
        // We assume the center of the board is at 0,0, so figure out
        // the top left of the board
        const board_size = la.Vec2f{
            .x = @intToFloat(f32, board.board_w) * g.tile_size,
            .y = @intToFloat(f32, board.board_h) * g.tile_size,
        };
        const board_tl = board_size.mul(-0.5);
        // Now figure out the camera top left & size too
        // We're assuming the camera offset here... maybe fix this
        // TODO zoom
        std.debug.assert(camera.zoom == 1.0);
        const camera_size = la.Vec2f.fromRaylib(camera.offset).mul(2.0);
        const camera_tl = camera_size.mul(-0.5).add(la.Vec2f.fromRaylib(camera.target));
        // Now use these two positions to compute the index of the top left most tile that must be rendered
        const top_left_tile_pos = camera_tl.sub(board_tl).mul(1.0 / g.tile_size).floor();
        const tile_rect_size = camera_size.mul(1.0 / g.tile_size).ceil().add(.{ .x = 1, .y = 1 });
        const bottom_right_tile_pos = top_left_tile_pos.add(tile_rect_size);
        // Finally, render the tiles
        var yy = @floatToInt(usize, std.math.max(0.0, top_left_tile_pos.y));
        while (yy < @floatToInt(usize, bottom_right_tile_pos.y)) : (yy += 1) {
            if (yy >= board.board_h) {
                break;
            }
            var xx = @floatToInt(usize, std.math.max(0.0, top_left_tile_pos.x));
            while (xx < @floatToInt(usize, bottom_right_tile_pos.x)) : (xx += 1) {
                if (xx >= board.board_w) {
                    break;
                }
                const tile = board.at(xx, yy);
                if (tile.present) {
                    const pos = board_tl.add(la.Vec2f{
                        .x = @intToFloat(f32, xx) * g.tile_size,
                        .y = @intToFloat(f32, yy) * g.tile_size,
                    });
                    C.DrawRectangleV(
                        pos.toRaylib(),
                        .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                        if (tile.tl) C.WHITE else C.GREEN,
                    );
                    C.DrawRectangleV(
                        pos.add(.{ .x = g.tile_size / 2, .y = 0 }).toRaylib(),
                        .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                        if (tile.tr) C.WHITE else C.GREEN,
                    );
                    C.DrawRectangleV(
                        pos.add(.{ .y = g.tile_size / 2, .x = 0 }).toRaylib(),
                        .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                        if (tile.bl) C.WHITE else C.GREEN,
                    );
                    C.DrawRectangleV(
                        pos.add(.{ .y = g.tile_size / 2, .x = g.tile_size / 2 }).toRaylib(),
                        .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                        if (tile.br) C.WHITE else C.GREEN,
                    );
                }
            }
        }

        // Render a square indicating what the mouse is hovering
        const mouse_clamped = mouse_tile_pos.mul(g.tile_size);
        C.DrawRectangleV(
            board_tl.add(mouse_clamped).toRaylib(),
            .{ .x = g.tile_size, .y = g.tile_size },
            .{ .r = 255, .g = 255, .b = 255, .a = 100 },
        );

        C.EndMode2D();
        C.DrawFPS(10, 10);
        C.EndDrawing();
    }
}
