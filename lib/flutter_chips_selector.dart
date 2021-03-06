library flutter_chips_selector;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ChipsBuilder<T> = Widget Function(BuildContext context, ChipsSelectorState<T?> state, T? data);
typedef ChipsInputSuggestions<T> = FutureOr<List<T>> Function(String query);
typedef ParsedItems<T> = FutureOr<List<T>> Function(String query);

class ChipsSelector<T> extends StatefulWidget {
  ChipsSelector(
      {Key? key,
      this.initialValue = const [],
      required this.chipBuilder,
      required this.suggestionBuilder,
      required this.findSuggestions,
      required this.onChanged,
      this.parseOnLeaving,
      this.decoration,
      this.style,
      this.autofocus,
      this.keyboardBrightness = Brightness.light,
      this.textInputType = TextInputType.text,
      this.textInputAction = TextInputAction.done,
      FocusNode? currentFocus,
      FocusNode? nextFocus})
      : this.current = currentFocus ?? FocusNode(),
        this.next = nextFocus ?? FocusNode(),
        super(key: key);

  final ChipsBuilder chipBuilder;
  final ChipsBuilder suggestionBuilder;
  final ChipsInputSuggestions findSuggestions;
  final List<T> initialValue;
  final ValueChanged<List<T>> onChanged;
  final ParsedItems? parseOnLeaving;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextInputType? textInputType;
  final TextInputAction? textInputAction;
  final FocusNode current;
  final FocusNode next;
  final bool? autofocus;
  final Brightness keyboardBrightness;

  @override
  State<StatefulWidget> createState() => ChipsSelectorState<T>();
}

