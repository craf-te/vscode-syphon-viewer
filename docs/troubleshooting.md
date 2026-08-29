# Troubleshooting

## The server list is empty

Check that an app is actually publishing over Syphon. In TouchDesigner that
means a `Syphon Spout Out TOP` with an input connected.

The bundled test server narrows it down:

```bash
./helper/.build/release/TestSyphonServer --name Test
```

If that shows up in the list, the extension is fine and the problem is on the
publishing side.

## "Helper keeps exiting"

Open the **Syphon Viewer** output channel and look for `[helper]` lines.

`Library not loaded: @rpath/Syphon.framework` means Syphon.framework was not
found. In the extension's install directory, check that `bin/syphon-bridge` and
`Frameworks/Syphon.framework` sit under the same parent.

## Gatekeeper blocks the helper

A binary installed from a `.vsix` can pick up a quarantine attribute. In the
extension's install directory:

```bash
cd ~/.vscode/extensions/craf-te.syphon-viewer-*/
xattr -dr com.apple.quarantine bin/syphon-bridge Frameworks/Syphon.framework
```

## Playback stutters

Frames are uncompressed, so a 4K source moves about 1 GB/s at 60fps. The helper
skips a frame whenever the previous one is still being written, so it should
settle at a lower rate rather than stall — a 4K source typically lands around
30fps. If it stutters below that, something else on the machine is competing for
bandwidth.

There is nothing to configure. Resolution and frame rate were deliberately not
made settable.

## The image is upside down or mirrored

`FrameConverter.convert` flips with `oriented(.downMirrored)` because Metal
textures are top-left origin and CoreImage is bottom-left. If the image still
looks wrong, the publishing app is probably sending `flipped: true`. Check its
settings.

## Where Syphon.framework comes from

Syphon's own GitHub Releases stop at tag `5` (2015): x86_64 only, OpenGL only,
no modulemap. The `main` branch is still maintained and supports Metal and
arm64, but the maintainers do not ship binaries — see
[issue #64](https://github.com/Syphon/Syphon-Framework/issues/64).

The author of node-syphon hosts a universal build instead, with the Syphon
maintainers' agreement. It is the official repository cloned and compiled for
`-arch x86_64 -arch arm64`, unmodified.

`scripts/fetch-syphon-framework.sh` pins that build to `v1.1.5` and verifies its
SHA256.

## "Metal Toolchain" errors when building

Since Xcode 26 the Metal compiler is a separate component. It is only needed to
build Syphon.framework from source with `--build`:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The default fetch path does not need it.
