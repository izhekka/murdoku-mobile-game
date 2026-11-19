import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Placeholder until Task 9 builds the real home screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
