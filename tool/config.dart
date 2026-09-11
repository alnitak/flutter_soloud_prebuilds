class XiphRepo {
  final String name;
  final String url;
  final String commit;

  const XiphRepo({
    required this.name,
    required this.url,
    required this.commit,
  });
}

const xiphRepos = [
  XiphRepo(
    name: 'ogg',
    url: 'https://github.com/xiph/ogg',
    commit: 'db5c7a4',
  ),
  XiphRepo(
    name: 'vorbis',
    url: 'https://github.com/xiph/vorbis',
    commit: '84c0236',
  ),
  XiphRepo(
    name: 'opus',
    url: 'https://github.com/xiph/opus',
    commit: 'c79a9bd',
  ),
  XiphRepo(
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
