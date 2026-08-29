# Syphon Viewer

## Commit messages

**Write commit messages in English, and keep them short.**
This overrides the global preference for Japanese — it applies to commit
messages only. Conversation and code comments stay in Japanese.

- Subject: imperative mood, lower case after the type, no trailing period.
  Aim for 50 characters, hard limit 72.
- Body: only when the subject cannot carry the reason. Wrap at 72 characters.
  Explain *why*, not *what* — the diff already shows what changed.
- One short paragraph beats a bulleted retelling of the diff.

```
fix: wrap toolbar so narrow panels avoid horizontal scroll

Flex items do not shrink below their content width by default, so a long
server name pushed the Connect button off-screen.
```

## Things that are easy to get wrong here

- **Frames are uncompressed and must stay that way.** JPEG subsamples chroma
  below quality 1.0 and shifted saturated colour by up to 200/255. Do not
  reintroduce a codec without measuring against the source pixel by pixel.
- **There is no resolution or frame rate setting, deliberately.** `FrameSource`
  skips a frame while the previous write is still in flight. The check happens
  before `newFrameImage()`, so a skipped frame costs no GPU work.
- **`MessageDecoder` must not concatenate per chunk.** An 8.3MB frame arrives in
  ~130 pipe fragments; concatenating each time is O(n^2) and cost 61ms per
  frame. It buffers chunks and copies once.
- **Syphon's own releases are unusable** (2015, x86_64, no Metal).
  `scripts/fetch-syphon-framework.sh` pins a universal build and verifies its
  SHA256. See `docs/troubleshooting.md`.

## Verifying UI changes

Layout and rendering claims are checked against a real webview in
`test/e2e/suite/`, not by eye. If you change `media/`, run `npm run test:e2e`.
