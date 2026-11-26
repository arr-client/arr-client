// What tool/sanitize_fixture.dart lets through. Everything here is a fixed word of a service's
// source code or a shape that cannot describe a user or a server. Field names are in lower case
// without punctuation, so "hearing_impaired" is 'hearingimpaired'.
//
// Add a value when a contract test needs it: something the app branches on, parses, formats or
// sends back. Text that is only shown (titles, messages, genres) is better left replaced.

/// Real field names that have too many digits to pass for one: Seerr passes them on from TMDB.
const knownFieldNames = {'iso_3166_1', 'iso_639_1'};

/// Whether [value], found in [field], may be kept.
bool isAllowedString(String value, String field) {
  if (_timestamp.hasMatch(value) || _duration.hasMatch(value)) return true;
  if (_mediaCover.hasMatch(value)) return true;
  if (field.endsWith('version')) {
    return value == 'unknown' || isVersion(value);
  }
  if (_fieldShapes[field]?.hasMatch(value) ?? false) return true;
  if (_fieldValues[field]?.contains(value) ?? false) return true;
  // "RefreshSeries", also written "Refresh Series".
  if (field == 'commandname') {
    return _commandNames.contains(value.replaceAll(' ', ''));
  }
  // Radarr history joins several flags into one string.
  if (field == 'indexerflags') {
    return value.split(', ').every(_indexerFlags.contains);
  }
  return _enumFields.contains(field) && _enumValues.contains(value);
}

/// Whether [value] is a version number that cannot be taken for an IP address.
bool isVersion(String value) {
  final match = _version.firstMatch(value);
  if (match == null) return false;
  final parts = match[1]!.split('.');
  // Four small numbers could be an IPv4 address.
  return parts.length < 4 || parts.any((part) => int.parse(part) > 255);
}

/// Plain text bodies that are kept as they are.
bool isSafePlainText(String text) =>
    _plainTextBodies.contains(text) || isVersion(text);

// qBittorrent. A login may also answer with an empty body.
const _plainTextBodies = {
  '',
  'Ok.',
  'Fails.',
  'Unauthorized',
  'Forbidden',
  'Your IP address has been banned after too many failed authentication '
      'attempts.',
};

final _timestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}'
  r'([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:?\d{2})?)?$',
);
final _duration = RegExp(r'^(\d{1,4}\.)?\d{2}:[0-5]\d:[0-5]\d(\.\d{1,9})?$');
final _version = RegExp(
  r'^v?(\d{1,2}(?:\.\d{1,5}){1,3})'
  r'(?:-(?:develop|nightly|beta|alpha|rc)(?:\.\d{1,4})?|(?:alpha|beta|rc)\d{1,2})?$',
);
// The cache buster is the file's write time, or in newer Radarr and Sonarr the first 20 hex
// digits, in lower case, of the SHA-256 of the cover's public source URL (MediaCoverService.cs).
final _mediaCover = RegExp(
  r'^/MediaCover(/Albums|/Books)?(/\d{1,9})?'
  r'/(poster|banner|fanart|cover|logo|clearlogo|disc|screenshot|headshot)'
  r'(-\d{2,4})?\.(jpg|jpeg|png)(\?(lastWrite=\d{1,20}|h=[0-9a-f]{20}))?$',
);

final _languageCode = RegExp(r'^[a-z]{2,3}$');
// Bazarr: a language, optionally with country, script and kind, as in "pt-BR:hi".
final _languageTag = RegExp(
  r'^[a-z]{2,3}(-[A-Z]{2})?(-[A-Z][a-z]{3})?(:(hi|forced))?$',
);
// Sonarr and Radarr media info: "eng/jpn".
final _languageList = RegExp(r'^[a-z]{2,3}(/[a-z]{2,3}){0,30}$');
// Bazarr sends these booleans as Python strings and takes original_format back.
final _pythonBool = RegExp(r'^(True|False)$');
// History "data" holds numbers as strings.
final _number = RegExp(r'^-?\d{1,19}(\.\d{1,20})?$');
final _isbn = RegExp(r'^97[89]\d{10}$');

