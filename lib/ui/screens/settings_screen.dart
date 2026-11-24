import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart'
    show LanguageSetting, SkinSetting;
import 'package:murdoku/ui/widgets/dialogs.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              l10n.themeModeLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SegmentedButton<ThemeMode>(
            // Same uniform segment treatment as the skin control (issue 76).
            showSelectedIcon: false,
            style: const ButtonStyle(
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => ref
                .read(settingsControllerProvider.notifier)
                .setThemeMode(selection.first),
          ),
          // The cartoon skins are light-only (issue 23): explain that the
          // ThemeMode choice applies to Классика alone.
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Text(
              l10n.themeModeCaption,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              l10n.skinLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SegmentedButton<SkinSetting>(
            // Uniform segment treatment (issue 76): at the 402x874 iPhone
            // viewport the selected segment's check icon chrome plus the
            // longest skin name exceed the quarter-tile width and the 14px labels
            // wrapped mid-word («Классик/а», «Stick/er»). The check is redundant
            // (the selected segment is already filled in by the theme) and a
            // uniform 12px label keeps every skin label on one line. Per-PNG
            // pixel verdicts travel with the issue 76 run report (screenshots
            // stay uncommitted artifacts under the gitignored build/).
            showSelectedIcon: false,
            style: const ButtonStyle(
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: [
              ButtonSegment(
                value: SkinSetting.classic,
                label: Text(l10n.skinClassic),
              ),
              ButtonSegment(
                value: SkinSetting.candy,
                label: Text(l10n.skinCandy),
              ),
              ButtonSegment(
                value: SkinSetting.sticker,
                label: Text(l10n.skinSticker),
              ),
              ButtonSegment(
                value: SkinSetting.comic,
                label: Text(l10n.skinComic),
              ),
            ],
            selected: {settings.skin},
            onSelectionChanged: (selection) => ref
                .read(settingsControllerProvider.notifier)
                .setSkin(selection.first),
          ),
          SwitchListTile(
            title: Text(l10n.hapticsLabel),
            value: settings.haptics,
            onChanged: (value) =>
                ref.read(settingsControllerProvider.notifier).setHaptics(value),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              l10n.languageLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SegmentedButton<LanguageSetting>(
            // Same uniform segment treatment as the skin control (issue 76).
            showSelectedIcon: false,
            style: const ButtonStyle(
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: [
              ButtonSegment(
                value: LanguageSetting.system,
                label: Text(l10n.languageSystem),
              ),
              ButtonSegment(
                value: LanguageSetting.russian,
                label: Text(l10n.languageRussian),
              ),
              ButtonSegment(
                value: LanguageSetting.english,
                label: Text(l10n.languageEnglish),
              ),
            ],
            selected: {settings.language},
            onSelectionChanged: (selection) => ref
                .read(settingsControllerProvider.notifier)
                .setLanguage(selection.first),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: Text(l10n.resetProgress),
            onTap: () => _resetProgress(context, ref, l10n),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Item icons: game-icons.net (Lorc, Delapouite, caro-asercion) — CC BY 3.0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetProgress(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.resetConfirmTitle,
      body: l10n.resetConfirmBody,
      confirmLabel: l10n.resetProgress,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(prefsRepositoryProvider).resetProgress();
    ref.read(gameControllerProvider.notifier).quit();
    ref.invalidate(statsControllerProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.progressReset)));
    }
  }
}
