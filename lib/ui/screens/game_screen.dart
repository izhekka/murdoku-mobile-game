import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Placeholder until Task 12 assembles the real game screen.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
