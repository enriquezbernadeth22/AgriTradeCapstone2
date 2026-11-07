import 'package:flutter/material.dart';

import '../services/market_demand_service.dart';
import '../theme/app_colors.dart';
import '../l10n/app_language.dart';

/// How a demand level reads and its colour, on the Farmer's Market tab
/// (Buyer Areas). The Buyer's product cards have no demand badge (removed
/// by the user, 2026-11-07).
(String label, Color color) demandLevelStyle(DemandLevel level) =>
    switch (level) {
      DemandLevel.high => (tl('High'), AppColors.mid),
      DemandLevel.moderate => (
        tl('Moderate'),
        AppColors.tone(Colors.orange, 800),
      ),
      DemandLevel.low => (tl('Low'), AppColors.grey(700)),
    };
