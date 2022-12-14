const std = @import("std");
const la = @import("linalg.zig");
const Board = @import("board.zig");
const C = @import("C.zig");
const g = @import("globals.zig");

/// Renders the game. Everything gets rendered to some FBOs, they get
/// composited, then we scale up everything by some integer scale before
/// rendering to the final framebuffer.
pub const Renderer = struct {
    alloc: std.mem.Allocator,
    /// Render 'white' blocks to this fbo. 2x2 blocks make up a Tile
    white_fbo: C.RenderTexture2D,
    /// Render 'black' blocks to this fbo. 2x2 blocks make up a Tile
    black_fbo: C.RenderTexture2D,
    /// Render 'white' blocks to this fbo. 2x2 blocks make up a Tile
    white_fbo_rounded: C.RenderTexture2D,
    /// Render 'black' blocks to this fbo. 2x2 blocks make up a Tile
    black_fbo_rounded: C.RenderTexture2D,
    score_square_blur_fbos: [2]C.RenderTexture2D,
    /// Shader to 'round' the shapes in the black/white FBOs in a pixelart style.
    round_shader: C.Shader,
    /// How much to scale up FBOs after compositing
    scale: u32,
    /// Should be globals.screen_w / scale
    fbo_w: u32,
    /// Should be globals.screen_h / scale
    fbo_h: u32,
    camera: C.Camera2D,
    white_color: C.Color = C.WHITE,
    black_color: C.Color = C.GREEN,
    score_color: C.Color = .{ .r = 254, .g = 191, .b = 148, .a = 255 },

    pub fn init(alloc: std.mem.Allocator) @This() {
        const scale: u32 = 4;
        const fbo_w: u32 = @floatToInt(u32, std.math.ceil(g.screen_w / @intToFloat(f32, scale)));
        const fbo_h: u32 = @floatToInt(u32, std.math.ceil(g.screen_h / @intToFloat(f32, scale)));
        return @This(){
            .alloc = alloc,
            .camera = C.Camera2D{
                .offset = .{ .x = g.screen_w / 2, .y = g.screen_h / 2 },
                .target = .{ .x = 0.0, .y = 0.0 },
                .rotation = 0.0,
                .zoom = 4.0,
            },
            .round_shader = C.LoadShader(
                null,
                "assets/shaders/round_frag.glsl",
            ),
            .white_fbo = C.LoadRenderTexture(@intCast(c_int, fbo_w), @intCast(c_int, fbo_h)),
            .black_fbo = C.LoadRenderTexture(@intCast(c_int, fbo_w), @intCast(c_int, fbo_h)),
            .white_fbo_rounded = C.LoadRenderTexture(@intCast(c_int, fbo_w), @intCast(c_int, fbo_h)),
            .black_fbo_rounded = C.LoadRenderTexture(@intCast(c_int, fbo_w), @intCast(c_int, fbo_h)),
            .scale = scale,
            .fbo_w = fbo_w,
            .fbo_h = fbo_h,
        };
    }

    /// mouse_tile_pos: indexes into board
    pub fn render(self: *@This(), board: Board, mouse_tile_pos: la.Vec2f) void {

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
        const camera_size = la.Vec2f.fromRaylib(self.camera.offset).mul(2.0).mul(1.0 / self.camera.zoom);
        const camera_tl = camera_size.mul(-0.5).add(la.Vec2f.fromRaylib(self.camera.target));
        // Now use these two positions to compute the index of the top left most tile that must be rendered
        const top_left_tile_pos = camera_tl.sub(board_tl).mul(1.0 / g.tile_size).floor();
        const tile_rect_size = camera_size.mul(1.0 / g.tile_size).ceil().add(.{ .x = 1, .y = 1 });
        const bottom_right_tile_pos = top_left_tile_pos.add(tile_rect_size);

        // Now we can draw all the tiles. We want to draw all the
        // 'white tiles to white_fbo, then all the 'black' tiles to
        // black_fbo. Then we run a shader to smooth, composite together,
        // then outline.
        var unzoomed_camera = self.camera;
        unzoomed_camera.offset.x /= self.camera.zoom;
        unzoomed_camera.offset.y /= self.camera.zoom;
        unzoomed_camera.zoom = 1.0;
        for ([2]bool{ true, false }) |render_white| {
            if (render_white) {
                C.BeginTextureMode(self.white_fbo);
            } else {
                C.BeginTextureMode(self.black_fbo);
            }
            C.ClearBackground(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
            C.BeginMode2D(unzoomed_camera);
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
                        if (tile.tl == render_white) {
                            C.DrawRectangleV(
                                pos.toRaylib(),
                                .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                                C.WHITE,
                            );
                        }
                        if (tile.tr == render_white) {
                            C.DrawRectangleV(
                                pos.add(.{ .x = g.tile_size / 2, .y = 0 }).toRaylib(),
                                .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                                C.WHITE,
                            );
                        }
                        if (tile.bl == render_white) {
                            C.DrawRectangleV(
                                pos.add(.{ .y = g.tile_size / 2, .x = 0 }).toRaylib(),
                                .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                                C.WHITE,
                            );
                        }
                        if (tile.br == render_white) {
                            C.DrawRectangleV(
                                pos.add(.{ .y = g.tile_size / 2, .x = g.tile_size / 2 }).toRaylib(),
                                .{ .x = g.tile_size / 2, .y = g.tile_size / 2 },
                                C.WHITE,
                            );
                        }
                    }
                }
            }
            C.EndMode2D();
            C.EndTextureMode();
        }

        // Round each fbo
        const FboPipe = struct {
            in: C.RenderTexture,
            out: C.RenderTexture,
        };
        for ([_]FboPipe{
            .{ .in = self.white_fbo, .out = self.white_fbo_rounded },
            .{ .in = self.black_fbo, .out = self.black_fbo_rounded },
        }) |fbo_pipe| {
            C.BeginTextureMode(fbo_pipe.out);
            C.BeginShaderMode(self.round_shader);
            C.ClearBackground(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
            C.DrawTexturePro(
                fbo_pipe.in.texture,
                .{
                    .x = 0,
                    .y = @intToFloat(f32, fbo_pipe.in.texture.height),
                    .width = @intToFloat(f32, fbo_pipe.in.texture.width),
                    .height = -@intToFloat(f32, fbo_pipe.in.texture.height),
                },
                .{
                    .x = 0,
                    .y = 0,
                    .width = @intToFloat(f32, fbo_pipe.out.texture.width),
                    .height = @intToFloat(f32, fbo_pipe.out.texture.height),
                },
                .{ .x = 0, .y = 0 },
                0.0,
                C.WHITE,
            );
            C.EndShaderMode();
            C.EndTextureMode();
        }

        // Combine FBOs into final framebuffer
        C.DrawTexturePro(
            self.black_fbo_rounded.texture,
            .{
                .x = 0,
                .y = @intToFloat(f32, self.black_fbo_rounded.texture.height),
                .width = @intToFloat(f32, self.black_fbo_rounded.texture.width),
                .height = -@intToFloat(f32, self.black_fbo_rounded.texture.height),
            },
            .{
                .x = 0,
                .y = -1,
                .width = g.screen_w,
                .height = g.screen_h - 1,
            },
            .{ .x = 0, .y = 0 },
            0.0,
            self.white_color,
        );
        C.DrawTexturePro(
            self.white_fbo_rounded.texture,
            .{
                .x = 0,
                .y = @intToFloat(f32, self.white_fbo_rounded.texture.height),
                .width = @intToFloat(f32, self.white_fbo_rounded.texture.width),
                .height = -@intToFloat(f32, self.white_fbo_rounded.texture.height),
            },
            .{
                .x = 0,
                .y = -1,
                .width = g.screen_w,
                .height = g.screen_h - 1,
            },
            .{ .x = 0, .y = 0 },
            0.0,
            self.white_color,
        );

        // Render our score squares to the score square fbo for blurring

        C.BeginMode2D(self.camera);
        // Render a square indicating what the mouse is hovering
        const mouse_clamped = mouse_tile_pos.mul(g.tile_size);
        C.DrawRectangleV(
            board_tl.add(mouse_clamped).toRaylib(),
            .{ .x = g.tile_size, .y = g.tile_size },
            .{ .r = 255, .g = 255, .b = 255, .a = 100 },
        );
        // Draw score squares
        for (board.score_squares.items) |ss| {
            C.DrawRectangleLinesEx(.{
                .x = board_tl.x + @intToFloat(f32, ss.x) * g.tile_size / 2,
                .y = board_tl.y + @intToFloat(f32, ss.y) * g.tile_size / 2,
                .width = g.tile_size,
                .height = g.tile_size,
            }, 1.0, C.RED);
        }
        C.EndMode2D();
    }

    pub fn deinit(self: *@This()) void {
        C.UnloadRenderTexture(self.white_fbo);
        C.UnloadRenderTexture(self.black_fbo);
    }
};

