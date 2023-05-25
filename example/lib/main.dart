import 'package:flutter/material.dart';
import 'package:flutter_chips_selector/flutter_chips_selector.dart';

void main() {
  runApp(const _MyApp());
}

class _MyApp extends StatelessWidget {
  const _MyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: MyWidget(),
          ),
        ),
      ),
    );
  }
}

class MyWidget extends StatelessWidget {
  const MyWidget({Key? key}) : super(key: key);

  static final nextFocus = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
            "Type to show suggestion Overlay\nChoose with Arrow-Up and Arrow-Down or with mouse\nSelect with Enter\nRemove with Backspace\nClick Chip to remove\n\nEnter to complete and go to next focus (if no suggestion overlay open)"),
        const Text("\n\nIn this example: Start your input with a # to get the input 1:1 as a suggestion"),
        const SizedBox(height: 40),
        ChipsSelector<String>(
          nextFocus: nextFocus,
          underlineColor: Colors.black,
          chipBuilder: (context, state, data) => Chip(
            onDeleted: () => state.deleteChip(data),
            label: Text(data),
          ),
          labelColor: Colors.grey,
          decoration: const InputDecoration(
            filled: true,
            fillColor: Colors.grey,
            focusColor: Colors.red,
            hoverColor: Colors.black26,
          ),
          autofocus: true,
          suggestionBuilder: (context, state, data) {
            return ListTile(
              onTap: () {
                state.selectSuggestion(data);
              },
              title: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: const BorderRadius.all(Radius.circular(4.0)),
                ),
                child: Text(data),
              ),
            );
          },
          findSuggestions: (query) => query.startsWith("#")
              ? [query]
              : [
                  "Chip Option 1",
                  "Chip Option 2",
                  "Chip Option 3",
                  "Chip Option 4",
                  "Chip Option 5",
                  "Chip Option 6",
                ],
          onChanged: (v) {
            // use this to sync your local state with the ChipsSelector's one
          },
        ),
        const SizedBox(height: 40),
        FloatingActionButton(
          onPressed: () {},
          focusNode: nextFocus,
        ),
      ],
    );
  }
}
