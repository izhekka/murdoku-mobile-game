import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Placeholder until Task 14 builds the real stats screen.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