/// Shapes that are harmless in the named field only.
final _fieldShapes = <String, RegExp>{
  // Numbers as strings
  'age': _number,
  'agehours': _number,
  'ageminutes': _number,
  'customformatscore': _number,
  'fileid': _number,
  'indexerid': _number,
  'preferredwordscore': _number,
  'size': _number,
  'tmdbid': _number,
  'tvdbid': _number,
  // 1 is Usenet and 2 torrent in history data.
  'protocol': RegExp(r'^[12]$'),

  // Public catalogue ids
  'imdbid': RegExp(r'^(tt\d{7,9}|0)$'),
  'isbn': _isbn,
  'isbn13': _isbn,

  // Languages
  'audiolanguages': _languageList,
  'code2': _languageCode,
  'code3': _languageCode,
  // Country and language codes; the keys are iso_3166_1 and iso_639_1.
  'iso31661': RegExp(r'^[A-Z]{2}$'),
  'iso6391': RegExp(r'^[a-z]{2}$'),
  'language': _languageTag,
  'originallanguage': _languageCode,
  'subtitles': _languageList,

  // Times
  'airtime': RegExp(r'^([01]\d|2[0-3]):[0-5]\d$'),
  // m:ss or h:mm:ss
  'runtime': RegExp(r'^(\d{1,2}:[0-5]\d|[0-5]?\d):[0-5]\d$'),
  'year': RegExp(r'^(19|20)\d\d$'),

  // Media info
  'audiobitrate': RegExp(r'^\d{1,5} kbps$'),
  'audiobits': RegExp(r'^\d{1,2}bit$'),
  'audiosamplerate': RegExp(r'^\d{1,3}(\.\d)?kHz$'),
  'resolution': RegExp(r'^\d{3,5}x\d{3,5}$'),

  // Bazarr
  'episodenumber': RegExp(r'^\d{1,4}x\d{1,4}$'),
  'forced': _pythonBool,
  'hearingimpaired': _pythonBool,
  'hi': _pythonBool,
  'originalformat': _pythonBool,
  'parsedtimestamp': RegExp(r'^\d\d/\d\d/\d\d \d\d:\d\d:\d\d$'),
  'score': RegExp(r'^\d{1,3}(\.\d{1,2})?%$'),
  // History shows this text as it is.
  'timestamp': RegExp(
    r'^(now|just now|yesterday|tomorrow|(last|next) (week|month|year)|'
    r'(a|an|\d{1,4}) (second|minute|hour|day|week|month|year)s? ago)$',
  ),

  // Servarr validation errors, as in "MovieExistsValidator".
  'errorcode': RegExp(r'^([A-Z][a-z]+){1,6}Validator$'),

  // Sorting, as echoed by paged responses.
  'sortkey': RegExp(
    r'^((series|episodes?|movies?|movieMetadata|artists?|albums?|authors?|'
    r'books?)\.)?(sortTitle|title|airDateUtc|releaseDate|lastSearchTime|date|'
    r'timeleft|id)$',
  ),
};

