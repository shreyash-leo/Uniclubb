import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniclub/shared/widgets.dart';

void main() {
  testWidgets('AsyncErrorState renders a retry action', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncErrorState(
            error: StateError('offline'),
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Could not load this page'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });
}
