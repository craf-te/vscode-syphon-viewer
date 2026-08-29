# Development

```bash
npm install
npm run build      # Swift helper + extension bundle
npm test           # TypeScript and Swift tests
npm run test:e2e   # E2E tests inside VS Code
npm run package    # build a darwin-arm64 .vsix
swift scripts/make-icon.swift   # regenerate the icon
```

A test Syphon server is included, so no external app is needed:

```bash
./helper/.build/release/TestSyphonServer --name Test
```

## Syphon.framework

`scripts/fetch-syphon-framework.sh` prepares `vendor/Syphon.framework`. The
build is already committed, so this only runs on a fresh checkout.

```bash
./scripts/fetch-syphon-framework.sh            # pinned build, SHA256 checked
./scripts/fetch-syphon-framework.sh --latest   # newest release, no hash check
./scripts/fetch-syphon-framework.sh --build    # build from Syphon main
./scripts/fetch-syphon-framework.sh --force    # rebuild vendor/
```

See [troubleshooting.md](./troubleshooting.md) for why the pinned build is used
and when `--build` is worth it.

## Publishing

```bash
npm run package
npx vsce publish --target darwin-arm64
```

Only `darwin-arm64` is published. Without the target flag the extension would be
offered to Windows and Linux users, where it cannot work.
