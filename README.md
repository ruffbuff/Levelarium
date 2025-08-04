# Levelarium
Levelarium is a versatile and user-friendly level editor built with LÖVE2D. It allows you to create, edit, and save custom game levels using a tile-based system.

## Features
- Intuitive tile-based level editing
- Multiple drawing tools: Brush, Eraser, Bucket Fill, Line, and Rectangle
- Customizable grid size and tile set
- Camera pan and zoom for easy navigation
- Save and load level functionality


### Prerequisites
- [LÖVE2D](https://love2d.org/) (version 11.5 or later)
- [Lua](https://www.lua.org/) (version 5.1.5 or later)

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
- Use the mouse to select tiles and draw on the grid
- Press number keys 1-5 to switch between tools:
  1. Brush
  2. Eraser
  3. Bucket Fill
  4. Line
  5. Rectangle
- Use WASD keys to pan the camera
- Scroll wheel to zoom in/out
- Press 'P' to save the level
- Press 'L' to load a saved level
- Press 'ESC' to return to the main menu

### Changing Grid Size
To modify the grid size, edit the `gridWidth` and `gridHeight` values in `scripts/settings.lua`:

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

### LICENSE
[LICENSE](LICENSE)