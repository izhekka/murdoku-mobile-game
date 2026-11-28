import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/format.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/case_pool.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart' show SavedGame;
import 'package:murdoku/ui/widgets/skin_card.dart';
import 'package:murdoku/ui/widgets/tutorial_overlay.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTutorial();
      _kickPoolRefill();
    });
  }

  /// Issue 108: home init runs the pool refill check so deficient pools
  /// top up in the background while the app is open — never blocking the
  /// UI. With the forced-seed pin (integration tests) the pool is
  /// bypassed entirely (the controller no-ops the check).
  void _kickPoolRefill() {
    if (!mounted) return;
    unawaited(ref.read(casePoolControllerProvider.notifier).maybeRefill());
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
          if (savedGame != null) ...[
            _continueCard(l10n, savedGame),
            // Issue 96: the explicit spacer joins every block pair, so the
            // drawn gap = the skin's card margins + 8 uniformly (16 on the
            // cartoon skins, 24 on classic) instead of spacing the menu card
            // off from a margins-only rhythm.
            const SizedBox(height: 8),
          ],
          _newCaseCard(l10n),
          const SizedBox(height: 8),
          _dailyCard(l10n, dailyDone, today),
          const SizedBox(height: 8),
          _menuCard(l10n),
        ],
      ),
    );
  }

  /// Resume the interrupted case: difficulty and elapsed time in the
  /// subtitle.
  Widget _continueCard(AppLocalizations l10n, SavedGame savedGame) {
    return SkinCard(
      child: ListTile(
        leading: const Icon(Icons.play_arrow),
        title: Text(l10n.continueCase),
        subtitle: Text(
          '${_difficultyLabel(l10n, savedGame.caseData.difficulty)} · '
          '${formatDuration(savedGame.board.elapsed)}',
        ),
        onTap: () {
          ref.read(gameControllerProvider.notifier).resume(savedGame);
          context.go('/game');
        },
      ),
    );
  }

  /// Start a fresh case (difficulty chooser).
  Widget _newCaseCard(AppLocalizations l10n) {
    return SkinCard(
      child: ListTile(
        leading: const Icon(Icons.add),
        title: Text(l10n.newCase),
        onTap: () => _showNewCaseSheet(context, ref, l10n),
      ),
    );
  }

  /// The UTC-date daily; a check icon marks an already-completed day.
  Widget _dailyCard(AppLocalizations l10n, bool dailyDone, String today) {
    return SkinCard(
      child: ListTile(
        leading: Icon(dailyDone ? Icons.check_circle : Icons.event),
        iconColor: dailyDone ? Theme.of(context).colorScheme.primary : null,
        title: Text(l10n.dailyCase),
        subtitle: dailyDone ? Text(l10n.dailyCompleted) : null,
        onTap: () {
          ref.read(gameControllerProvider.notifier).startDaily(today);
          context.go('/game');
        },
      ),
    );
  }

  /// How-to-play, stats and settings menu rows.
  Widget _menuCard(AppLocalizations l10n) {
    return SkinCard(
      child: Column(
        // Issue 75: push, not go — a fresh single-page stack via go
        // strands the plain-AppBar screens with no back affordance. This
        // applies to all rows below; the home→game entries keep `go` so the
        // game's confirm-quit stays the only in-UI exit.
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: Text(l10n.howToPlayTitle),
            onTap: () => context.push('/how-to-play'),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: Text(l10n.statsTitle),
            onTap: () => context.push('/stats'),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(l10n.settingsTitle),
            onTap: () => context.push('/settings'),
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
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
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
                child: Text(
                  l10n.chooseDifficulty,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final difficulty in Difficulty.values)
                ListTile(
                  title: Text(_difficultyLabel(l10n, difficulty)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startNewCase(
                      context,
                      ref,
                      l10n,
                      difficulty,
                      hasActiveSave,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startNewCase(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Difficulty difficulty,
    bool hasActiveSave,
  ) async {
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
