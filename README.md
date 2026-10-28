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
- Main menu, save/open screens with a scrolling level list (date, size) and overwrite confirmation
- Unsaved-changes indicator and a quiet background check for new releases

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
- `P` - save, `Ctrl+S` - quick save under the current name and format, `L` - open a saved level (TXT)
- `Esc` - back to the main menu (your work stays open, choose **Continue** to return to it)

### Main menu
`Up` / `Down` + `Enter` or the mouse. **Continue** appears when there is a level in the editor.
**New level** asks for confirmation if there are unsaved changes (shown as `*` after the name in the
HUD and in the window title). `Esc` in the menu goes back to the editor (or quits when nothing is open).

### Save and open screens
- Save (`P`): type a name, pick the format with `Tab` / the mouse (TXT can be opened again, JSON and TMX are
  export-only), `Enter` saves. Existing files of that format are listed below: pick one with
  `Up` / `Down` / the wheel to overwrite it. Overwriting always asks for confirmation.
- Open (`L`): the list is sorted by date (`Tab` switches to sorting by name); `Up` / `Down`,
  `PgUp` / `PgDn`, `Home` / `End` and the mouse wheel scroll; `Enter` or a double click opens.
- Success and error messages appear as toasts at the top of the screen.
- Wheel scrolling also works in the asset pack list (`T`).

The interface text is in English because the bundled default font has no Cyrillic glyphs.

### Update check
At startup Levelarium asks `https://api.github.com/repos/ruffbuff/Levelarium/releases/latest`
once, in a background thread, and compares `tag_name` with the version in `scripts/settings.lua`.
If a newer release exists, the menu shows "Version X is available" - click it or press `U` to open
the release page in the browser. It needs the system `curl` (Windows 10+, macOS and most Linux
distributions have it); without curl, offline, on timeouts (5 s connect / 10 s total) or on any
other error nothing happens and nothing is shown. Disable it with `checkUpdates = false` in
`scripts/settings.lua`.

To test it without publishing a release:
```bash
python3 -m http.server 8000 --directory some_dir_with_release_json &
LEVELARIUM_UPDATE_URL=http://127.0.0.1:8000/release.json LEVELARIUM_TEST_VERSION=1.0.0 love .
```
`release.json` only needs `tag_name` and `html_url` fields.

Levels are saved to the `levels/` folder of the project (when started with `love .`);
in a packaged build they go to the LÖVE save directory.

### Changing Grid Size
Press `C` in the editor, enter the new width and height (1-1000) and confirm with `Enter`.
Tiles outside a smaller canvas are removed. The default size for a new session can still be
changed with `gridWidth` and `gridHeight` in `scripts/settings.lua`.

### Running the tests
The pure logic (`scripts/level.lua`: TXT/JSON/TMX, flood fill, lines; `version.lua`, `files.lua`,
`list.lua` and `updater.lua` parsing: version comparison, file list sorting, list scrolling) has tests
that do not need LÖVE:
```bash
lua tests/run.lua    # or: luajit tests/run.lua
```

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

### LICENSE
[LICENSE](LICENSE)