pub fn main() !void {
    C.InitWindow(@floatToInt(c_int, g.screen_w), @floatToInt(c_int, g.screen_h), "window_me");
    defer C.CloseWindow();

    var board = try Board.init(std.heap.c_allocator, 1024, 1024);
    board.set(512, 512, Board.Tile.init(true, false, false, true));

    const target_fps: f32 = 480.0;
    const dt: f32 = 1.0 / target_fps;
    C.SetTargetFPS(@floatToInt(c_int, target_fps));

    var renderer = Renderer.init(std.heap.c_allocator);
    defer renderer.deinit();

    var rand = std.rand.DefaultPrng.init(123098123098); // TODO choose seed based on something like time

    while (!C.WindowShouldClose()) {
        // Compute mouse position in world
        const mouse_screen = la.Vec2f.fromRaylib(C.GetMousePosition());
        const mouse_world = mouse_screen.mul(1.0 / renderer.camera.zoom)
            .add(la.Vec2f.fromRaylib(renderer.camera.offset).mul(-1.0 / renderer.camera.zoom))
            .add(la.Vec2f.fromRaylib(renderer.camera.target));
        var mouse_tile_pos = mouse_world.mul(1.0 / g.tile_size).floor();
        mouse_tile_pos = mouse_tile_pos.add(.{
            .x = @intToFloat(f32, @divFloor(board.board_w, 2)),
            .y = @intToFloat(f32, @divFloor(board.board_h, 2)),
        });
        mouse_tile_pos.x = std.math.clamp(mouse_tile_pos.x, 0.0, @intToFloat(f32, board.board_w - 1));
        mouse_tile_pos.y = std.math.clamp(mouse_tile_pos.y, 0.0, @intToFloat(f32, board.board_h - 1));
        const mouse_tile_x: usize = @floatToInt(usize, mouse_tile_pos.x);
        const mouse_tile_y: usize = @floatToInt(usize, mouse_tile_pos.y);
        const hovered_tile = board.at(mouse_tile_x, mouse_tile_y);

        if (C.IsMouseButtonDown(C.MOUSE_BUTTON_LEFT)) {
            if (!hovered_tile.present) {
                board.set(
                    mouse_tile_x,
                    mouse_tile_y,
                    Board.Tile.init(
                        rand.random().boolean(),
                        rand.random().boolean(),
                        rand.random().boolean(),
                        rand.random().boolean(),
                    ),
                );
            }
        }

        if (hovered_tile.present) {
            if (C.IsKeyPressed(C.KEY_E)) {
                board.rotateClockwise(
                    @floatToInt(usize, mouse_tile_pos.x),
                    @floatToInt(usize, mouse_tile_pos.y),
                );
            }
            if (C.IsKeyPressed(C.KEY_Q)) {
                board.rotateAntiClockwise(
                    @floatToInt(usize, mouse_tile_pos.x),
                    @floatToInt(usize, mouse_tile_pos.y),
                );
            }
        }

        // Scroll camera?
        const camera_scroll_speed: f32 = 400.0; // pixels per second
        if (C.IsKeyDown(C.KEY_A)) {
            renderer.camera.target.x -= dt * camera_scroll_speed;
        } else if (C.IsKeyDown(C.KEY_D)) {
            renderer.camera.target.x += dt * camera_scroll_speed;
        }
        if (C.IsKeyDown(C.KEY_W)) {
            renderer.camera.target.y -= dt * camera_scroll_speed;
        } else if (C.IsKeyDown(C.KEY_S)) {
            renderer.camera.target.y += dt * camera_scroll_speed;
        }

        C.BeginDrawing();
        C.ClearBackground(C.BLACK);
        renderer.render(board, mouse_tile_pos);
        const dbg_txt = try std.fmt.allocPrintZ(std.heap.c_allocator, "{d} {d}", .{ mouse_world.x, mouse_world.y });
        defer std.heap.c_allocator.free(dbg_txt);
        C.DrawText(dbg_txt, 100, 10, 10, C.WHITE);

        C.DrawFPS(10, 10);
        C.EndDrawing();
    }
}
