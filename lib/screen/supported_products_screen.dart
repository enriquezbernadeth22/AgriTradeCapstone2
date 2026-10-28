import '../widgets/agri_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/commodity_master_list.dart';
import '../theme/app_colors.dart';

/// The full, always-up-to-date Supported Products list — reads straight
/// from CommodityRegistry (the Admin-managed commodity list, the single
/// source of truth) so it can never drift out of sync with what Add
/// Product's autocomplete and the AI price guide recognize. Opened from: the Farmer setup "Supported
/// Products in AgriTrade+" section, the Add Product top banner, and the
/// "unsupported product" dialog.
class SupportedProductsScreen extends StatelessWidget {
  const SupportedProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: const AgriAppBar(title: 'Supported Products'),
      // Rebuilds whenever the Admin adds, moves or disables a commodity.
      body: ListenableBuilder(
        listenable: CommodityRegistry.instance,
        builder: (context, _) => _list(),
      ),
    );
  }

  Widget _list() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(
          'Only products on this list can be posted in the marketplace.',
          style: GoogleFonts.montserrat(
            fontSize: 13,
            color: AppColors.text,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        for (final entry
            in CommodityRegistry.instance.activeByCategory.entries) ...[
          Text(
            entry.key,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.value
                .map(
                  (name) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.mid.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      name,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
