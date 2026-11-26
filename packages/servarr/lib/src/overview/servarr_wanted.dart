import 'package:core/core.dart';

import '../json_reading.dart';
import '../servarr_client.dart';

/// The wanted lists of a service of the Servarr family: monitored items only,
/// a server page at a time and in the server's order.
final class ServarrWanted implements WantedProvider {
  /// The wanted lists of one service.
  ///
  /// [item] reads one record and throws [FormatException] for one it cannot
  /// understand. [query] holds the service's own parameters.
  ServarrWanted(this._client, {required this._item, required this._query});

  static const _pageSize = 50;

  final ServarrClient _client;
  final LibraryItem Function(JsonObject record) _item;
  final Map<String, List<String>> _query;

  @override
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1}) =>
      _list('wanted/missing', page);

  @override
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1}) =>
      _list('wanted/cutoff', page);

  ServiceResult<ResultPage<LibraryItem>> _list(String path, int page) =>
      _client.read(
        path,
        (json) {
          final answer = readPage(json, _item);
          return ResultPage(
            items: answer.records,
            page: page,
            hasMore: page * answer.pageSize < answer.totalRecords,
          );
        },
        query: {
          ..._query,
          'page': ['$page'],
          'pageSize': ['$_pageSize'],
          'monitored': ['true'],
        },
      );
}
