import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import 'agri_dialog.dart';

/// "Choose your language": English or Tagalog, for this phone. The whole app
/// changes as soon as one is chosen.
Future<void> showLanguagePicker(BuildContext context) async {
  final language = await showAgriDialog<AppLanguage>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.language_rounded,
      title: Text(tl('Choose your language'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final language in AppLanguage.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(language.label),
              trailing: language == LanguageController.instance.value
                  ? Icon(Icons.check_rounded, color: AppColors.brand)
                  : null,
              onTap: () => Navigator.pop(dialogContext, language),
            ),
        ],
      ),
    ),
  );
  if (language != null) await LanguageController.instance.choose(language);
}