/// Exact words that are harmless in the named field only.
final _fieldValues = <String, Set<String>>{
  'appname': {'Sonarr', 'Radarr', 'Lidarr', 'Readarr', 'Prowlarr'},
  'message': {'invalid csrf token'}, // Seerr
  'name': {
    ..._commandNames,
    ..._qualityNames,
    ..._languageNames,
    ..._indexerCategories,
  },
  // A quality definition's title starts as the quality's name.
  'title': _qualityNames,
  'source': _healthChecks,
  'propertyname': {
    'ForeignAlbumId',
    'ForeignArtistId',
    'ForeignAuthorId',
    'ForeignBookId',
    'MetadataProfileId',
    'Path',
    'QualityProfileId',
    'RootFolderPath',
    'Title',
    'TitleSlug',
    'TmdbId',
    'TvdbId',
  },

  // History data
  'reason': {
    'MissingFromDisk',
    'Manual',
    'Upgrade',
    'NoLinkedEpisodes',
    'ManualOverride',
  },
  'releasesource': {
    'Unknown',
    'Rss',
    'Search',
    'UserInvokedSearch',
    'InteractiveSearch',
    'ReleasePush',
  },
  'releasetype': {
    'Unknown',
    'SingleEpisode',
    'MultiEpisode',
    'SeasonPack',
    'MultiSeasonPack',
  },
  'moviematchtype': _matchTypes,
  'seriesmatchtype': _matchTypes,

  // Media info
  'audiocodec': {
    'AAC', 'AC3', 'ALAC', 'APE', 'DTS', 'DTS 96/24', 'DTS Express', 'DTS-ES',
    'DTS-HD HRA', 'DTS-HD MA', 'DTS-X', 'EAC3', 'EAC3 Atmos', 'FLAC', 'HE-AAC',
    'MP1', 'MP2', 'MP3', 'OGG', 'OPUS', 'Opus', 'PCM', 'TrueHD',
    'TrueHD Atmos', 'Unknown', 'Vorbis', 'WMA', 'WavPack', 'xHE-AAC', //
  },
  'videocodec': {
    'AV1', 'AVC', 'DivX', 'HEVC', 'MPEG', 'MPEG2', 'VC1', 'VP6', 'VP7', 'VP8',
    'VP9', 'VVC', 'WMV', 'XviD', 'h264', 'h265', 'h266', 'x264', 'x265',
    'x266', //
  },
  'videodynamicrange': {'HDR'},
  'videodynamicrangetype': {
    'DV', 'DV HDR10', 'DV HDR10Plus', 'DV HLG', 'DV SDR', 'HDR', 'HDR10',
    'HDR10Plus', 'HLG', 'PQ', //
  },
  'scantype': {'Progressive', 'Interlaced', 'MBAFF', 'PAFF'},

  'certification': {
    'G', 'PG', 'PG-13', 'R', 'NC-17', 'NR', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG',
    'TV-14', 'TV-MA', //
  },

  // Lidarr
  'albumtype': {'Album', 'EP', 'Single', 'Broadcast', 'Other'},
  'secondarytypes': {
    'Studio', 'Compilation', 'Soundtrack', 'Spokenword', 'Interview',
    'Audiobook', 'Live', 'Remix', 'DJ-mix', 'Mixtape/Street', 'Demo',
    'Audio drama', //
  },
  'artisttype': {
    'Person', 'Group', 'Orchestra', 'Choir', 'Character', 'Other', //
  },

  // Prowlarr
  'privacy': {'public', 'semiPrivate', 'private'},

  // Seerr passes on TMDB's wording.
  'status': {
    'Rumored', 'Planned', 'In Production', 'Post Production', 'Released',
    'Canceled', 'Returning Series', 'Ended', 'Pilot', //
  },

  // Bazarr
  'matches': _subtitleMatches,
  'dontmatches': _subtitleMatches,
};

const _matchTypes = {'Unknown', 'Title', 'Alias', 'Id', 'Grabbed'};

const _subtitleMatches = {
  'hash', 'title', 'series', 'year', 'season', 'episode', 'release_group',
  'source', 'audio_codec', 'resolution', 'video_codec', 'hearing_impaired',
  'streaming_service', 'edition', 'country', 'imdb_id', 'series_imdb_id',
  'tvdb_id', 'series_tvdb_id', //
};

// Radarr, then Prowlarr. "0" is none.
const _indexerFlags = {
  '0',
  'G_Freeleech',
  'G_Halfleech',
  'G_DoubleUpload',
  'PTP_Golden',
  'PTP_Approved',
  'G_Internal',
  'AHD_Internal',
  'G_Scene',
  'G_Freeleech75',
  'G_Freeleech25',
  'AHD_UserRelease',
  'Nuked',
  'internal',
  'exclusive',
  'freeleech',
  'neutralleech',
  'halfleech',
  'scene',
  'doubleupload',
};

