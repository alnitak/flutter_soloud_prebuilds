# flutter_soloud_prebuilds

Automated reproducible builds of precompiled [Xiph.org](https://www.xiph.org/) libraries (`ogg`, `vorbis`, `opus`, `flac`) for the [flutter_soloud](https://github.com/alnitak/flutter_soloud) audio plugin.

## Pinned Upstream Commits
- **ogg**: `https://github.com/xiph/ogg` @ `db5c7a4`
- **vorbis**: `https://github.com/xiph/vorbis` @ `84c0236`
- **opus**: `https://github.com/xiph/opus` @ `c79a9bd`
- **flac**: `https://github.com/xiph/flac` @ `9547dbc`

## Supported Targets

| Platform | Architectures / ABIs | Format |
| :--- | :--- | :--- |
| **Android** | `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` | Shared `.so` (16k page-size aligned) |
| **Linux** | `x86_64`, `arm64` (aarch64) | Shared `.so` |
| **macOS** | Universal (`arm64` + `x86_64`) | Static archive `.a` |
| **iOS** | Device (`arm64`), Simulator Universal (`arm64` + `x86_64`) | Static archive `.a` |
| **Windows** | `x86_64`, `arm64` | Shared `.dll` + `.lib` |
| **Headers** | Universal C includes | `include/` directory |

## Local Build
```bash
# Get dependencies
dart pub get

# Build for current host platform
dart run tool/build.dart

# Build for specific platform
dart run tool/build.dart --os=android
dart run tool/build.dart --os=ios
dart run tool/build.dart --os=linux --arch=arm64
dart run tool/build.dart --os=macos
dart run tool/build.dart --os=windows

# Build for all platforms
dart run tool/build.dart --os=all

# Package output into dist/
dart run tool/package.dart output dist
```

## Release Process
Binaries are built and published automatically via GitHub Actions:
- Push a tag: `git tag v1.0.0 && git push origin v1.0.0`
- Or trigger manually via the **Run workflow** button on GitHub Actions.
