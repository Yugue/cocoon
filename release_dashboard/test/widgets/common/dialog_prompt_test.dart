// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:conductor_ui/widgets/clean_release_button.dart';
import 'package:conductor_ui/widgets/common/dialog_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String title = 'Are you sure you want to clean up the persistent state file?';
  const String content = 'This will abort a work in progress release.';
  const String leftButtonTitle = 'Yes';
  const String rightButtonTitle = 'No';

  group('Dialog prompt without input confirmation tests', () {
    testWidgets('Appears upon clicking on a button', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  dialogPrompt(
                    context: context,
                    title: const Text(title),
                    content: const Text(content),
                    leftButtonTitle: leftButtonTitle,
                    rightButtonTitle: rightButtonTitle,
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      expect(find.byType(ElevatedButton), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text(content), findsOneWidget);
      expect(find.text(leftButtonTitle), findsOneWidget);
      expect(find.text(rightButtonTitle), findsOneWidget);
    });

    testWidgets('Disappears when the left button is clicked', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  dialogPrompt(
                    context: context,
                    title: const Text(title),
                    content: const Text(content),
                    leftButtonTitle: leftButtonTitle,
                    rightButtonTitle: rightButtonTitle,
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(leftButtonTitle));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Disappears when the right button is clicked', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  dialogPrompt(
                    context: context,
                    title: const Text(title),
                    content: const Text(content),
                    leftButtonTitle: leftButtonTitle,
                    rightButtonTitle: rightButtonTitle,
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(rightButtonTitle));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Executes the left button callback when the left button is clicked, right callback is not called',
        (WidgetTester tester) async {
      bool isLeftButtonCallbackCalled = false;
      Future<void> leftButtonCallback() async {
        isLeftButtonCallbackCalled = true;
      }

      bool isRightButtonCallbackCalled = false;
      Future<void> rightButtonCallback() async {
        isRightButtonCallbackCalled = true;
      }

      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  dialogPrompt(
                    context: context,
                    title: const Text(title),
                    content: const Text(content),
                    leftButtonTitle: leftButtonTitle,
                    rightButtonTitle: rightButtonTitle,
                    leftButtonCallback: leftButtonCallback,
                    rightButtonCallback: rightButtonCallback,
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(leftButtonTitle));
      await tester.pumpAndSettle();
      expect(isLeftButtonCallbackCalled, equals(true));
      expect(isRightButtonCallbackCalled, equals(false));
    });

    testWidgets('Executes the right button callback when the right button is clicked, left callback is not called',
        (WidgetTester tester) async {
      bool isLeftButtonCallbackCalled = false;
      Future<void> leftButtonCallback() async {
        isLeftButtonCallbackCalled = true;
      }

      bool isRightButtonCallbackCalled = false;
      Future<void> rightButtonCallback() async {
        isRightButtonCallbackCalled = true;
      }

      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  dialogPrompt(
                    context: context,
                    title: const Text(title),
                    content: const Text(content),
                    leftButtonTitle: leftButtonTitle,
                    rightButtonTitle: rightButtonTitle,
                    leftButtonCallback: leftButtonCallback,
                    rightButtonCallback: rightButtonCallback,
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(rightButtonTitle));
      await tester.pumpAndSettle();
      expect(isLeftButtonCallbackCalled, equals(false));
      expect(isRightButtonCallbackCalled, equals(true));
    });
  });

  group('Dialog prompt with input confirmation tests', () {
    const String requiredConfirmationString = CleanReleaseButton.requiredConfirmationString;
    testWidgets('Appears upon clicking on a button', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: Text(title),
                      content: Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      expect(find.byType(ElevatedButton), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(DialogPromptConfirmInput), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text(content), findsOneWidget);
      expect(find.text(leftButtonTitle), findsOneWidget);
      expect(find.text(rightButtonTitle), findsOneWidget);
    });

    testWidgets('Disappears when the left button is clicked', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: Text(title),
                      content: Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(DialogPromptConfirmInput), findsOneWidget);
      await tester.tap(find.text(leftButtonTitle));
      await tester.pumpAndSettle();
      expect(find.byType(DialogPromptConfirmInput), findsNothing);
    });

    testWidgets('Executes the left button callback when the left button is clicked, right callback is not called',
        (WidgetTester tester) async {
      bool isLeftButtonCallbackCalled = false;
      Future<void> leftButtonCallback() async {
        isLeftButtonCallbackCalled = true;
      }

      bool isRightButtonCallbackCalled = false;
      Future<void> rightButtonCallback() async {
        isRightButtonCallbackCalled = true;
      }

      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: const Text(title),
                      content: const Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                      leftButtonCallback: leftButtonCallback,
                      rightButtonCallback: rightButtonCallback,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(leftButtonTitle));
      await tester.pumpAndSettle();
      expect(isLeftButtonCallbackCalled, equals(true));
      expect(isRightButtonCallbackCalled, equals(false));
    });

    testWidgets('Right button enables when the user input is correct', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: Text(title),
                      content: Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key(rightButtonTitle))).enabled, equals(false));
      await tester.enterText(find.byType(TextFormField), requiredConfirmationString);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key(rightButtonTitle))).enabled, equals(true));
    });

    testWidgets('Right button disables when the user input becomes incorrect', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: Text(title),
                      content: Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), requiredConfirmationString);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key(rightButtonTitle))).enabled, equals(true));
      await tester.enterText(find.byType(TextFormField), '$requiredConfirmationString@');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key(rightButtonTitle))).enabled, equals(false));
    });

    testWidgets(
        'Executes the right button callback when the user input is correct and the right button is clicked, left callback is not called',
        (WidgetTester tester) async {
      bool isLeftButtonCallbackCalled = false;
      Future<void> leftButtonCallback() async {
        isLeftButtonCallbackCalled = true;
      }

      bool isRightButtonCallbackCalled = false;
      Future<void> rightButtonCallback() async {
        isRightButtonCallbackCalled = true;
      }

      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => DialogPromptConfirmInput(
                      confirmationString: requiredConfirmationString,
                      title: const Text(title),
                      content: const Text(content),
                      leftButtonTitle: leftButtonTitle,
                      rightButtonTitle: rightButtonTitle,
                      leftButtonCallback: leftButtonCallback,
                      rightButtonCallback: rightButtonCallback,
                    ),
                  );
                },
                child: const Text('Clean'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), requiredConfirmationString);
      await tester.pumpAndSettle();
      await tester.tap(find.text(rightButtonTitle));
      await tester.pumpAndSettle();
      expect(isLeftButtonCallbackCalled, equals(false));
      expect(isRightButtonCallbackCalled, equals(true));
    });
  });
}
