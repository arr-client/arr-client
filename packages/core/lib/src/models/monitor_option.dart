import '../module/localized_text.dart';

/// A choice of what to monitor, as the service offers it.
final class MonitorOption {
  const MonitorOption({required this.id, required this.label});

  /// The service's value.
  final String id;

  final LocalizedText label;
}
