# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-28

### Added
- Eyedropper: right click on the grid picks the tile under the cursor (current layer first,
  then the upper layers) and switches to the brush; the palette scrolls to the picked tile.
- `scripts/level.lua`: the pure level logic (TXT/JSON/TMX serialisation, TXT parsing, flood fill,
  line rasterisation, canvas trimming) moved out of `main.lua`, with no dependency on `love.*`.
- Tests for that logic: `lua tests/run.lua`.
- `CHANGELOG.md`.
- Maximum grid size (`maxGridSize` in `scripts/settings.lua`, 1000).

### Changed
- Level files are written and listed without `mkdir -p` / `ls` shell commands, so saving and
  loading work on Windows as well. In a packaged build levels go to the LÖVE save directory.
- Saving large levels is much faster (`table.concat` instead of string concatenation in loops).
- README: documented all hotkeys, the in-editor grid size dialog, the formats and the tests.

### Fixed
- Resizing the canvas to a smaller size did not remove tiles outside of it (the loop compared the new
  width with itself); the canvas dialog also showed stale values after loading a level.
- Bucket fill used recursion and crashed with `stack overflow` on large empty areas (100x100 and up).
- The key that opened the save dialog (`P`) ended up in the level name input.
- Clicking the left margin of the tile palette selected "tile 0"; clicks on the right edge or below the
  last row selected tiles from other rows.
- Dragging the brush/eraser over the tools panel or the palette painted tiles hidden under them.
- Right and middle mouse buttons painted like the left one, and releasing them finished line/rectangle.
- TMX export described the whole tileset as one 512x512 sprite sheet (`1.png`, 64 tiles hard-coded);
  now every tile image is a separate tile of an image-collection tileset.
- Loading a level crashed on an empty or corrupted TXT file and did not work with `\r\n` line endings.
- Entering a huge canvas size (e.g. 99999999) froze the editor; size is limited to 1000.
- Switching asset packs could leave the selected tile at 0 or the palette scrolled past the end.
- Level names consisting only of spaces are no longer accepted.
