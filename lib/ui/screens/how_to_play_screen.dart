import 'package:material_ui/material_ui.dart';

import 'package:murdoku/l10n/generated/app_localizations.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rules = [
      l10n.rule1Text,
      l10n.rule2Text,
      l10n.rule3Text,
      l10n.rule4Text,
    ];
    final glossary = [
      l10n.glossaryRowCol,
      l10n.glossaryBeside,
      l10n.glossaryDirections,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.howToPlayTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < rules.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text('${i + 1}'),
                ),
                title: Text(rules[i]),
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              l10n.glossaryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final entry in glossary)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(entry),
            ),
        ],
      ),
    );
  }
}
