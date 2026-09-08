import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// L'interruttore della dashboard desktop, quello delle opzioni: 32x18,
/// acceso pieno blu con bordo chiaro, spento grigio su grigio.
///
/// Sta qui e non dentro una schermata perché lo usano in due — l'elenco dei
/// moduli e quello delle soglie — e due copie dello stesso interruttore sono
/// due occasioni di scriverlo diverso.
class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.on, this.onColor});

  final bool on;

  /// Per un interruttore che non vuol dire «acceso» ma qualcos'altro: nella
  /// lista delle soglie l'ambra dice «può entrare nella vista dinamica», e
  /// il blu è già preso dall'essere acceso in generale.
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final tint = onColor ?? AppColors.accentSolid;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 32,
      height: 18,
      decoration: BoxDecoration(
        color: on ? tint : AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: on ? (onColor ?? AppColors.accent) : AppColors.border,
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: on ? Colors.white : AppColors.disabled,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
