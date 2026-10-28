# Levelarium
Levelarium is a versatile and user-friendly level editor built with LÖVE2D. It allows you to create, edit, and save custom game levels using a tile-based system.

## Features
- Intuitive tile-based level editing
- Multiple drawing tools: Brush, Eraser, Bucket Fill, Line, and Rectangle
- Multiple layers (up to 5)
- Customizable grid size and tile set
- Camera pan and zoom for easy navigation
- Eyedropper: right click picks the tile under the cursor
- Save levels as TXT, JSON or TMX (Tiled); load levels from TXT

## Getting Started

### Prerequisites
- [LÖVE2D](https://love2d.org/) (version 11.5 or later)
- [Lua](https://www.lua.org/) 5.1 / LuaJIT is only needed to run the tests (LÖVE already bundles LuaJIT)

### Installation
```bash
git clone https://github.com/ruffbuff/Levelarium
cd Levelarium
```

### Running the Application
**1. Linux:**
To run Levelarium, use the following command in the project directory: `love .`,
or use `./run.sh` in the project directory.

**2. Windows:**
On Windows, you can drag the project folder onto the `love.exe` file.

## Usage
- Use the mouse to select tiles and draw on the grid (left button)
- Right click on the grid picks the tile under the cursor (eyedropper)
- Press number keys 1-5 to switch between tools:
  1. Brush
  2. Eraser
  3. Bucket Fill
  4. Line
  5. Rectangle
- Use WASD keys to pan the camera
- Scroll wheel to zoom in/out (scroll over the tile palette to scroll the palette)
- `N` - new layer, `PgUp` / `PgDn` - switch layer, `Del` - delete the current layer
- `T` - choose an asset pack
- `C` - change the canvas (grid) size
- `F` - choose the save format (TXT, JSON, TMX)
- Press 'P' to save the level
- Press 'L' to load a saved level (TXT files)
- Press 'ESC' to return to the main menu

Levels are saved to the `levels/` folder of the project (when started with `love .`);
in a packaged build they go to the LÖVE save directory.

### Changing Grid Size
Press `C` in the editor, enter the new width and height (1-1000) and confirm with `Enter`.
Tiles outside a smaller canvas are removed. The default size for a new session can still be
changed with `gridWidth` and `gridHeight` in `scripts/settings.lua`.

### Running the tests
The pure level logic (`scripts/level.lua`: TXT/JSON/TMX, flood fill, lines) has tests that
do not need LÖVE:
```bash
lua tests/run.lua    # or: luajit tests/run.lua
```

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

### LICENSE
[LICENSE](LICENSE)