class GitRepoConfig {
  final String name;
  final String url;
  final String commit;
  final List<String> submodules;

  const GitRepoConfig({
    required this.name,
    required this.url,
    required this.commit,
    this.submodules = const [],
  });
}

const xiphRepos = [
  GitRepoConfig(
    name: 'ogg',
    url: 'https://github.com/xiph/ogg',
    commit: 'db5c7a4',
  ),
  GitRepoConfig(
    name: 'vorbis',
    url: 'https://github.com/xiph/vorbis',
    commit: '84c0236',
  ),
  GitRepoConfig(
    name: 'opus',
    url: 'https://github.com/xiph/opus',
    commit: 'c79a9bd',
  ),
  GitRepoConfig(
    name: 'flac',
    url: 'https://github.com/xiph/flac',
    commit: '9547dbc',
  ),
];

const xiphLibNames = [
  'ogg',
  'opus',
  'vorbis',
  'vorbisenc',
  'vorbisfile',
  'FLAC',
];

/// Pinned Steinberg VST3 SDK release (v3.8.1_build_84) used to build the
/// desktop VST3 hosting static library (`libvst3_hosting.a` / `vst3_hosting.lib`)
/// and header archive (`vst3-include.tar.gz`).
const vst3SdkRepo = GitRepoConfig(
  name: 'vst3sdk',
  url: 'https://github.com/steinbergmedia/vst3sdk',
  commit: '3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96',
  submodules: [
    'cmake',
    'pluginterfaces',
    'base',
    'public.sdk',
  ],
);

const vst3LibName = 'vst3_hosting';
