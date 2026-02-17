import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_filepicker/core/file_picker_config.dart';
import 'package:app_filepicker/providers/font_provider.dart';
import 'package:app_filepicker/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:app_filepicker/core/localization.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  @override
  Widget build(BuildContext context) {
    final fontProvider = context.watch<FontSizeProvider>();
    final fontSize = fontProvider.getScaledSize(16);

    return Scaffold(
      appBar: AppBar(
        title: Text('settings_title'.tr()),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _buildSection(
            title: 'settings_section_display'.tr(),
            fontSize: fontSize,
            children: [
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: Text('settings_font_size'.tr()),
                subtitle: Text('${(fontProvider.scaleFactor * 100).toInt()}%'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showFontSizeDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text('settings_recent_count'.tr()),
                subtitle: FutureBuilder<int>(
                   future: SharedPreferences.getInstance().then((p) => p.getInt('recentFileCount') ?? 10),
                   builder: (context, snapshot) {
                     return Text('settings_count_unit'.tr(namedArgs: {'count': '${snapshot.data ?? 10}'}));
                   }
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showRecentCountDialog(),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode),
                title: Text('settings_dark_mode_test'.tr()),
                value: context.watch<ThemeProvider>().isDarkMode,
                onChanged: (val) {
                  context.read<ThemeProvider>().setDarkMode(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'settings_section_info'.tr(),
            fontSize: fontSize,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('settings_version'.tr()),
                subtitle: const Text('1.0.0'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'settings_section_data'.tr(),
            fontSize: fontSize,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: Text('settings_trash_period'.tr()),
                subtitle: FutureBuilder<int>(
                   future: SharedPreferences.getInstance().then((p) => p.getInt('retentionDays') ?? 30),
                   builder: (context, snapshot) {
                     final days = snapshot.data ?? 30;
                     if (days < 0) return Text('settings_no_limit'.tr());
                     return Text('settings_day_unit'.tr(namedArgs: {'days': '$days'}));
                   }
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showRetentionDialog(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children, required double fontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: fontSize.fSmall,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Container(
          color: Theme.of(context).cardColor,
          child: Column(children: children),
        ),
      ],
    );
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<FontSizeProvider>(
          builder: (context, fontProvider, child) {
            final fontSize = fontProvider.getScaledSize(16);
            return AlertDialog(
              title: Text('settings_font_size'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(fontProvider.scaleFactor * 100).toInt()}%', style: TextStyle(fontSize: fontSize.fHeader, fontWeight: FontWeight.bold)),
                  Slider(
                    value: fontProvider.scaleFactor,
                    min: 0.8,
                    max: 1.4,
                    divisions: 5,
                    label: '${(fontProvider.scaleFactor * 100).toInt()}%',
                    onChanged: (val) {
                      fontProvider.setScale(val);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'settings_preview'.tr(),
                    style: TextStyle(fontSize: fontSize.fBody),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('action_confirm'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRetentionDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text('settings_trash_period'.tr()),
          children: [15, 30, 60, -1].map((days) {
            return SimpleDialogOption(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('retentionDays', days);
                if (mounted) {
                  setState(() {}); // refresh subtitle
                  Navigator.of(context).pop();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(days < 0 ? 'settings_no_limit'.tr() : 'settings_day_unit'.tr(namedArgs: {'days': '$days'})),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showRecentCountDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text('settings_recent_count'.tr()),
          children: [5, 10, 20, 50].map((count) {
            return SimpleDialogOption(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('recentFileCount', count);
                if (mounted) {
                  setState(() {}); // refresh subtitle
                  Navigator.of(context).pop();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('settings_count_unit'.tr(namedArgs: {'count': '$count'})),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
