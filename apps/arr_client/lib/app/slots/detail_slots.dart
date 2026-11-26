/// What the app puts on the detail screens of the modules.
library;

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import 'download_progress_slot.dart';

/// Fills [slot], for a [DetailSlotScope].
Widget buildDetailSlot(BuildContext context, DetailSlot slot) =>
    switch (slot.name) {
      DetailSlotName.downloadProgress => DownloadProgressSlot(
        key: ValueKey(slot.item),
        item: slot.item,
      ),
      // Nothing offers subtitles yet.
      DetailSlotName.subtitles => const SizedBox.shrink(),
    };
