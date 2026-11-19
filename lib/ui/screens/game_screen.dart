import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../domain/game_logic.dart' show Tool, boardSolved;
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/game_controller.dart';
import '../../state/stats_controller.dart';
import '../widgets/accuse_sheet.dart';
import '../widgets/board_view.dart';
import '../widgets/dialogs.dart';
import '../widgets/suspect_panel.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _accuseOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lifecycle == AppLifecycleState.resumed) {
        ref.read(gameControllerProvider.notifier).tick();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(gameControllerProvider);

    // Auto-open the accuse sheet exactly once per solved transition.
    ref.listen<GameState?>(gameControllerProvider, (prev, next) {
      if (next == null || next.phase != GamePhase.playing) return;
      final wasSolved =
          prev != null && boardSolved(prev.caseData, prev.placed);
      final solved = boardSolved(next.caseData, next.placed);
      if (solved && !wasSolved && !_accuseOpen) {
        _accuseOpen = true;
        showAccuseSheet().whenComplete(() => _accuseOpen = false);
      }
    });

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.gameTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.noActiveCase),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/'),
                child: Text(l10n.backToHome),
              ),
            ],
          ),
        ),
      );
    }

    final difficultyLabel = switch (state.caseData.difficulty) {
      Difficulty.easy => l10n.difficultyEasy,
      Difficulty.standard => l10n.difficultyStandard,
      Difficulty.hard => l10n.difficultyHard,
    };

    final board = Padding(
      padding: const EdgeInsets.all(8),
      child: BoardView(
        caseData: state.caseData,
        placed: state.placed,
        xMarks: state.xMarks,
        selectedSuspectId: state.selectedSuspectId,
        onCellTap: (p) =>
            ref.read(gameControllerProvider.notifier).tapCell(p),
        onCellDrag: (p) {
          final notifier = ref.read(gameControllerProvider.notifier);
          if (state.tool != Tool.place) notifier.tapCell(p);
        },
      ),
    );

    final panel = SuspectPanel(
      caseData: state.caseData,
      placed: state.placed,
      selectedSuspectId: state.selectedSuspectId,
      onSuspectTap: (id) {
        final notifier = ref.read(gameControllerProvider.notifier);
        notifier.selectSuspect(
            state.selectedSuspectId == id ? null : id);
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _confirmQuit(l10n),
          tooltip: l10n.quitCase,
        ),
        title: Text('$difficultyLabel · ${formatDuration(state.elapsed)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: l10n.revealSolution,
            onPressed: () => _confirmReveal(l10n),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (wide) {
            return Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: board),
                      SizedBox(width: 300, child: panel),
                    ],
                  ),
                ),
                _toolbar(l10n, state),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 3, child: Center(child: board)),
              SizedBox(
                height: 160,
                child: panel,
              ),
              _toolbar(l10n, state),
            ],
          );
        }),
      ),
    );
  }

  Widget _toolbar(AppLocalizations l10n, GameState state) {
    final notifier = ref.read(gameControllerProvider.notifier);
    final hintsLeft = 2 - state.hintsUsed;

    Widget toolButton(Tool tool, IconData icon, String tooltip) => IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: () => notifier.setTool(tool),
          style: IconButton.styleFrom(
            backgroundColor:
                state.tool == tool ? Theme.of(context).colorScheme.primaryContainer : null,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          toolButton(Tool.place, Icons.person, l10n.newCase),
          toolButton(Tool.markX, Icons.close, l10n.stateExcluded),
          toolButton(Tool.erase, Icons.auto_fix_normal, l10n.cancel),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.cancel,
            onPressed: () => notifier.undo(),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check),
            tooltip: l10n.checkResult(0, 0),
            onPressed: () => _runCheck(l10n),
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb),
            tooltip: l10n.hintsLeft(hintsLeft),
            onPressed: () => _showHintSheet(l10n, hintsLeft),
          ),
          IconButton(
            icon: const Icon(Icons.gavel),
            tooltip: l10n.accuse,
            onPressed: () => showAccuseSheet(),
          ),
        ],
      ),
    );
  }

  Future<void> showAccuseSheet() async {
    final state = ref.read(gameControllerProvider);
    if (state == null || state.phase != GamePhase.playing) return;
    final accused = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => AccuseSheet(
        caseData: state.caseData,
        eliminatedSuspects: state.eliminatedSuspects,
      ),
    );
    if (accused == null) return;
    if (!mounted) return;
    final notifier = ref.read(gameControllerProvider.notifier);
    final correct = notifier.accuse(accused);
    if (correct) {
      final won = ref.read(gameControllerProvider)!;
      unawaited(ref.read(statsControllerProvider.notifier).recordWin(
        difficulty: won.caseData.difficulty,
        time: won.elapsed,
        mistakes: won.wrongAccusations,
        isDaily: won.isDaily,
        dailyDate: won.dailyDate ?? '',
      ));
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => VictoryDialog(
          elapsed: won.elapsed,
          difficulty: won.caseData.difficulty,
          wrongAccusations: won.wrongAccusations,
        ),
      );
      if (mounted) context.go('/');
    } else {
      final name = state.caseData.suspects
          .firstWhere((s) => s.id == accused)
          .name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.alibi(name))),
      );
    }
  }

  void _runCheck(AppLocalizations l10n) {
    final result = ref.read(gameControllerProvider.notifier).runCheck();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.checkResult(result.correct, result.total)),
      ),
    );
  }

  void _showHintSheet(AppLocalizations l10n, int hintsLeft) {
    final notifier = ref.read(gameControllerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.hintsLeft(hintsLeft)),
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(l10n.hintPlace),
              onTap: () {
                Navigator.of(sheetContext).pop();
                notifier.hintPlacement();
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.hintEliminate),
              onTap: () {
                Navigator.of(sheetContext).pop();
                notifier.hintEliminate();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmQuit(AppLocalizations l10n) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.quitConfirmTitle,
      body: l10n.quitConfirmBody,
      confirmLabel: l10n.quitCase,
    );
    if (!confirmed || !mounted) return;
    ref.read(gameControllerProvider.notifier).quit();
    context.go('/');
  }

  Future<void> _confirmReveal(AppLocalizations l10n) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.revealConfirmTitle,
      body: l10n.revealConfirmBody,
      confirmLabel: l10n.revealSolution,
    );
    if (!confirmed || !mounted) return;
    ref.read(gameControllerProvider.notifier).revealSolution();
  }
}
