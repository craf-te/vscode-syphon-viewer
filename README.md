# Syphon Viewer

Watch a Syphon video stream inside VS Code, in an editor tab beside your code.

Useful when you are writing shaders or building generative visuals in one
window and want to see the output without switching apps.

## Requirements

- macOS on Apple Silicon
- VS Code 1.135 or later

Intel Macs and Windows are not supported.

## Getting started

1. Start something that publishes over Syphon. TouchDesigner, Resolume,
   MadMapper, VDMX and Processing all can.
2. Run **Syphon Viewer: Open Preview** from the Command Palette.
3. Pick a server from the dropdown and press **Connect**.

The list updates as sources appear and disappear. If a source you were watching
comes back under the same name, the preview reconnects on its own.

## Fidelity

Frames arrive at the source resolution, uncompressed. The preview is
bit-identical to what the source published — no scaling, no codec, no chroma
subsampling, no colour drift.

There is nothing to tune. A frame is skipped whenever the previous one is still
being written, so the preview runs as fast as your machine allows and settles on
its own: roughly 60fps at 1080p, 30fps at 4K.

Processing stops entirely while the tab is in the background, so leaving the
preview open costs nothing when you are not looking at it.

## Settings

| Key | Default | Description |
|---|---|---|
| `syphonViewer.autoConnect` | `""` | Server name to connect to when the preview opens |

## License

MIT.

This extension bundles Syphon.framework, which is BSD 3-Clause licensed
(Copyright 2010 Tom Butterworth & Anton Marini). Its full license text ships
with the extension in `THIRD-PARTY-LICENSES.txt`.

Syphon Viewer is an independent project, not affiliated with or endorsed by
the Syphon Project.
