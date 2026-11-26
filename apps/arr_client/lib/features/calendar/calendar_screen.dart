import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/l10n/generated/app_localizations.dart';
import 'agenda_view.dart';
import 'calendar_data.dart';
import 'downloaded_view.dart';
import 'month_view.dart';
import 'today.dart';

/// The views of the calendar, in their order.
enum CalendarTab { agenda, month, downloaded }

/// The combined calendar of the active profile's services: what is coming up,
/// by agenda and by month, and what was downloaded.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({this.initialTab = CalendarTab.agenda, super.key});

  final CalendarTab initialTab;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// The day selected in the month, and the day of downloads. Null follows
  /// today, also when the day changes.
  DateTime? _monthDay;
  DateTime? _importDay;

  /// The instances filtered out of every view.
  var _hidden = <String>{};

  void _hide(Set<String> hidden) => setState(() => _hidden = hidden);

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);
    // Watched here, so that it lasts while another view is shown.
    final agendaDays = ref.watch(agendaDaysProvider);
    final importDay = _importDay;
    return DefaultTabController(
      length: CalendarTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.moreCalendar),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.calendarRefresh,
              onPressed: () =>
                  ref.read(calendarRefreshProvider.notifier).request(),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: strings.calendarTabAgenda),
              Tab(text: strings.calendarTabMonth),
              Tab(text: strings.calendarTabDownloaded),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AgendaView(
              today: today,
              days: agendaDays,
              onMore: () => ref.read(agendaDaysProvider.notifier).extend(),
              hidden: _hidden,
              onHiddenChanged: _hide,
            ),
            MonthView(
              today: today,
              selected: _monthDay ?? today,
              onSelected: (day) =>
                  setState(() => _monthDay = day == today ? null : day),
              hidden: _hidden,
              onHiddenChanged: _hide,
            ),
            DownloadedView(
              today: today,
              // A clock set back must not leave a day after today.
              day: importDay == null || !importDay.isBefore(today)
                  ? today
                  : importDay,
              onDay: (day) =>
                  setState(() => _importDay = day.isBefore(today) ? day : null),
              hidden: _hidden,
              onHiddenChanged: _hide,
            ),
          ],
        ),
      ),
    );
  }
}
