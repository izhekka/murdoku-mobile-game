import 'package:material_ui/material_ui.dart';

import 'package:murdoku/l10n/generated/app_localizations.dart';

/// First-launch walkthrough: three pages covering the four rules plus the
/// X-mark affordance. Shown over the home screen until dismissed; dismissal
/// persists `tutorialSeen`.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = [
      [l10n.rule1Text, l10n.rule2Text],
      [l10n.rule3Text, l10n.tutorialXHint],
      [l10n.rule4Text],
    ];
    final isLast = _page == pages.length - 1;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 320,
          height: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.howToPlayTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    for (final page in pages)
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final text in page)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    text,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.tutorialDone,
                    onPressed: widget.onDismiss,
                  ),
                  // Issue 31: at 320px with large system text the intrinsic
                  // label no longer fits beside the close button. The loose
                  // Flexible caps the button at the space left by the icon;
                  // the scale-down FittedBox then fits the label into that
                  // width (the toolbar miniButton pattern).
                  Flexible(
                    child: FilledButton(
                      onPressed: () {
                        if (isLast) {
                          widget.onDismiss();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isLast ? l10n.tutorialDone : l10n.tutorialNext,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
