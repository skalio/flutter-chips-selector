import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_chips_selector/flutter_chips_selector.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _withRequiredParents(Widget child) => MaterialApp(
      home: Scaffold(
        body: Material(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child,
          ),
        ),
      ),
    );

void main() {
  group('ChipSelector', () {
    testWidgets("Suggestion Overlay is closed if focus is lost", (tester) async {
      final GlobalKey<ChipsSelectorState> chipStateKey = GlobalKey();
      final GlobalKey suggestionKey = GlobalKey();

      final FocusNode otherFocus = FocusNode();

      await tester.pumpWidget(
        _withRequiredParents(
          Stack(
            children: [
              Focus(
                focusNode: otherFocus,
                child: SizedBox(
                  height: 100,
                  width: 100,
                ),
              ),
              ChipsSelector<String>(
                key: chipStateKey,
                chipBuilder: (context, state, data) => Container(color: Colors.blue, width: 10, height: 10),
                suggestionBuilder: (context, state, data) => Container(
                  key: suggestionKey,
                  color: Colors.red,
                  width: 100,
                  height: 100,
                ),
                findSuggestions: (query) {
                  return ["SUGGESTION"];
                },
                onChanged: (value) {
                  print(value);
                },
              )
            ],
          ),
        ),
      );

      /// Get chip state to access other fields
      final chipState = chipStateKey.currentState;
      expect(chipState, isNotNull);
      chipState!;

      /// Get text field and enter some text to trigger a suggestion
      final textFieldWidget = find.byKey(chipState.editKey);
      expect(textFieldWidget, findsOneWidget);
      await tester.enterText(textFieldWidget, "SUG");
      await tester.pumpAndSettle();

      /// Check if the suggestion widget is shown
      final suggestionWidget = find.byKey(suggestionKey);
      expect(suggestionWidget, findsOneWidget);

      /// Check that the overlay is visible
      expect(chipState.overlayEntry.mounted, isTrue);

      /// Remove focus
      otherFocus.requestFocus();
      await tester.pumpAndSettle();

      /// Check that the overlay is no longer visible
      expect(chipState.overlayEntry.mounted, isFalse);
    });

    testWidgets("Suggestion Builder onTap callbacks are executed", (tester) async {
      int onTapCounter = 0;
      final GlobalKey buttonKey = GlobalKey();
      final GlobalKey<ChipsSelectorState> chipStateKey = GlobalKey();

      await tester.pumpWidget(
        _withRequiredParents(
          ChipsSelector<String>(
            key: chipStateKey,
            chipBuilder: (context, state, data) => Container(color: Colors.blue, width: 10, height: 10),
            suggestionBuilder: (context, state, data) => GestureDetector(
              key: buttonKey,
              onTap: () {
                onTapCounter += 1;
              },
              child: Container(
                color: Colors.red,
                width: 100,
                height: 100,
              ),
            ),
            findSuggestions: (query) {
              return ["SUGGESTION"];
            },
            onChanged: (value) {
              print(value);
            },
          ),
        ),
      );

      /// Get chip state to access other fields
      final chipState = chipStateKey.currentState;
      expect(chipState, isNotNull);
      chipState!;

      /// Get text field and enter some text to trigger a suggestion
      final textFieldWidget = find.byKey(chipState.editKey);
      expect(textFieldWidget, findsOneWidget);
      await tester.enterText(textFieldWidget, "SUG");
      await tester.pumpAndSettle();

      /// Get the suggestion widget to tap on it
      final suggestionWidget = find.byKey(buttonKey);
      expect(suggestionWidget, findsOneWidget);
      expect(onTapCounter, 0);

      /// Check that the overlay is still visible
      expect(chipState.overlayEntry.mounted, isTrue);

      /// Press the suggestion to trigger its callback
      Offset suggestionWidgetCenter = tester.getCenter(suggestionWidget);
      final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(suggestionWidgetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      /// Check that the suggestion widgets callback has been called
      expect(onTapCounter, 1);

      /// Check that the overlay is no longer visible
      expect(chipState.overlayEntry.mounted, isFalse);
    });
  });
}
