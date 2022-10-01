#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

void main() {
  vec2 pixel_size = 1.0 / textureSize(texture0, 0);
  vec4 curr_col = texture(texture0, fragTexCoord);
  vec4 other_col = vec4(1, 1, 1, 1) - curr_col;
  bool top   = curr_col == texture(texture0, fragTexCoord - vec2(0.0, pixel_size.y));
  bool bot   = curr_col == texture(texture0, fragTexCoord + vec2(0.0, pixel_size.y));
  bool left  = curr_col == texture(texture0, fragTexCoord - vec2(pixel_size.x, 0.0));
  bool right = curr_col == texture(texture0, fragTexCoord + vec2(pixel_size.x, 0.0));
  bool tl    = curr_col == texture(texture0, fragTexCoord + vec2(-pixel_size.x, -pixel_size.y));
  bool tr    = curr_col == texture(texture0, fragTexCoord + vec2(pixel_size.x, -pixel_size.y));
  bool bl    = curr_col == texture(texture0, fragTexCoord + vec2(-pixel_size.x, pixel_size.y));
  bool br    = curr_col == texture(texture0, fragTexCoord + vec2(pixel_size.x, pixel_size.y));

  // Do we need to flip this pixel
  bool needs_flip =
    (top && left && tl && !bot && !right && !br) ||
    (top && right && tr && !bot && !left && !bl) ||
    (!top && !left && !tl && bot && right && br) ||
    (!top && !right && !tr && bot && left && bl);

  finalColor = needs_flip ? other_col : curr_col;
}