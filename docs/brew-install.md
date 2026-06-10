# Install with Homebrew

`apfel-plus` is available in homebrew-core:

```bash
brew install apfel-plus
```

Verify the install:

```bash
apfel-plus --version
apfel-plus --release
```

## Requirements

- Apple Silicon
- macOS 26.4 or newer
- Apple Intelligence enabled

Homebrew installs the `apfel-plus` binary. You do **not** need Xcode.

## Troubleshooting

If the binary runs but generation is unavailable, check:

```bash
apfel-plus --model-info
```

If you already installed `apfel-plus` manually into `/usr/local/bin/apfel-plus`, make sure the Homebrew binary is first in your `PATH`:

```bash
which apfel-plus
brew --prefix
```

## Maintainers

See [release.md](release.md) for the release workflow and Homebrew tap maintenance.
