/// The permission bits of the servers' `server/lib/permissions.ts`, the same in
/// all three (research R16).
library;

import 'package:core/core.dart';

const _admin = 2;
const _manageRequests = 16;
const _request = 32;
const _request4k = 1024;
const _request4kMovie = 2048;
const _request4kTv = 4096;
const _requestMovie = 262144;
const _requestTv = 524288;
const _manageIssues = 1048576;
const _viewIssues = 2097152;
const _createIssues = 4194304;

/// What a user with [bits] may do. 4K is offered only where the server has a
/// 4K server set up, as its `settings/public` says with [movie4k] and
/// [series4k].
Set<ServicePermission> permissionsOf(
  int bits, {
  required bool movie4k,
  required bool series4k,
}) {
  // An administrator may do everything.
  bool has(int any) => bits & (any | _admin) != 0;
  return {
    if (has(_request | _requestMovie)) ServicePermission.requestMovies,
    if (has(_request | _requestTv)) ServicePermission.requestSeries,
    if (movie4k && has(_request4k | _request4kMovie))
      ServicePermission.request4kMovies,
    if (series4k && has(_request4k | _request4kTv))
      ServicePermission.request4kSeries,
    if (has(_manageRequests)) ServicePermission.manageRequests,
    if (has(_createIssues | _manageIssues)) ServicePermission.reportIssues,
    if (has(_createIssues | _viewIssues | _manageIssues))
      ServicePermission.viewIssues,
    if (has(_manageIssues)) ServicePermission.manageIssues,
  };
}
