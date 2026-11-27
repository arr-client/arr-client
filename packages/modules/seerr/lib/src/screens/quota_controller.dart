/// What the user may still request.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seerr_source.dart';

/// The quota of one instance's user, while a screen shows it.
final quotaProvider = FutureProvider.autoDispose
    .family<Result<Quota, ServiceFailure>, SeerrSource>(
      (ref, source) => source.guard(source.requests.quota),
    );
