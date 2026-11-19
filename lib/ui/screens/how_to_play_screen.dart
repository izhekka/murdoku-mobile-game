import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Placeholder until Task 16 fills in the rules.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.howToPlayTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
