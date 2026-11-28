import 'dart:async';
import 'dart:math' as math;

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
            icon: const Icon(Icons.pause),
            tooltip: l10n.pauseMenuTitle,
            onPressed: () => _showPauseMenu(l10n),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            // Built per branch (review, issue 103): the wide branch hosts it
            // header-less — building the portrait variant up here would
            // construct a widget the landscape tree discards every build.
            final panel = _panel(state, showHeader: !wide);
            if (wide) {
              // Issue 107: the toolbar is a vertical strip on the right
              // edge, OUTSIDE the board slot's LayoutBuilder — the slot's
              // maxWidth/maxHeight already exclude the strip, so the board
              // square formula below needs no strip-width constant and the
              // map grows by the old bottom toolbar's height.
              return Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, slot) {
                        // Issue 103: the board's square footprint pins to
                        // the slot's TOP-LEFT edge (issue 109 switched the
                        // vertical pin from bottom to top: when the slot is
                        // taller than the square — SE landscape ≈319 vs 295
                        // — the bottom pin left a dead band ABOVE the map)
                        // and the suspects panel takes the remaining width
                        // up to its minimum, header-less. The 8px padding
                        // stays the seams — no dead band.
                        final boardSide = math.max(
                          0.0,
                          math.min(
                            slot.maxHeight,
                            slot.maxWidth - _panelMinWidth,
                          ),
                        );
                        return Row(
                          children: [
                            SizedBox(
                              width: boardSide,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: board,
                              ),
                            ),
                            Expanded(
                              // Tight height (like the narrow branch's
                              // Expanded panel): the landscape grid's
                              // pinned split measures the real slot.
                              child: SizedBox(
                                height: double.infinity,
                                child: panel,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _toolbarStrip(l10n, state),
                ],
              );
            }
            return Column(
              children: [
                // Issue 95: the board takes its maximum square first — the
                // leftover between the app bar and the toolbar minus the
                // panel's minimum, capped at the full-width square — and the
                // suspect panel takes what remains, filling all space under
                // the board (UX-9) with no dead band and no vertical gap to
                // the board (UX-6): the slot never exceeds the square it
                // holds, and the board's own 8px bottom padding rides the
                // seam. When the leftover is tighter than the panel's
                // minimum, the board shrinks to fit (overflow is never
                // allowed). The outer Column lays out the non-flex toolbar
                // before the flex children, so the inner LayoutBuilder
                // measures the exact leftover above the toolbar with no
                // height estimates — correct at any text scale.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, slot) {
                      final slotHeight = math.max(
                        0.0,
                        math.min(
                          slot.maxWidth,
                          slot.maxHeight - _panelMinHeight,
                        ),
                      );
                      return Column(
                        children: [
                          SizedBox(
                            height: slotHeight,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: board,
                            ),
                          ),
                          Expanded(child: panel),
                        ],
                      );
                    },
                  ),
                ),
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
  /// card asks the controller to deselect. The landscape wide branch hosts
  /// it header-less ([showHeader] false, issue 103); every other host keeps
  /// the default header.
  Widget _panel(GameState state, {bool showHeader = true}) {
    return SuspectPanel(
      caseData: state.caseData,
      placed: state.placed,
      selectedSuspectId: state.selectedSuspectId,
      showHeader: showHeader,
      onSuspectTap: (id) {
        final notifier = ref.read(gameControllerProvider.notifier);
        notifier.selectSuspect(state.selectedSuspectId == id ? null : id);
      },
    );
  }

  /// The four labeled toolbar buttons, un-wrapped: [Place, Mark X, Hint,
  /// Accuse] (issue 107 — Erase/Undo/Check are gone, Menu lives in the app
  /// bar). The portrait row wraps each in Expanded; the landscape strip
  /// stacks them vertically.
  List<Widget> _toolbarButtons(AppLocalizations l10n, GameState state) {
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

    return [
      toolButton(
        Tool.place,
        Icons.person,
        l10n.toolPlace,
        tooltip: l10n.toolPlace,
        pillColor: _actionColor(actions, (a) => a.place),
      ),
      toolButton(
        Tool.markX,
        Icons.close,
        l10n.toolMark,
        tooltip: l10n.toolMarkTooltip,
        pillColor: _actionColor(actions, (a) => a.mark),
      ),
      _MiniButton(
        icon: Icons.lightbulb,
        label: l10n.toolHint,
        tooltip: l10n.toolHintTooltip,
        keyName: 'tool_hint',
        pillColor: _actionColor(actions, (a) => a.hint),
        tokens: tokens,
        onPressed: () => _showHintSheet(l10n, hintsLeft),
      ),
      _MiniButton(
        icon: Icons.gavel,
        label: l10n.toolAccuse,
        tooltip: l10n.accuse,
        keyName: 'tool_accuse',
        pillColor: _actionColor(actions, (a) => a.accuse),
        tokens: tokens,
        onPressed: showAccuseSheet,
      ),
    ];
  }

  /// The portrait bottom toolbar: ONE row of the four buttons at every
  /// width (issue 107) — 4×48 + 3×4 + 16 = 212px fits the 320px minimum
  /// viewport, so the issue-88 two-row wrap is gone.
  Widget _toolbar(AppLocalizations l10n, GameState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: _toolbarRow([
        for (final button in _toolbarButtons(l10n, state))
          Expanded(child: button),
      ]),
    );
  }

  /// The landscape toolbar strip (issue 107): the same four labeled pills
  /// stacked top-to-bottom on the right edge, with the row's ≥4px seam
  /// pattern turned vertical, a fixed width, and every pill stretched to
  /// fill it. The stack's natural height (4×52 pills + 3×4 seams = 220)
  /// exceeds a legally short desktop body, so the Column scrolls instead of
  /// clipping Accuse — every pill keeps its 44pt target (review, issue 107).
  Widget _toolbarStrip(AppLocalizations l10n, GameState state) {
    final buttons = _toolbarButtons(l10n, state);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: _toolbarStripWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                buttons[i],
              ],
            ],
          ),
        ),
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
            ListTile(
              leading: const Icon(Icons.visibility),
              title: Text(l10n.revealSolution),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmReveal(l10n);
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

  /// Cartoon pills: white glyphs rendered on every pastel pill failed
  /// WCAG AA 4.5:1 on all three skins (issue 87), so only the danger pill
  /// keeps white and every other pill paints the skin's ink. Classic
  /// (null pill) keeps the theme's default text color.
  Color? _foreground() {
    if (pillColor == null) return null;
    final tokens = this.tokens;
    if (tokens == null) return Colors.white;
    return pillColor == tokens.dangerColor ? Colors.white : tokens.ink;
  }
}

