<p align="center"><img src="icon.png"/></p>

# Traktion

Arcade racing in Godot 4.7. Built on Kenney's racing starter kit: pick a car, run one lap, beat your ghosts.

### Screenshot

<p align="center"><img src="screenshots/screenshot.png"/></p>

### Play

Open the project in **Godot 4.7** and run `scenes/main.tscn`.

On the menu the camera orbits the car. Use the on-screen arrows to choose a vehicle, then **START**.

| Key | In race |
| --- | --- |
| <kbd>W</kbd> | Accelerate |
| <kbd>S</kbd> | Brake / reverse |
| <kbd>A</kbd> <kbd>D</kbd> | Steer |

The timer starts when you move. Cross the far corner, then the finish line to complete a lap. **AGAIN** puts you back on the start grid.

- Vehicles: truck, motorcycle, racer, future, hatchback, sports, taxi, police, SUV
- Last five lap times are stored locally
- Ghosts replay your four fastest runs (they wait until you launch, then fade when they get close)
- Steering needs speed; the car coasts until you brake

### Track

Select the **GridMap** node to paint tiles from `models/Library/mesh-library.tres`. Library pieces live in `models/Library/mesh-library.tscn` — instance a GLB there, then **Scene → Export As → MeshLibrary…** and merge into the existing `.tres` so old cell IDs stay put.

### Cars

Garage models are swapped at runtime from `models/cars/` (plus the yellow truck and motorcycle). New cars should include:

- `body`
- `wheel-front-left` / `wheel-front-right` / `wheel-back-left` / `wheel-back-right`  
  (motorcycle uses `wheel-front` and `wheel-back`)

Kenney vehicle GLBs expect `models/cars/Textures/colormap.png`.

### License

MIT License. Original starter kit © Kenney.

3D models, sprites, audio, and UI from [Kenney](https://kenney.nl) are [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
