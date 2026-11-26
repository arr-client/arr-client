import '../models/health_issue.dart';
import '../models/history_event.dart';
import '../models/item_ref.dart';
import '../models/media_request.dart';

/// One notification to show. The app words it and decides what a tap opens.
sealed class Notice {
  const Notice({required this.instanceId});

  /// The instance it is about.
  final String instanceId;
}

/// An item was imported.
final class ImportedNotice extends Notice {
  /// Creates an [ImportedNotice].
  const ImportedNotice({required super.instanceId, required this.event});

  /// The history event.
  final HistoryEvent event;
}

/// A download failed or needs attention.
final class DownloadProblemNotice extends Notice {
  /// Creates a [DownloadProblemNotice].
  const DownloadProblemNotice({
    required super.instanceId,
    required this.title,
    this.itemRef,
    this.downloadId,
  });

  /// The release's title.
  final String title;

  /// The item being downloaded, where the server knows it.
  final ItemRef? itemRef;

  /// The download client's id, where there is one.
  final String? downloadId;
}

/// A health problem is new or has worsened.
final class HealthNotice extends Notice {
  /// Creates a [HealthNotice].
  const HealthNotice({required super.instanceId, required this.issue});

  /// The problem as it is now.
  final HealthIssue issue;
}

/// A request is waiting for approval.
final class PendingRequestNotice extends Notice {
  /// Creates a [PendingRequestNotice].
  const PendingRequestNotice({
    required super.instanceId,
    required this.request,
  });

  /// The request as it is now.
  final MediaRequest request;
}

/// One of the user's own requests changed.
final class OwnRequestNotice extends Notice {
  /// Creates an [OwnRequestNotice].
  const OwnRequestNotice({required super.instanceId, required this.request});

  /// The request as it is now.
  final MediaRequest request;
}

/// Stands for all the events of one instance in one check, when there are more
/// than five.
final class SummaryNotice extends Notice {
  /// Creates a [SummaryNotice].
  const SummaryNotice({required super.instanceId, required this.count});

  /// How many events it stands for.
  final int count;
}
