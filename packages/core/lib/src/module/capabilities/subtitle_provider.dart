import '../../models/result_page.dart';
import '../../models/subtitle_candidate.dart';
import '../../models/subtitle_file.dart';
import '../../models/subtitle_history_event.dart';
import '../../models/subtitle_language.dart';
import '../../models/subtitle_media.dart';
import '../../models/subtitle_media_type.dart';
import '../../models/subtitle_title.dart';
import '../../models/subtitle_want.dart';
import '../capability.dart';
import '../module_route.dart';
import '../service_result.dart';

/// Browsing and fetching subtitles. Pages start at 1.
abstract interface class SubtitleProvider implements Capability {
  /// Series known to the service.
  ServiceResult<ResultPage<SubtitleTitle>> browseSeries({int page = 1});

  /// Movies known to the service.
  ServiceResult<ResultPage<SubtitleTitle>> browseMovies({int page = 1});

  /// The episodes of a series.
  ServiceResult<List<SubtitleTitle>> browseEpisodes(int seriesId);

  /// Movies or episodes lacking subtitles.
  ServiceResult<ResultPage<SubtitleWant>> wanted(
    SubtitleMediaType type, {
    int page = 1,
  });

  /// In the server's order, newest first.
  ServiceResult<ResultPage<SubtitleHistoryEvent>> history(
    SubtitleMediaType type, {
    int page = 1,
  });

  /// The subtitle state of one title.
  ServiceResult<SubtitleTitle> forMedia(SubtitleMedia media);

  /// Has the service find and download [language].
  ServiceResult<void> autoSearch(
    SubtitleMedia media,
    SubtitleLanguage language,
  );

  /// Candidates from the providers.
  ServiceResult<List<SubtitleCandidate>> manualSearch(SubtitleMedia media);

  /// Downloads a candidate.
  ServiceResult<void> download(
    SubtitleMedia media,
    SubtitleCandidate candidate,
  );

  /// Deletes a subtitle file.
  ServiceResult<void> delete(SubtitleFile file);

  /// Synchronizes a subtitle file with its video.
  ServiceResult<void> sync(SubtitleFile file);

  /// The subtitle screen.
  ModuleRoute entryRoute();
}
