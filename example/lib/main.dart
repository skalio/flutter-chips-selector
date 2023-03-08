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

  static final FocusNode fn = FocusNode(debugLabel: "textFocus");
  static final FocusNode fnTile = FocusNode(debugLabel: "tile");

  static final GlobalKey<ChipsSelectorState> _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ChipsSelector<String>(
      key: _key,
      currentFocus: fn,
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
        // TODO would like to know here whether data is selected or not
        //  add state.isSelected(data) and return null;
        return ListTile(
          focusNode: fnTile,
          key: ValueKey(data),
          onTap: () {
            _key.currentState!.selectSuggestion(data);
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
      findSuggestions: (query) {
        switch (query.toLowerCase()) {
          case "hello":
            return ["hello world", "hello you"];
          case "ping":
            return ["ping pong"];
          case "marco":
            return ["marco polo"];
          default:
            return ["default suggestion #1", "default suggestion #2"];
        }
      },
      onChanged: (v) {},
    );
  }
}
