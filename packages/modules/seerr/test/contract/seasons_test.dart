// The seasons a series can be requested with (spec story 9, scenario 3).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/src/adapters/seasons.dart';

import 'support.dart';

/// The recorded series: specials and two seasons, both asked for.
FakeSeerr _server({
  Map<String, Object?>? media,
  Map<String, Object?> settings = const {},
}) {
  final series = recorded('tv');
  return FakeSeerr()
    ..set('GET api/v1/tv/1100', json({...series, 'mediaInfo': ?media}))
    ..set(
      'GET api/v1/settings/public',
      json({...publicSettings(), ...settings}),
    );
}

Future<SeasonChoices> _seasons(FakeSeerr http, {bool is4k = false}) async =>
    valueOf(
      await SeerrSeasonAdapter(contextOf(http)).seasons(1100, is4k: is4k),
    );

Map<String, Object?> _media({
  List<(int, int, int)> seasons = const [],
  List<(int, bool, List<int>)> requests = const [],
}) => {
  'id': 10,
  'seasons': [
    for (final (number, status, status4k) in seasons)
      {'seasonNumber': number, 'status': status, 'status4k': status4k},
  ],
  'requests': [
    for (final (status, is4k, numbers) in requests)
      {
        'status': status,
        'is4k': is4k,
        'seasons': [
          for (final number in numbers) {'seasonNumber': number},
        ],
      },
  ],
};

Map<int, bool> _open(SeasonChoices choices) => {
  for (final season in choices.seasons) season.number: season.isOpen,
};

void main() {
  test('reads the recorded series and leaves out specials', () async {
    final http = _server();

    final choices = await _seasons(http);

    expect(_open(choices), {1: false, 2: false});
    expect(choices.seasons.every((season) => season.requested), isTrue);
    expect(choices.seasons.map((season) => season.episodeCount), [22, 22]);
    expect(choices.mayChoose, isTrue);
    expect(http.writes, isEmpty);
  });

  test('keeps the variants apart', () async {
    final choices = await _seasons(_server(), is4k: true);

    expect(_open(choices), {1: true, 2: true});
  });

  test('offers specials and single seasons as the server says', () async {
    final choices = await _seasons(
      _server(
        settings: {
          'enableSpecialEpisodes': true,
          'partialRequestsEnabled': false,
        },
      ),
    );

    expect(choices.seasons.map((season) => season.number), [0, 1, 2]);
    expect(choices.mayChoose, isFalse);
  });

  test('a season is open again after its request is over', () async {
    final choices = await _seasons(
      _server(
        media: _media(
          requests: [
            (3, false, [1]),
            (5, false, [2]),
          ],
        ),
      ),
    );

    expect(_open(choices), {1: true, 2: true});
  });

  test('a season on the server is not open, a removed one is', () async {
    final choices = await _seasons(
      _server(media: _media(seasons: [(1, 5, 1), (2, 7, 5)])),
    );

    expect(_open(choices), {1: false, 2: true});
    expect(choices.seasons.first.availability, Availability.available);
  });

  test('a series the server does not know has every season open', () async {
    final http = _server();
    http.set(
      'GET api/v1/tv/1100',
      json({...recorded('tv'), 'mediaInfo': null}),
    );

    expect(_open(await _seasons(http)), {1: true, 2: true});
  });

  test('says that an answer without seasons cannot be read', () async {
    final http = _server()..set('GET api/v1/tv/1100', json({'id': 1100}));

    final answer = await SeerrSeasonAdapter(contextOf(http))
        .seasons(1100, is4k: false);

    expect(failureOf(answer), isA<MalformedResponse>());
  });
}
