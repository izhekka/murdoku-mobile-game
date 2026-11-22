import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/clock.dart';
import '../../state/game_controller.dart';
import '../../state/providers.dart';
import '../widgets/skin_card.dart';
import '../widgets/tutorial_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _tutorialQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
  }

  void _maybeShowTutorial() {
    if (_tutorialQueued || !mounted) return;
    if (ref.read(prefsRepositoryProvider).loadTutorialSeen()) return;
    _tutorialQueued = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TutorialOverlay(
        onDismiss: () {
          Navigator.of(dialogContext).pop();
          ref.read(prefsRepositoryProvider).saveTutorialSeen(true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.watch(prefsRepositoryProvider);
    // Watch the controller so returning from a won/quit game rebuilds home
    // with fresh repository state.
    final controllerState = ref.watch(gameControllerProvider);
    final savedGame = controllerState != null
        ? ref.read(gameControllerProvider.notifier).currentSave() ??
            repo.loadActiveGame()
        : repo.loadActiveGame();
    final daily = repo.loadDailyState();
    final today = utcToday(ref.read(clockProvider));
    final dailyDone = daily.lastCompletedDate == today;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (savedGame != null)
            SkinCard(
              child: ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(l10n.continueCase),
                subtitle: Text(
                    '${_difficultyLabel(l10n, savedGame.caseData.difficulty)} · '
                    '${formatDuration(savedGame.board.elapsed)}'),
                onTap: () {
                  ref.read(gameControllerProvider.notifier).resume(savedGame);
                  context.go('/game');
                },
              ),
            ),
          SkinCard(
            child: ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.newCase),
              onTap: () => _showNewCaseSheet(context, ref, l10n),
            ),
          ),
          SkinCard(
            child: ListTile(
              leading: Icon(dailyDone ? Icons.check_circle : Icons.event),
              iconColor:
                  dailyDone ? Theme.of(context).colorScheme.primary : null,
              title: Text(l10n.dailyCase),
              subtitle: dailyDone ? Text(l10n.dailyCompleted) : null,
              onTap: () {
                ref.read(gameControllerProvider.notifier).startDaily(today);
                context.go('/game');
              },
            ),
          ),
          const SizedBox(height: 8),
          SkinCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text(l10n.howToPlayTitle),
                  onTap: () => context.go('/how-to-play'),
                ),
                ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: Text(l10n.statsTitle),
                  onTap: () => context.go('/stats'),
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(l10n.settingsTitle),
                  onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _difficultyLabel(AppLocalizations l10n, Difficulty difficulty) =>
      switch (difficulty) {
        Difficulty.easy => l10n.difficultyEasy,
        Difficulty.standard => l10n.difficultyStandard,
        Difficulty.hard => l10n.difficultyHard,
      };

  void _showNewCaseSheet(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final repo = ref.read(prefsRepositoryProvider);
    final hasActiveSave = repo.loadActiveGame() != null;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.chooseDifficulty,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              for (final difficulty in Difficulty.values)
                ListTile(
                  title: Text(_difficultyLabel(l10n, difficulty)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startNewCase(context, ref, l10n, difficulty, hasActiveSave);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startNewCase(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, Difficulty difficulty, bool hasActiveSave) async {
    if (hasActiveSave) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.discardTitle),
          content: Text(l10n.discardBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.discard),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    ref.read(gameControllerProvider.notifier).startNewCase(difficulty);
    if (context.mounted) context.go('/game');
  }
}
