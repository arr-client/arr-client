// The values data-model.md lists. A change here is a change to the data model.
// `unknown` also appears where an enum takes wire values the app does not know.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _names(List<Enum> values) => [for (final v in values) v.name];

void main() {
  test('Release.protocol', () {
    expect(_names(DownloadProtocol.values), ['torrent', 'usenet', 'unknown']);
  });

  test('HistoryEvent.eventType', () {
    expect(_names(HistoryEventType.values), [
      'grabbed',
      'imported',
      'failed',
      'renamed',
      'deleted',
      'other',
    ]);
  });

  test('Command.status and Command.result', () {
    expect(_names(CommandStatus.values), [
      'queued',
      'started',
      'completed',
      'failed',
      'aborted',
      'cancelled',
      'orphaned',
      'unknown',
    ]);
    expect(_names(CommandResult.values), [
      'successful',
      'unsuccessful',
      'indeterminate',
      'unknown',
    ]);
  });

  test('DownloadProgress.state', () {
    expect(_names(DownloadState.values), [
      'queued',
      'downloading',
      'paused',
      'stalled',
      'checking',
      'processing',
      'seeding',
      'completed',
      'error',
      'unknown',
    ]);
  });

  test('ServerOption.kind', () {
    expect(_names(ServerOptionKind.values), [
      'qualityProfile',
      'metadataProfile',
      'rootFolder',
      'tag',
    ]);
  });

  test('DiscoveryTitle.availability and availability4k', () {
    expect(_names(Availability.values), [
      'unknown',
      'pending',
      'processing',
      'partial',
      'available',
      'blocklisted',
      'deleted',
    ]);
  });

  test('only a blocklisted variant rules out a request', () {
    expect(Availability.values.where((a) => a.blocksRequest), [
      Availability.blocklisted,
    ]);
  });

  test('Request.status', () {
    expect(_names(RequestStatus.values), [
      'pending',
      'approved',
      'declined',
      'failed',
      'completed',
      'unknown',
    ]);
  });

  test('SubtitleFile.mediaType', () {
    expect(_names(SubtitleMediaType.values), ['episode', 'movie']);
  });
}
