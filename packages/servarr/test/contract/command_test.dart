// The command status read. A result left out is null; the outcome rules are
// `Command.outcome` of the core (data-model.md Command).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Reads the fixture's command, with [changes].
Future<Command> _read(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) {
  final body = service.object('command')
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  final id = body['id']! as int;
  final server = FakeServer.paths({'command/$id': body});
  return value(service.client(server).commandStatus(id));
}

void main() {
  for (final service in services) {
    final id = service == radarr ? 8 : 4;

    group('${service.name} command', () {
      test('asks for the one command', () async {
        final server = FakeServer.paths({
          'command/$id': service.fixture('command'),
        });

        await value(service.client(server).commandStatus(id));

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/command/$id');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('maps a command that succeeded', () async {
        final command = await _read(service);

        expect(command.id, id);
        expect(
          command.name,
          service == radarr ? 'MoviesSearch' : 'SeriesSearch',
        );
        expect(command.status, CommandStatus.completed);
        expect(command.result, CommandResult.successful);
        expect(command.message, service.object('command')['message']);
        expect(command.message, isNotEmpty);
        expect(command.outcome, CommandOutcome.succeeded);
        expect(command.isFinished, isTrue);
      });

      // The server sends `unknown` as the result until a command completes.
      for (final (word, status, outcome) in [
        ('queued', CommandStatus.queued, CommandOutcome.pending),
        ('started', CommandStatus.started, CommandOutcome.pending),
        ('failed', CommandStatus.failed, CommandOutcome.failed),
        ('aborted', CommandStatus.aborted, CommandOutcome.failed),
        ('cancelled', CommandStatus.cancelled, CommandOutcome.failed),
        // Was running when the server restarted.
        ('orphaned', CommandStatus.orphaned, CommandOutcome.failed),
        ('someFutureStatus', CommandStatus.unknown, CommandOutcome.unknown),
      ]) {
        test('reads status $word as ${outcome.name}', () async {
          final command = await _read(
            service,
            {'status': word, 'result': 'unknown'},
            ['message'],
          );

          expect(command.status, status);
          expect(command.result, CommandResult.unknown);
          expect(command.message, isNull);
          expect(command.outcome, outcome);
          expect(command.isFinished, outcome != CommandOutcome.pending);
        });
      }

      for (final (word, result, outcome) in [
        ('successful', CommandResult.successful, CommandOutcome.succeeded),
        ('unsuccessful', CommandResult.unsuccessful, CommandOutcome.failed),
        ('indeterminate', CommandResult.indeterminate, CommandOutcome.unknown),
        ('unknown', CommandResult.unknown, CommandOutcome.unknown),
        ('someFutureResult', CommandResult.unknown, CommandOutcome.unknown),
      ]) {
        test('reads completed with $word as ${outcome.name}', () async {
          final command = await _read(service, {'result': word});

          expect(command.status, CommandStatus.completed);
          expect(command.result, result);
          expect(command.outcome, outcome);
          expect(command.isFinished, isTrue);
        });
      }

      test('takes completed without a result as success', () async {
        final command = await _read(service, const {}, ['result']);

        expect(command.result, isNull);
        expect(command.outcome, CommandOutcome.succeeded);
      });

      test('reports a command the server no longer has', () async {
        final server = FakeServer.paths(const {});

        expect(
          await failure(service.client(server).commandStatus(id)),
          isA<NotFound>(),
        );
        expect(server.requests, hasLength(1));
      });

      for (final field in ['id', 'name', 'status']) {
        test('cannot understand a command without $field', () async {
          final body = service.object('command')..remove(field);
          final server = FakeServer.paths({'command/$id': body});

          expect(
            await failure(service.client(server).commandStatus(id)),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }
}
