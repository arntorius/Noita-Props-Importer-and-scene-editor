# Prop Placement Editor for Noita

A general-purpose in-game prop placement editor for Noita.

Build and save scenes using custom PNGs, animated spritesheets, and supported vanilla Noita props. Props can be spawned multiple times, positioned precisely, layered, deleted, and saved as complete layouts.

## Features

- Custom PNG and animated spritesheet support
- Vanilla Noita prop library
- Multiple instances of each prop
- 1 px and 10 px positioning controls
- Adjustable Z layer / rendering depth
- Move selected props to the player
- Delete individual props
- Save and load complete scenes
- CSV layout import/export
- Minimizable editor UI

## Installation

Place the mod here:

    Noita/
    └── mods/
        └── prop_placement_editor/

Then enable the mod from Noita's Mods menu.

## Custom Props

Place custom PNG files in:

    prop_placement_editor/files/gfx/

Example:

    lamp.png
    poster.png
    table.png

Press `REFRESH GFX` in the editor after adding new files.

Static PNGs are automatically added to the Custom Prop Library. Select a prop and press `SPAWN` to create an instance in the world.

## Animated Spritesheets

For animations, use the recommended filename format:

    Name__sheet_WIDTHxHEIGHT_FRAMECOUNT_SPEED.png

Example:

    Tree__sheet_90x40_4_0.10.png

This means:

    Frame size:   90 × 40 px
    Frame count:  4
    Frame time:   0.10 seconds

A four-frame horizontal sheet would therefore be 360 × 40 px.

The editor automatically calculates how many frames fit per row. Animated props are marked with `[ANIM]` in the Prop Library.

### Short Formats

The frame count and speed can be omitted:

    Tree__sheet_90x40.png
    Tree__sheet_90x40_4.png

When possible, the editor determines missing information from the image dimensions.

For complex or multi-row animations, the full format is recommended.

Example:

    Bushes__sheet_55x70_122_0.04.png

This defines 122 frames at 55 × 70 px with a frame time of 0.04 seconds.

Explicit frame counts are especially important when the final row contains unused transparent cells. Otherwise those cells may be played and cause blinking.

## Vanilla Props

Open:

    PROPS → VANILLA

to browse supported vanilla Noita props.

Once spawned, vanilla and custom props use the same positioning, layering, deletion, and scene-saving tools.

## Creating a Scene

A typical workflow:

1. Add custom PNGs or spritesheets to `files/gfx`.
2. Press `REFRESH GFX`.
3. Open the Prop Library.
4. Select a custom or vanilla prop.
5. Press `SPAWN`.
6. Position the prop using the 1 px or 10 px controls.
7. Adjust its Z layer if necessary.
8. Repeat to build your scene.
9. Press `SAVE LAYOUT`.

The same prop can be spawned multiple times. Each instance can be positioned and deleted independently.

## Saving and Loading

`SAVE LAYOUT` saves the current scene to:

    layout.csv

`LOAD LAYOUT` reconstructs the saved scene.

The editor also provides:

    EXPORT CSV
    IMPORT CSV

for transferring or externally editing layouts.

Use `CLEAR` to remove the currently placed editor props and start a new scene.

## Spritesheet Troubleshooting

If an animation appears as one large static image, verify the frame dimensions in its filename.

For example, a 360 × 40 image containing four equal horizontal frames uses 90 × 40 frames:

    MyAnimation__sheet_90x40_4_0.10.png

If an animation blinks at the end, specify the actual number of visible frames. This prevents unused transparent cells from being included in the animation.

For spritesheets where automatic detection is ambiguous, always use the full filename format:

    Name__sheet_WIDTHxHEIGHT_FRAMECOUNT_SPEED.png

## Important

- Custom graphics belong in `files/gfx`.
- Press `REFRESH GFX` after adding artwork.
- Keep the mod folder named `prop_placement_editor`.
- Use explicit frame dimensions for spritesheets when needed.
- Specify the real frame count if a spritesheet contains unused cells.
- Save your layout before making major scene changes.

## Example

    prop_placement_editor/
    ├── files/
    │   ├── gfx/
    │   │   ├── lamp.png
    │   │   ├── poster.png
    │   │   └── Tree__sheet_90x40_4_0.10.png
    │   └── generated/
    ├── init.lua
    ├── layout.csv
    └── mod.xml

Have fun building scenes!
