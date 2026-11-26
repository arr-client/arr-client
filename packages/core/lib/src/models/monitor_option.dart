import '../module/localized_text.dart';

/// A choice of what to monitor, as the service offers it.
final class MonitorOption {
  /// Creates a [MonitorOption].
  const MonitorOption({required this.id, required this.label});

  /// The service's value.
  final String id;

  /// The name to show.
  final LocalizedText label;
}
