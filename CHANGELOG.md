# Changelog

## 1.0.1

Packaging only. Nothing changes in how the preview behaves.

- The vsix no longer ships the CI workflow file or a source map.
- The helper reports the same version as the extension.

## 1.0.0

First release.

- Show a Syphon server's video in a VS Code editor tab.
- Frames arrive at the source resolution, uncompressed, so the preview is
  bit-identical to what the source published.
- The server list follows Syphon announce and retire notifications live.
- Reconnects on its own when a server returns under the same name.
- Processing pauses while the tab is in the background.

There is no resolution or frame rate setting. The helper skips a frame whenever
the previous one is still being written, so it runs as fast as the machine
allows and degrades on its own — roughly 60fps at 1080p and 30fps at 4K.

macOS on Apple Silicon only.
