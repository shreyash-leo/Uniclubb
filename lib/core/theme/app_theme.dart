import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final generated = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final scheme = generated.copyWith(
      primary: light ? AppColors.primary : const Color(0xFFA9AAFF),
      onPrimary: Colors.white,
      primaryContainer:
          light ? AppColors.primaryLight : const Color(0xFF292A61),
      onPrimaryContainer:
          light ? AppColors.primaryPressed : const Color(0xFFE4E4FF),
      surface: light ? AppColors.surface : const Color(0xFF17181E),
      onSurface: light ? AppColors.textPrimary : const Color(0xFFF5F5F7),
      onSurfaceVariant:
          light ? AppColors.textSecondary : const Color(0xFFB7BAC4),
      outline: light ? AppColors.outline : const Color(0xFF3A3C46),
      outlineVariant: light ? AppColors.outline : const Color(0xFF2A2C34),
      surfaceContainer:
          light ? AppColors.secondaryBackground : const Color(0xFF202129),
      surfaceContainerLow:
          light ? AppColors.secondaryBackground : const Color(0xFF1C1D24),
      error: AppColors.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor:
          light ? AppColors.background : const Color(0xFF101116),
    );
    final text = base.textTheme.copyWith(
      headlineMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -.7,
      ),
      headlineSmall: TextStyle(
        color: scheme.onSurface,
        fontSize: 24,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -.45,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        height: 1.22,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -.15,
      ),
      titleSmall: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final rounded16 =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final buttonOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: .12);
      }
      if (states.contains(WidgetState.hovered)) {
        return Colors.white.withValues(alpha: .08);
      }
      return Colors.transparent;
    });
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        toolbarHeight: 68,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        constraints: const BoxConstraints(minHeight: 52),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: .06),
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: ShapeDecoration(
          color: scheme.primary,
          shape: const StadiumBorder(),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: scheme.onSurfaceVariant,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        splashBorderRadius: BorderRadius.circular(20),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: .12);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primaryPressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.primaryHover;
            }
            return scheme.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: buttonOverlay,
          shape: WidgetStatePropertyAll(rounded16),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primaryPressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.primaryHover;
            }
            return scheme.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: buttonOverlay,
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(rounded16),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: scheme.outline),
          shape: rounded16,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: rounded16,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primaryContainer
                  : scheme.surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(CircleBorder()),
          overlayColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? scheme.primary.withValues(alpha: .1)
                  : Colors.transparent),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
