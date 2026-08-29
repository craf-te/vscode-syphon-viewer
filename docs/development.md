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

## Releasing

Releases go through the **Release** workflow in GitHub Actions, run manually
from the Actions tab. One run does all of it: pick the version, update the
changelog, build, test, tag, cut the GitHub release and publish to the
Marketplace.

Inputs:

| Input | Meaning |
|---|---|
| `bump` | `patch`, `minor` or `major`. Ignored if `version` is set. |
| `version` | An exact `x.y.z`, when the bump is not what you want. |
| `notes` | The changelog entry. Defaults to commit subjects since the last tag. |
| `publish` | Untick to cut a GitHub release without touching the Marketplace. |

The Marketplace step needs a Personal Access Token with the
**Marketplace → Manage** scope, stored as the `VSCODE_MARKETPLACE` secret.

The job runs on an Apple Silicon runner and fails immediately if it is not,
since the helper is an arm64 binary linked against Syphon.framework. Publishing
is the last step, because it is the only one that cannot be undone.

To see what a release would do to the version and changelog without touching
anything:

```bash
node scripts/prepare-release.mjs --bump minor --dry-run
```

Only `darwin-arm64` is published. Without the target flag the extension would be
offered to Windows and Linux users, where it cannot work.