// Class names of src/NzbDrone.Core/HealthCheck/Checks in the five Servarr services.
const _healthChecks = {
  'AllowedHostsCheck', 'ApiKeyValidationCheck', 'AppDataLocationCheck',
  'ApplicationLongTermStatusCheck', 'ApplicationStatusCheck',
  'CalibreRootFolderCheck', 'DownloadClientCheck',
  'DownloadClientRemovesCompletedDownloadsCheck',
  'DownloadClientRootFolderCheck', 'DownloadClientSortingCheck',
  'DownloadClientStatusCheck', 'FpcalcCheck', 'ImportListRootFolderCheck',
  'ImportListStatusCheck', 'ImportMechanismCheck', 'IndexerCheck',
  'IndexerDownloadClientCheck', 'IndexerJackettAllCheck',
  'IndexerLongTermStatusCheck', 'IndexerNoDefinitionCheck',
  'IndexerProxyStatusCheck', 'IndexerRssCheck', 'IndexerSearchCheck',
  'IndexerStatusCheck', 'IndexerVIPCheck', 'IndexerVIPExpiredCheck',
  'MountCheck', 'MovieCollectionRootFolderCheck', 'NamingConfigCheck',
  'NotificationStatusCheck', 'OidcConfigurationCheck',
  'OutdatedDefinitionCheck', 'PTPOldSettingsCheck',
  'PackageGlobalMessageCheck', 'PasswordResetTokenCheck', 'PluginCheck',
  'ProxyCheck', 'RecyclingBinCheck', 'RedactedGazelleCheck',
  'ReleaseBranchCheck', 'RemotePathMappingCheck', 'RemovedArtistCheck',
  'RemovedMovieCheck', 'RemovedSeriesCheck', 'RootFolderCheck',
  'SlackUrlCheck', 'SqliteVersionCheck', 'SystemTimeCheck', 'UpdateCheck', //
};

// Commands the app sends or is likely to see running.
const _commandNames = {
  'AlbumSearch', 'ArtistSearch', 'AuthorSearch', 'BookSearch',
  'BulkRefreshArtist', 'BulkRefreshAuthor', 'BulkRefreshBook', 'CheckHealth',
  'CutoffUnmetAlbumSearch', 'CutoffUnmetBookSearch',
  'CutoffUnmetEpisodeSearch', 'CutoffUnmetMoviesSearch', 'EpisodeSearch',
  'ManualImport', 'MissingAlbumSearch', 'MissingBookSearch',
  'MissingEpisodeSearch', 'MissingMoviesSearch', 'MoviesSearch',
  'ProcessMonitoredDownloads', 'RefreshAlbum', 'RefreshArtist',
  'RefreshAuthor', 'RefreshBook', 'RefreshMonitoredDownloads', 'RefreshMovie',
  'RefreshSeries', 'RescanFolders', 'RescanMovie', 'RescanSeries', 'RssSync',
  'SeasonSearch', 'SeriesSearch', //
};

