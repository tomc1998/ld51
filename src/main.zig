const std = @import("std");
const C = @import("C.zig");

pub fn main() !void {
    C.InitWindow(1600, 900, "window_me");
    defer C.CloseWindow();

    C.SetTargetFPS(60);
    while (!C.WindowShouldClose()) {
        C.BeginDrawing();
        C.ClearBackground(C.BLACK);
        C.DrawFPS(10, 10);
        C.EndDrawing();
    }
}
