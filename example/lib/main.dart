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

  @override
  Widget build(BuildContext context) {
    return ChipsSelector<String>(
      underlineColor: Colors.black,
      chipBuilder: (context, state, data) => Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          border: Border.all(color: Colors.white),
          borderRadius: const BorderRadius.all(Radius.circular(4.0)),
        ),
        child: Text(data ?? "empty"),
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
            child: Text(data ?? "empty"),
          ),
        );
      },
      findSuggestions: (query) => [
        "Chip Option 1",
        "Chip Option 2",
        "Chip Option 3",
        "Chip Option 4",
        "Chip Option 5",
        "Chip Option 6",
      ],
      onChanged: (v) {
        // use the updated list of chips here
      },
    );
  }
}
