import 'package:flutter/widgets.dart';

import '../models/media_image.dart';

/// Loads one instance's artwork. Implemented by the core: instance paths go
/// through the instance's client, remote addresses carry no credentials.
abstract interface class ArtworkLoader {
  /// Null when nothing may be loaded, so a placeholder is shown.
  ImageProvider<Object>? image(MediaImage image);
}