// Quality.cs of Sonarr, Radarr, Lidarr and Readarr.
const _qualityNames = {
  'Unknown', 'SDTV', 'DVD', 'DVD-R', 'DVDSCR', 'REGIONAL', 'WORKPRINT', 'CAM',
  'TELESYNC', 'TELECINE', 'BR-DISK', 'Raw-HD', 'HDTV-720p', 'HDTV-1080p',
  'HDTV-2160p', 'WEBDL-480p', 'WEBDL-720p', 'WEBDL-1080p', 'WEBDL-2160p',
  'WEBRip-480p', 'WEBRip-720p', 'WEBRip-1080p', 'WEBRip-2160p',
  'Bluray-480p', 'Bluray-576p', 'Bluray-720p', 'Bluray-1080p',
  'Bluray-2160p', 'Bluray-1080p Remux', 'Bluray-2160p Remux', 'Remux-1080p',
  'Remux-2160p', //
  'MP3-8', 'MP3-16', 'MP3-24', 'MP3-32', 'MP3-40', 'MP3-48', 'MP3-56',
  'MP3-64', 'MP3-80', 'MP3-96', 'MP3-112', 'MP3-128', 'MP3-160', 'MP3-192',
  'MP3-224', 'MP3-256', 'MP3-320', 'MP3-VBR-V0', 'MP3-VBR-V2', 'AAC-192',
  'AAC-256', 'AAC-320', 'AAC-VBR', 'WMA', 'WAV', 'APE', 'WavPack', 'FLAC',
  'FLAC 24bit', 'ALAC', 'ALAC 24bit', 'OGG Vorbis Q5', 'OGG Vorbis Q6',
  'OGG Vorbis Q7', 'OGG Vorbis Q8', 'OGG Vorbis Q9', 'OGG Vorbis Q10', //
  'Unknown Text', 'Unknown Audio', 'PDF', 'MOBI', 'EPUB', 'AZW3', 'MP3', 'M4B',
};

// Language.cs of Sonarr and Radarr.
const _languageNames = {
  'Afrikaans', 'Albanian', 'Any', 'Arabic', 'Azerbaijani', 'Bengali',
  'Bosnian', 'Bulgarian', 'Catalan', 'Chinese', 'Croatian', 'Czech', 'Danish',
  'Dutch', 'English', 'Estonian', 'Finnish', 'Flemish', 'French', 'Georgian',
  'German', 'Greek', 'Hebrew', 'Hindi', 'Hungarian', 'Icelandic',
  'Indonesian', 'Irish', 'Italian', 'Japanese', 'Kannada', 'Korean',
  'Latvian', 'Lithuanian', 'Macedonian', 'Malay', 'Malayalam', 'Marathi',
  'Mongolian', 'Norwegian', 'Original', 'Persian', 'Polish', 'Portuguese',
  'Portuguese (Brazil)', 'Romanian', 'Romansh', 'Russian', 'Serbian',
  'Slovak', 'Slovenian', 'Spanish', 'Spanish (Latino)', 'Swedish', 'Tagalog',
  'Tamil', 'Telugu', 'Thai', 'Turkish', 'Ukrainian', 'Unknown', 'Urdu',
  'Uzbek', 'Vietnamese', //
};

// Prowlarr's NewznabStandardCategory.cs.
const _indexerCategories = {
  'Other', 'Other/Misc', 'Other/Hashed', 'Console', 'Console/NDS',
  'Console/PSP', 'Console/Wii', 'Console/XBox', 'Console/XBox 360',
  'Console/Wiiware', 'Console/XBox 360 DLC', 'Console/PS3', 'Console/Other',
  'Console/3DS', 'Console/PS Vita', 'Console/WiiU', 'Console/XBox One',
  'Console/PS4', 'Movies', 'Movies/Foreign', 'Movies/Other', 'Movies/SD',
  'Movies/HD', 'Movies/UHD', 'Movies/BluRay', 'Movies/3D', 'Movies/DVD',
  'Movies/WEB-DL', 'Movies/x265', 'Audio', 'Audio/MP3', 'Audio/Video',
  'Audio/Audiobook', 'Audio/Lossless', 'Audio/Other', 'Audio/Foreign', 'PC',
  'PC/0day', 'PC/ISO', 'PC/Mac', 'PC/Mobile-Other', 'PC/Games',
  'PC/Mobile-iOS', 'PC/Mobile-Android', 'TV', 'TV/WEB-DL', 'TV/Foreign',
  'TV/SD', 'TV/HD', 'TV/UHD', 'TV/Other', 'TV/Sport', 'TV/Anime',
  'TV/Documentary', 'TV/x265', 'XXX', 'XXX/DVD', 'XXX/WMV', 'XXX/XviD',
  'XXX/x264', 'XXX/UHD', 'XXX/Pack', 'XXX/ImageSet', 'XXX/Other', 'XXX/SD',
  'XXX/WEB-DL', 'Books', 'Books/Mags', 'Books/EBook', 'Books/Comics',
  'Books/Technical', 'Books/Other', 'Books/Foreign', //
};

