import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _series = ItemRef(instanceId: 'i1', kind: MediaKind.series, remoteId: 1);
const _episode = ItemRef(
  instanceId: 'i1',
  kind: MediaKind.episode,
  remoteId: 2,
);

void main() {
  const slot = DetailSlot(
    DetailSlotName.subtitles,
    item: _episode,
    parent: _series,
  );

  testWidgets('shows nothing without a scope', (tester) async {
    await tester.pumpWidget(const Center(child: slot));

    expect(tester.getSize(find.byType(DetailSlot)), Size.zero);
  });

  testWidgets('shows what the scope builds for its name and item', (
    tester,
  ) async {
    DetailSlot? asked;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DetailSlotScope(
          builder: (context, slot) {
            asked = slot;
            return const Text('filled');
          },
          child: slot,
        ),
      ),
    );

    expect(find.text('filled'), findsOneWidget);
    expect(asked?.name, DetailSlotName.subtitles);
    expect(asked?.item, _episode);
    expect(asked?.parent, _series);
  });
}