/// One toolbar row of equal-width [buttons] with ≥4px logical seams between
/// them, so pills (skin shadows, the active tool's ink outline) never touch
/// at any width (issue 88).
Widget _toolbarRow(List<Widget> buttons) => Row(
  children: [
    for (var i = 0; i < buttons.length; i++) ...[
      if (i > 0) const SizedBox(width: 4),
      buttons[i],
    ],
  ],
);

/// The landscape toolbar strip's fixed width (issue 107), mirroring the
/// `_panelMinWidth` discipline: one labeled pill column. 56 = the 48dp
/// touch target plus room so the widest ru label («Подсказка», Roboto
/// ideal ≈50.5px at the 10px label font) keeps a ≥9px effective size in its
/// (56 − 8)px paint box — the issue-88 label floor carried to the strip.
const double _toolbarStripWidth = 56;

/// The suspect panel's minimum content height on phones (issue 95): the
/// suspects header plus a scrollable sliver of its grid (issue 39's pinned
/// branch clamps and scrolls under the header). When the leftover above the
/// single-row toolbar (issue 107) is tighter than this, the board shrinks
/// to fit instead (overflow is never allowed).
const double _panelMinHeight = 72;

/// The suspect panel's minimum width in the wide game branch (issue 103):
/// the landscape board's square slot is capped to `width − _panelMinWidth`,
/// so a window taller than wide (e.g. 600×1000) keeps the panel at the
/// pre-issue 300px column instead of crushing it to zero width.
const double _panelMinWidth = 300;

/// The test key of a tool button, matching the tool's name.
String _toolKeyName(Tool tool) => switch (tool) {
  Tool.place => 'tool_place',
  Tool.markX => 'tool_mark',
};

/// The skin's color for one toolbar action; null keeps the classic scheme.
Color? _actionColor(SkinActions? actions, Color Function(SkinActions) pick) =>
    actions == null ? null : pick(actions);
