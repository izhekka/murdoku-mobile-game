import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/format.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/game_logic.dart' show Tool, boardSolved;
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/board_view.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:murdoku/ui/widgets/legend_sheet.dart';
import 'package:murdoku/ui/widgets/pause_menu_sheet.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

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
    ref.listen<GameState?>(gameControllerProvider, _autoOpenAccuse);

    if (state == null) return _noActiveCaseScaffold(l10n);

    final difficultyLabel = _difficultyLabel(l10n, state.caseData.difficulty);
    final board = _board(state);
    final panel = _panel(state);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _confirmQuit(l10n),
          tooltip: l10n.quitCase,
        ),
        title: Semantics(
          label: l10n.timerSemantics(
            difficultyLabel,
            formatDuration(state.elapsed),
          ),
          excludeSemantics: true,
          child: Text('$difficultyLabel · ${formatDuration(state.elapsed)}'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: l10n.legendTitle,
            onPressed: () => showLegendSheet(context, state.caseData),
          ),
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: l10n.revealSolution,
            onPressed: () => _confirmReveal(l10n),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            if (wide) {
              return Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // Bottom-center the square board in its (wider than
                        // tall) slot so it hugs the toolbar, matching the
                        // narrow branch's flush seam.
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: board,
                          ),
                        ),
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
                // The square board hugs the suspect grid; whatever vertical
                // space is left above it (under the app bar) is a few px at
                // phone sizes — never a dead band, and never a gap between
                // the board and the panel (UX-6).
                Expanded(
                  child: Align(alignment: Alignment.bottomCenter, child: board),
                ),
                // The panel fills all space under the board (UX-9) instead of
                // a fixed 205px slot, so its cards stretch taller and the
                // full clue text stays readable.
                Expanded(child: panel),
                _toolbar(l10n, state),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Auto-open the accuse sheet exactly once per solved transition.
  void _autoOpenAccuse(GameState? prev, GameState? next) {
    if (_accuseOpen) return;
    if (next == null || next.phase != GamePhase.playing) return;
    if (_transitionedToSolved(prev, next)) {
      _accuseOpen = true;
      showAccuseSheet().whenComplete(() => _accuseOpen = false);
    }
  }

  /// True when [prev] was unsolved and [next] just became fully placed.
  bool _transitionedToSolved(GameState? prev, GameState next) {
    final wasSolved = prev != null && boardSolved(prev.caseData, prev.placed);
    return boardSolved(next.caseData, next.placed) && !wasSolved;
  }

  /// The placeholder shown with no case in play.
  Widget _noActiveCaseScaffold(AppLocalizations l10n) {
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

  /// The localized difficulty label for the timer title.
  String _difficultyLabel(AppLocalizations l10n, Difficulty difficulty) =>
      switch (difficulty) {
        Difficulty.easy => l10n.difficultyEasy,
        Difficulty.standard => l10n.difficultyStandard,
        Difficulty.hard => l10n.difficultyHard,
      };

  /// The mansion map, wired to the controller.
  Widget _board(GameState state) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BoardView(
        caseData: state.caseData,
        placed: state.placed,
        xMarks: state.xMarks,
        selectedSuspectId: state.selectedSuspectId,
        onCellTap: (p) => ref.read(gameControllerProvider.notifier).tapCell(p),
        onCellDrag: (p) {
          final notifier = ref.read(gameControllerProvider.notifier);
          if (state.tool != Tool.place) notifier.tapCell(p);
        },
      ),
    );
  }

  /// The suspects panel; tapping a card selects it, tapping the selected
  /// card asks the controller to deselect.
  Widget _panel(GameState state) {
    return SuspectPanel(
      caseData: state.caseData,
      placed: state.placed,
      selectedSuspectId: state.selectedSuspectId,
      onSuspectTap: (id) {
        final notifier = ref.read(gameControllerProvider.notifier);
        notifier.selectSuspect(state.selectedSuspectId == id ? null : id);
      },
    );
  }

  Widget _toolbar(AppLocalizations l10n, GameState state) {
    final notifier = ref.read(gameControllerProvider.notifier);
    final hintsLeft = 2 - state.hintsUsed;
    // Cartoon skins color every toolbar action (issue 23); classic keeps
    // its scheme-colored buttons (maybeOf null → classic rendering).
    final tokens = SkinScope.maybeOf(context);
    final actions = tokens != null && tokens.isCartoon ? tokens.actions : null;

    Widget toolButton(
      Tool tool,
      IconData icon,
      String label, {
      required String tooltip,
      required Color? pillColor,
    }) => _MiniButton(
      icon: icon,
      label: label,
      tooltip: tooltip,
      keyName: _toolKeyName(tool),
      active: state.tool == tool,
      pillColor: pillColor,
      tokens: tokens,
      onPressed: () => notifier.setTool(tool),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: toolButton(
              Tool.place,
              Icons.person,
              l10n.toolPlace,
              tooltip: l10n.toolPlace,
              pillColor: _actionColor(actions, (a) => a.place),
            ),
          ),
          Expanded(
            child: toolButton(
              Tool.markX,
              Icons.close,
              l10n.toolMark,
              tooltip: l10n.toolMarkTooltip,
              pillColor: _actionColor(actions, (a) => a.mark),
            ),
          ),
          Expanded(
            child: toolButton(
              Tool.erase,
              Icons.auto_fix_normal,
              l10n.toolErase,
              tooltip: l10n.toolErase,
              pillColor: _actionColor(actions, (a) => a.erase),
            ),
          ),
          Expanded(
            child: _MiniButton(
              icon: Icons.undo,
              label: l10n.toolUndo,
              tooltip: l10n.toolUndo,
              keyName: 'tool_undo',
              pillColor: _actionColor(actions, (a) => a.undo),
              tokens: tokens,
              onPressed: notifier.undo,
            ),
          ),
          Expanded(
            child: _MiniButton(
              icon: Icons.fact_check,
              label: l10n.toolCheck,
              tooltip: l10n.toolCheckTooltip,
              keyName: 'tool_check',
              pillColor: _actionColor(actions, (a) => a.check),
              tokens: tokens,
              onPressed: () => _runCheck(l10n),
            ),
          ),
          Expanded(
            child: _MiniButton(
              icon: Icons.lightbulb,
              label: l10n.toolHint,
              tooltip: l10n.toolHintTooltip,
              keyName: 'tool_hint',
              pillColor: _actionColor(actions, (a) => a.hint),
              tokens: tokens,
              onPressed: () => _showHintSheet(l10n, hintsLeft),
            ),
          ),
          Expanded(
            child: _MiniButton(
              icon: Icons.gavel,
              label: l10n.toolAccuse,
              tooltip: l10n.accuse,
              keyName: 'tool_accuse',
              pillColor: _actionColor(actions, (a) => a.accuse),
              tokens: tokens,
              onPressed: showAccuseSheet,
            ),
          ),
          Expanded(
            child: _MiniButton(
              icon: Icons.pause,
              label: l10n.pauseMenuTitle,
              tooltip: l10n.pauseMenuTitle,
              keyName: 'tool_menu',
              pillColor: _actionColor(actions, (a) => a.menu),
              tokens: tokens,
              onPressed: () => _showPauseMenu(l10n),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPauseMenu(AppLocalizations l10n) {
    return PauseMenuSheet.show(context, onAbandon: () => _confirmQuit(l10n));
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
    await _finishAccuse(state, accused);
  }

  /// Resolves the accusation: alibi snackbar on a miss, victory flow on a
  /// hit.
  Future<void> _finishAccuse(GameState state, String? accused) async {
    if (accused == null) return;
    if (!mounted) return;
    final notifier = ref.read(gameControllerProvider.notifier);
    if (!notifier.accuse(accused)) {
      _showAlibi(state, accused);
      return;
    }
    await _recordVictory(ref.read(gameControllerProvider)!);
  }

  /// The wrong-suspect snackbar with the accused's localized name.
  void _showAlibi(GameState state, String accused) {
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, state.caseData);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.alibi(names.nom(accused)))));
  }

  /// Records the win, shows the victory dialog, then returns home.
  Future<void> _recordVictory(GameState won) async {
    unawaited(
      ref
          .read(statsControllerProvider.notifier)
          .recordWin(
            difficulty: won.caseData.difficulty,
            time: won.elapsed,
            mistakes: won.wrongAccusations,
            isDaily: won.isDaily,
            dailyDate: won.dailyDate ?? '',
          ),
    );
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
  }

  void _runCheck(AppLocalizations l10n) {
    final result = ref.read(gameControllerProvider.notifier).runCheck();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.checkResult(result.correct, result.total))),
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

