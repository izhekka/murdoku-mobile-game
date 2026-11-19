import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Placeholder until Task 14 builds the real settings screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