// An enum word below survives only in one of these fields.
const _enumFields = {
  'authentication',
  'covertype',
  'eventtype',
  'finaletype',
  'mediatype',
  'minimumavailability',
  'mode',
  'modifier',
  'monitornewitems',
  'name',
  'priority',
  'protocol',
  'releasetype',
  'result',
  'seriestype',
  'severity',
  'sortdirection',
  'sortkey',
  'source',
  'sourcetype',
  'state',
  'status',
  'trackeddownloadstate',
  'trackeddownloadstatus',
  'trigger',
  'type',
};

// Matched exactly. None of them describes a user or a server.
const _enumValues = {
  // Common
  'unknown', 'none', 'all', 'new', 'ok', 'notice', 'warning', 'error',
  'info', 'low', 'normal', 'high', 'auto', 'manual', 'scheduled', 'unspecified',
  'successful', 'unsuccessful', 'indeterminate', 'ascending', 'descending',
  'default', 'console',
  // Servarr queue, commands and history
  'queued', 'paused', 'downloading', 'completed', 'failed', 'delay', 'delayed',
  'downloadClientUnavailable', 'fallback', 'importBlocked', 'importPending',
  'importing', 'imported', 'failedPending', 'ignored', 'downloadFailed',
  'downloadFailedPending', 'started', 'aborted', 'cancelled', 'orphaned',
  'grabbed', 'seriesFolderImported', 'downloadFolderImported',
  'movieFileDeleted', 'movieFolderImported', 'movieFileRenamed',
  'episodeFileDeleted', 'episodeFileRenamed', 'downloadIgnored',
  'trackFileImported', 'trackFileDeleted', 'trackFileRenamed',
  'albumImportIncomplete', 'downloadImported', 'bookFileImported',
  'bookFileDeleted', 'bookFileRenamed', 'bookImportIncomplete',
  'releaseGrabbed', 'indexerQuery', 'indexerRss', 'indexerAuth', 'usenet',
  'torrent', 'artistFolderImported', 'trackFileRetagged', 'bookFileRetagged',
  'indexerInfo',
  // Lidarr and Readarr name a protocol by its class, and have their own
  // tracked download states.
  'TorrentDownloadProtocol', 'UsenetDownloadProtocol', 'importFailed',
  // Servarr releases, credits and episodes
  'permanent', 'temporary', 'cast', 'crew', 'series', 'season', 'midseason',
  'singleEpisode', 'multiEpisode', 'seasonPack', 'multiSeasonPack',
  // Servarr library and media
  'continuing', 'ended', 'upcoming', 'deleted', 'tba', 'announced', 'inCinemas',
  'released', 'preDB', 'standard', 'daily', 'anime', 'poster', 'banner',
  'fanart', 'cover', 'logo', 'clearlogo', 'disc', 'screenshot', 'headshot',
  'television', 'televisionRaw', 'web', 'webdl', 'webRip', 'webrip', 'bluray',
  'blurayRaw', 'dvd', 'raw', 'tv', 'cam', 'telesync', 'telecine', 'workprint',
  'regional', 'screener', 'dvdscr', 'rawhd', 'brdisk', 'remux', 'imdb', 'tmdb',
  'trakt', 'rottenTomatoes', 'metacritic', 'user', 'critic', 'forms', 'basic',
  'external',
  // qBittorrent torrent states
  'missingFiles', 'uploading', 'pausedUP', 'stoppedUP', 'queuedUP', 'stalledUP',
  'checkingUP', 'forcedUP', 'allocating', 'metaDL', 'forcedMetaDL', 'pausedDL',
  'stoppedDL', 'queuedDL', 'stalledDL', 'checkingDL', 'forcedDL',
  'checkingResumeData', 'moving',
  // Seerr
  'movie', 'person', 'collection',
};