/// Two-line mini toolbar button (issue 35 extraction of the former local
/// `miniButton`): icon over a visible label (UX-5), minimum 48dp wide /
/// 52dp tall target, the label shrinks instead of overflowing. Cartoon
/// skins render it as a per-action colored pill with the skin's shadow; the
/// active tool gets an ink outline.
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.keyName,
    required this.pillColor,
    required this.onPressed,
    required this.tokens,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final String keyName;
  final bool active;
  final Color? pillColor;
  final VoidCallback onPressed;

  /// Null on classic: the button keeps its scheme-colored rendering.
  final SkinTokens? tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            key: Key(keyName),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: _decoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: _foreground()),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 10, color: _foreground()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Transparent active-highlight on classic; the skin pill on cartoon.
  BoxDecoration _decoration(BuildContext context) =>
      pillColor == null ? _classicDecoration(context) : _pillDecoration();

  /// The classic rendering: active tool highlighted with the scheme's
  /// primary container, inactive ones transparent.
  BoxDecoration _classicDecoration(BuildContext context) => BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    color: active
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.transparent,
  );

  /// The cartoon per-action colored pill with the skin's shadow; the active
  /// tool gets an ink outline.
  BoxDecoration _pillDecoration() => BoxDecoration(
    borderRadius: BorderRadius.circular(tokens!.buttonRadius),
    color: pillColor,
    boxShadow: [tokens!.buttonShadow],
    border: active ? Border.all(color: tokens!.ink, width: 2.5) : null,
  );

  /// White ink on the colored pill; theme ink on classic.
  Color? _foreground() => pillColor != null ? Colors.white : null;
}

/// The test key of a tool button, matching the tool's name.
String _toolKeyName(Tool tool) => switch (tool) {
  Tool.place => 'tool_place',
  Tool.markX => 'tool_mark',
  Tool.erase => 'tool_erase',
};

/// The skin's color for one toolbar action; null keeps the classic scheme.
Color? _actionColor(SkinActions? actions, Color Function(SkinActions) pick) =>
    actions == null ? null : pick(actions);
