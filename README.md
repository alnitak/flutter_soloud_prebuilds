# flutter_soloud_prebuilds

Automated reproducible builds of precompiled [Xiph.org](https://www.xiph.org/) libraries (`ogg`, `vorbis`, `opus`, `flac`) and the [Steinberg VST3 Hosting SDK](https://github.com/steinbergmedia/vst3sdk) (`vst3_hosting`) for the [flutter_soloud](https://github.com/alnitak/flutter_soloud) audio plugin.

## Pinned Upstream Commits
- **ogg**: `https://github.com/xiph/ogg` @ `db5c7a4`
- **vorbis**: `https://github.com/xiph/vorbis` @ `84c0236`
- **opus**: `https://github.com/xiph/opus` @ `c79a9bd`
- **flac**: `https://github.com/xiph/flac` @ `9547dbc`
- **vst3sdk**: `https://github.com/steinbergmedia/vst3sdk` @ `3cdf9ca` (`v3.8.1_build_84`)

## Supported Targets

### Xiph Libraries (`ogg`, `vorbis`, `opus`, `flac`)

| Platform | Architectures / ABIs | Format | Archive |
| :--- | :--- | :--- | :--- |
| **Android** | `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` | Shared `.so` (16k page-size aligned) | `xiph-android.tar.gz` |
| **Linux** | `x86_64`, `arm64` (aarch64) | Shared `.so` | `xiph-linux-x64.tar.gz`, `xiph-linux-arm64.tar.gz` |
| **macOS** | Universal (`arm64` + `x86_64`) | Static archive `.a` | `xiph-macos.tar.gz` |
| **iOS** | Device (`arm64`), Simulator Universal (`arm64` + `x86_64`) | Static archive `.a` | `xiph-ios.tar.gz` |
| **Windows** | `x86_64`, `arm64` | Shared `.dll` + `.lib` | `xiph-windows-x64.zip`, `xiph-windows-arm64.zip` |
| **Headers** | Universal C includes | `include/` directory | `xiph-include.tar.gz` |

### Steinberg VST3 Hosting SDK (`vst3_hosting`)

| Platform | Architectures / ABIs | Format | Archive |
| :--- | :--- | :--- | :--- |
| **Linux** | `x86_64`, `arm64` (aarch64) | Static archive `libvst3_hosting.a` (`-fPIC`) | `vst3-linux-x64.tar.gz`, `vst3-linux-arm64.tar.gz` |
| **macOS** | Universal (`arm64` + `x86_64`) | Static archive `libvst3_hosting.a` | `vst3-macos.tar.gz` |
| **Windows** | `x86_64`, `arm64` | Static archive `vst3_hosting.lib` | `vst3-windows-x64.zip`, `vst3-windows-arm64.zip` |
| **Headers** | Universal C++ includes (`pluginterfaces/`, `base/`, `public.sdk/`) | `vst3/include/` directory | `vst3-include.tar.gz` |

## Local Build
```bash
# Get dependencies
dart pub get

# Build all libraries (Xiph + VST3) for current host platform
dart run tool/build.dart

# Build only VST3 or only Xiph
dart run tool/build.dart --os=macos --target=vst3
dart run tool/build.dart --os=macos --target=xiph

# Build for specific platform
dart run tool/build.dart --os=android --target=xiph
dart run tool/build.dart --os=ios --target=xiph
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
- Push a tag: `git tag v1.1.0 && git push origin v1.1.0`
- Or trigger manually via the **Run workflow** button on GitHub Actions.
