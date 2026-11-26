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
  ServiceResult<ResultPage<SubtitleTitle>> browseSeries({int page = 1});

  ServiceResult<ResultPage<SubtitleTitle>> browseMovies({int page = 1});

  ServiceResult<List<SubtitleTitle>> browseEpisodes(int seriesId);

  ServiceResult<ResultPage<SubtitleWant>> wanted(
    SubtitleMediaType type, {
    int page = 1,
  });

  /// In the server's order, newest first.
  ServiceResult<ResultPage<SubtitleHistoryEvent>> history(
    SubtitleMediaType type, {
    int page = 1,
  });

  ServiceResult<SubtitleTitle> forMedia(SubtitleMedia media);

  ServiceResult<void> autoSearch(
    SubtitleMedia media,
    SubtitleLanguage language,
  );

  ServiceResult<List<SubtitleCandidate>> manualSearch(SubtitleMedia media);

  ServiceResult<void> download(
    SubtitleMedia media,
    SubtitleCandidate candidate,
  );

  ServiceResult<void> delete(SubtitleFile file);

  ServiceResult<void> sync(SubtitleFile file);

  ModuleRoute entryRoute();
}
