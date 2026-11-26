import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

Command _command(CommandStatus status, [CommandResult? result]) =>
    Command(id: 1, name: 'RefreshMovie', status: status, result: result);

const _results = [null, ...CommandResult.values];

void main() {
  test('a queued or started command is pending, whatever its result', () {
    for (final status in [CommandStatus.queued, CommandStatus.started]) {
      for (final result in _results) {
        final command = _command(status, result);
        expect(command.outcome, CommandOutcome.pending);
        expect(command.isFinished, isFalse);
      }
    }
  });

  test('a completed command is judged by its result', () {
    const expected = {
      null: CommandOutcome.succeeded,
      CommandResult.successful: CommandOutcome.succeeded,
      CommandResult.unsuccessful: CommandOutcome.failed,
      CommandResult.indeterminate: CommandOutcome.unknown,
      CommandResult.unknown: CommandOutcome.unknown,
    };
    expect(expected.keys, unorderedEquals(_results));

    for (final MapEntry(key: result, value: outcome) in expected.entries) {
      final command = _command(CommandStatus.completed, result);
      expect(command.outcome, outcome, reason: '$result');
      expect(command.isFinished, isTrue);
    }
  });

  test('a terminal failure stays a failure, whatever its result', () {
    for (final status in [
      CommandStatus.failed,
      CommandStatus.aborted,
      CommandStatus.cancelled,
      CommandStatus.orphaned,
    ]) {
      for (final result in _results) {
        final command = _command(status, result);
        expect(command.outcome, CommandOutcome.failed, reason: '$status');
        expect(command.isFinished, isTrue);
      }
    }
  });

  test('an unknown status ends polling with an unknown outcome', () {
    for (final result in _results) {
      final command = _command(CommandStatus.unknown, result);
      expect(command.outcome, CommandOutcome.unknown);
      expect(command.isFinished, isTrue);
    }
  });
}
