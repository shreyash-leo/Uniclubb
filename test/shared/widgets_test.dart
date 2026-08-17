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

  testWidgets('EmptyState does not overflow a tightly constrained viewport',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 27,
              width: 329,
              child: EmptyState(
                icon: Icons.grid_on_outlined,
                title: 'No posts yet',
                message: 'Posts you publish will appear here.',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No posts yet'), findsOneWidget);
  });

  testWidgets('AsyncErrorState does not overflow a tight viewport',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 51,
              width: 329,
              child: AsyncErrorState(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('route text controllers remain alive through reverse transitions',
      (tester) async {
    final controller = TextEditingController();
    var disposed = false;
    controller.addListener(() {});

    final disposal = disposeTextControllersAfterRoute([controller]).then((_) {
      disposed = true;
    });

    await tester.pump();
    controller.text = 'still mounted';
    expect(disposed, isFalse);

    await tester.pump(const Duration(milliseconds: 399));
    expect(disposed, isFalse);

    await tester.pump(const Duration(milliseconds: 1));
    await disposal;
    expect(disposed, isTrue);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
