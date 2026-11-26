import 'package:core/core.dart';

/// What a queue or history record is about, as the module reads its ids.
///
/// `item` is null where the server cannot match the record. `parent` is the
/// series, artist or author `item` belongs to.
typedef ServarrRefs = ({ItemRef? item, ItemRef? parent});
