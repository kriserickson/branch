# Branch

Branch is a Mac-native file explorer for macOS 15 and later. It combines a synchronized folder tree with tabbed browsing, breadcrumbs, familiar file operations, Quick Look previews, and list or icon views.

## Run

Build a launchable personal-app bundle with:

```sh
zsh Scripts/build-app.sh
open .build/Branch.app
```

For development, `swift build` and `swift test` are also available. The packaging script accepts `debug` or `release` as its first argument and produces `.build/Branch.app`.

To debug in VS Code, install the CodeLLDB extension, open this folder, and start the `Debug Branch` configuration. The included tasks also provide `Build Branch.app (debug)` and `Test Branch`.

Branch is intentionally unsandboxed for the personal-app MVP so it can browse local files without repeatedly requesting folder access.
