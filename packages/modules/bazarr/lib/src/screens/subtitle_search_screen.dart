import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import 'labels.dart';
import 'read_controllers.dart';
import 'request_note.dart';
import 'requests.dart';
import 'title_actions.dart';

/// A manual search: what the providers offer, to download from.
class SubtitleSearchScreen extends ConsumerStatefulWidget {
  /// Creates the search for [target], on the instance called [name].
  const SubtitleSearchScreen({
    required this.target,
    required this.name,
    super.key,
  });

  /// The movie or episode.
  final MediaKey target;

  /// The instance's name.
  final String name;

  @override
  ConsumerState<SubtitleSearchScreen> createState() =>
      _SubtitleSearchScreenState();
}

class _SubtitleSearchScreenState extends ConsumerState<SubtitleSearchScreen> {
  /// Those whose download was asked for, which is not asked again from these
  /// results.
  final _asked = <SubtitleCandidate>{};

  Future<void> _download(SubtitleCandidate candidate) async {
    setState(() => _asked.add(candidate));
    final taken = await downloadSubtitle(
      context,
      ref,
      widget.target,
      widget.name,
      candidate,
    );
    // One that was refused may be tried again.
    if (!taken && mounted) setState(() => _asked.remove(candidate));
  }

  void _searchAgain() {
    setState(_asked.clear);
    unawaited(
      ref.read(candidatesProvider(widget.target).notifier).searchAgain(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = BazarrLocalizations.of(context);
    final target = widget.target;
    final state = ref.watch(candidatesProvider(target));
    final request = ref.watch(
      requestsProvider,
    )[(instanceId: target.source.instanceId, media: target.media)];
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.manualSearch),
        actions: [
          IconButton(
            tooltip: strings.searchAgain,
            icon: const Icon(Icons.refresh),
            onPressed: state is ViewLoading ? null : _searchAgain,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state is ViewLoading<List<SubtitleCandidate>>
            ? ProgressMessage(message: strings.searching)
            : StateScaffold<List<SubtitleCandidate>>(
                state: state,
                onRetry: _searchAgain,
                itemId: target.media,
                isEmpty: (candidates) => candidates.isEmpty,
                emptyMessage: strings.searchNone,
                builder: (_, candidates, {required isStale}) => _results(
                  candidates,
                  request,
                  enabled: !isStale && request != RequestState.sending,
                ),
              ),
      ),
    );
  }

  Widget _results(
    List<SubtitleCandidate> candidates,
    RequestState? request, {
    required bool enabled,
  }) {
    final strings = BazarrLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView.separated(
        padding: EdgeInsets.symmetric(
          horizontal: screenMargin(constraints.maxWidth),
          vertical: 8,
        ),
        // How a request stands comes first.
        itemCount: candidates.length + 1,
        separatorBuilder: (context, index) =>
            index == 0 ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return request == null
                ? const SizedBox.shrink()
                : RequestNote(
                    state: request,
                    name: widget.name,
                    // A download changes the title, not these results.
                    actionLabel: strings.backToSubtitles,
                    actionIcon: Icons.arrow_back,
                    onAction: () => Navigator.of(context).pop(),
                  );
          }
          final candidate = candidates[index - 1];
          return _Candidate(
            candidate: candidate,
            asked: _asked.contains(candidate),
            onDownload: enabled ? () => unawaited(_download(candidate)) : null,
          );
        },
      ),
    );
  }
}

class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.candidate,
    required this.asked,
    required this.onDownload,
  });

  final SubtitleCandidate candidate;
  final bool asked;
  final VoidCallback? onDownload;

  // The server names properties such as `release_group`.
  static String? _properties(List<String> properties) =>
      serverText(properties.join(', ').replaceAll('_', ' '));

  @override
  Widget build(BuildContext context) {
    final strings = BazarrLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = serverText(candidate.provider) ?? strings.untitled;
    final language = languageLabel(strings, candidate.language);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(provider, style: theme.textTheme.titleSmall),
          Text(strings.historyLanguage(language)),
          Text(strings.candidateScore(candidate.score)),
          if (_properties(candidate.matches) case final matches?)
            Text(strings.matches(matches)),
          if (_properties(candidate.dontMatches) case final others?)
            Text(strings.doesNotMatch(others)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: asked
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(strings.downloadAsked),
                  )
                : TextButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: Text(
                      strings.download,
                      semanticsLabel: strings.downloadFrom(language, provider),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
