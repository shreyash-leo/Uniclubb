import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniclub/core/theme/app_theme.dart';
import 'package:uniclub/ui/app_colors.dart';

void main() {
  test('theme uses the approved single-accent palette', () {
    final theme = AppTheme.light;

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.primaryContainer, AppColors.primaryLight);
    expect(theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondary);
  });

  test('tab selection has pill geometry without square press overlay', () {
    final tabs = AppTheme.light.tabBarTheme;

    expect(tabs.indicator, isA<ShapeDecoration>());
    final decoration = tabs.indicator! as ShapeDecoration;
    expect(decoration.shape, isA<StadiumBorder>());
    expect(
      tabs.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    expect(tabs.splashFactory, NoSplash.splashFactory);
  });

  test('buttons and navigation keep stable target sizes', () {
    final theme = AppTheme.light;
    final button = theme.filledButtonTheme.style;

    expect(button?.minimumSize?.resolve({}), const Size(64, 52));
    expect(theme.navigationBarTheme.height, 72);
    expect(
      theme.navigationBarTheme.labelBehavior,
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
  });
}