class ChipsSelectorState<T> extends State<ChipsSelector<T?>> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey editKey = GlobalKey();
  late OverlayEntry _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  Timer? searchOnStoppedTyping;

  List<T?> _items = [];
  List<T> _suggestions = [];

  int _selectedIndex = -1;

  BoxDecoration defaultDecoration = BoxDecoration(
      border: Border.all(
        color: Colors.grey,
      ),
      borderRadius: BorderRadius.all(Radius.circular(5)));

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialValue);
    widget.current.addListener(() {
      if (widget.current.hasFocus) {
        this._overlayEntry = this._createOverlayEntry();
        Overlay.of(context)!.insert(this._overlayEntry);
      } else {
        this._overlayEntry.remove();
        if (widget.parseOnLeaving != null) {
          List<T> parsedEntries = widget.parseOnLeaving!(_controller.text) as List<T>;
          parsedEntries.forEach((element) {
            selectSuggestion(element);
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildChipsControl();
  }

  Widget _buildChipsControl() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).requestFocus(widget.current);
            },
            child: InputDecorator(
              decoration: widget.decoration ?? InputDecoration(),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: EdgeInsets.all(0),
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        alignment: WrapAlignment.start,
                        direction: Axis.horizontal,
                        children: _getWrapWidgets(context),
                      ),
                    ),
                    CompositedTransformTarget(
                      link: this._layerLink,
                      child: SizedBox(
                        height: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _getWrapWidgets(BuildContext context) {
    List<Widget> wrapWidgets = [];
    _items.forEach((item) {
      wrapWidgets.add(widget.chipBuilder(context, this, item));
    });
    wrapWidgets.add(_buildInput());
    return wrapWidgets;
  }

  Widget _buildInput() {
    return FocusableActionDetector(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
        LogicalKeySet(LogicalKeyboardKey.enter): SelectIntent(),
      },
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(onInvoke: (intent) {
          if (intent.direction == TraversalDirection.down) {
            if (_suggestions.length > 0) {
              setState(() {
                _selectedIndex = (_selectedIndex + 1 >= _suggestions.length) ? 0 : _selectedIndex + 1;
                _overlayEntry.markNeedsBuild();
              });
            }
          } else if (intent.direction == TraversalDirection.up) {
            if (_suggestions.length > 0) {
              setState(() {
                _selectedIndex = (_selectedIndex - 1 < 0) ? _suggestions.length - 1 : _selectedIndex - 1;
                _overlayEntry.markNeedsBuild();
              });
            }
          }
          return;
        }),
        SelectIntent: CallbackAction<SelectIntent>(onInvoke: (_) {
          if (_selectedIndex > -1) {
            selectSuggestion(_suggestions[_selectedIndex]);
            setState(() {
              _selectedIndex = -1;
            });
          }
          return;
        }),
      },
      child: RawKeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKey: (RawKeyEvent event) {
          if (event.isKeyPressed(LogicalKeyboardKey.delete) || event.isKeyPressed(LogicalKeyboardKey.backspace)) {
            if (_controller.text.length == 0 && _items.length > 0) {
              setState(() {
                _items.removeLast();
              });
              widget.onChanged(_items);
            }
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: _items.length > 0 ? 5 : 0),
          child: EditableText(
            keyboardType: widget.textInputType,
            textInputAction: widget.textInputAction,
            keyboardAppearance: widget.keyboardBrightness,
            key: editKey,
            enableSuggestions: false,
            autocorrect: false,
            onChanged: (String newText) async {
              //wait some time after user has stopped typing
              const duration = Duration(milliseconds: 100);
              if (searchOnStoppedTyping != null) {
                setState(() => searchOnStoppedTyping!.cancel()); // clear timer
              }
              setState(
                () => searchOnStoppedTyping = new Timer(duration, () async {
                  if (newText.length > 1) {
                    var _suggestionsResult = await widget.findSuggestions(newText) as List<T>;
                    setState(() {
                      _suggestions = _suggestionsResult;
                      if (_suggestions.length > 0) _selectedIndex = 0;
                    });
                  } else {
                    _suggestions.clear();
                    _selectedIndex = -1;
                  }
                  _overlayEntry.markNeedsBuild();
                }),
              );
            },
            onEditingComplete: () {
              widget.current.unfocus();
              FocusScope.of(context).requestFocus(widget.next);
            },
            minLines: 1,
            maxLines: 1,
            autofocus: widget.autofocus ?? true,
            forceLine: false,
            style: widget.style ?? Theme.of(context).textTheme.bodyText2!,
            cursorColor: Theme.of(context).textSelectionTheme.cursorColor!,
            backgroundCursorColor: Theme.of(context).backgroundColor,
            focusNode: widget.current,
            controller: _controller,
          ),
        ),
      ),
    );
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    var size = renderBox?.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size!.width,
        child: Visibility(
          visible: _suggestions.isNotEmpty,
          child: CompositedTransformFollower(
            link: this._layerLink,
            showWhenUnlinked: false,
            child: FocusScope(
              child: Material(
                elevation: 4.0,
                child: LimitedBox(
                  //suggestion list shall be one third of the viewport max
                  maxHeight: MediaQuery.of(context).size.height / 3,
                  child: ListView.builder(
                    shrinkWrap: true,
                    addAutomaticKeepAlives: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _suggestions.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Container(
                        color: _selectedIndex == index ? Theme.of(context).hoverColor : Colors.transparent,
                        child: widget.suggestionBuilder(context, this, _suggestions[index]),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void deleteChip(T data) {
    setState(() {
      _items.remove(data);
      widget.onChanged(_items);
    });
  }

  void selectSuggestion(T data) {
    var exists = _items.firstWhere((m) {
      return m == data;
    }, orElse: () {
      return null;
    });
    if (exists == null) {
      setState(() {
        _controller.clear();
        _items.add(data);
        _suggestions.clear();
      });
      widget.onChanged(_items);
      _overlayEntry.markNeedsBuild();
    }
  }

  void triggerChange() {
    widget.onChanged(_items);
  }

  void clearInput() {
    setState(() {
      _controller.clear();
      _items = [];
      _selectedIndex = -1;
      _suggestions = [];
    });
  }
}
