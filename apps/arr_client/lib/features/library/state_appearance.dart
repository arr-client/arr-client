import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// How an item's state looks: a word and an icon, with colour only helping.
extension StateAppearance on ItemState {
  String label(AppLocalizations strings) => switch (this) {
    ItemState.downloading => strings.libraryStateDownloading,
    ItemState.downloaded => strings.libraryStateDownloaded,
    ItemState.partial => strings.libraryStatePartial,
    ItemState.unmonitored => strings.libraryStateUnmonitored,
    ItemState.unreleased => strings.libraryStateUnreleased,
    ItemState.missing => strings.libraryStateMissing,
  };

  IconData get icon => switch (this) {
    ItemState.downloading => Icons.downloading,
    ItemState.downloaded => Icons.check_circle,
    ItemState.partial => Icons.incomplete_circle,
    ItemState.unmonitored => Icons.bookmark_border,
    ItemState.unreleased => Icons.schedule,
    ItemState.missing => Icons.error_outline,
  };

  Color color(ColorScheme colors) => switch (this) {
    ItemState.downloading => colors.tertiary,
    ItemState.downloaded => colors.primary,
    ItemState.missing => colors.error,
    ItemState.partial ||
    ItemState.unmonitored ||
    ItemState.unreleased => colors.onSurfaceVariant,
  };
}
