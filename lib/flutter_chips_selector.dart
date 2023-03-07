library flutter_chips_selector;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

typedef ChipsBuilder<T> = Widget Function(
  BuildContext context,
  ChipsSelectorState<T?> state,
  T? data,
);
typedef ChipsInputSuggestions<T> = FutureOr<List<T>> Function(String query);
typedef ParsedItems<T> = FutureOr<List<T>> Function(String query);

class ChipsSelector<T> extends StatefulWidget {
  ChipsSelector({
    Key? key,
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
    this.underlineColor = Colors.transparent,
    this.labelColor,
    FocusNode? currentFocus,
    FocusNode? nextFocus,
  })  : this.textFieldFocusNode = currentFocus ?? FocusNode(), // TODO need to dispose
        this.nextFocusNode = nextFocus ?? FocusNode(), // TODO need to dispose
        super(key: key);

  final ChipsBuilder<T> chipBuilder;
  final ChipsBuilder<T> suggestionBuilder;
  final ChipsInputSuggestions findSuggestions;
  final List<T> initialValue;
  final ValueChanged<List<T>> onChanged;
  final ParsedItems<T>? parseOnLeaving;
  final InputDecoration? decoration;
  final TextStyle? style;
  final Color underlineColor;
  final Color? labelColor;
  final TextInputType? textInputType;
  final TextInputAction? textInputAction;
  final FocusNode textFieldFocusNode;
  final FocusNode nextFocusNode;
  final bool? autofocus;
  final Brightness keyboardBrightness;

  @Deprecated("Use textFieldFocusNode instead")
  FocusNode get current => textFieldFocusNode;

  @Deprecated("Use nextFocusNode instead")
  FocusNode get next => nextFocusNode;

  @override
  State<StatefulWidget> createState() => ChipsSelectorState<T>();
}

class ChipsSelectorState<T> extends State<ChipsSelector<T>> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _overlayScrollController = ScrollController();
  final GlobalKey editKey = GlobalKey();
  @visibleForTesting
  late OverlayEntry overlayEntry;
  final LayerLink _layerLink = LayerLink();
  Timer? searchOnStoppedTyping;

  final GlobalKey _endOfChips = GlobalKey(), _endOfTextField = GlobalKey();
  final ValueNotifier<double?> _textInputWidth = ValueNotifier(null);

  late VoidCallback _textFieldFocusNodeListener;

  final FocusNode _focusableActionDetectorFocusNode = FocusNode(
    debugLabel: "#chip selector: focusableActionDetector focus node",
    skipTraversal: true,
  );

  final FocusNode _rawKeyboardListenerFocusNode = FocusNode(
    debugLabel: "#chip selector: rawKeyboardListener focus node",
    skipTraversal: true,
  );

  List<T> _items = [];
  List<T> _suggestions = [];

  int _selectedIndex = -1;
  Duration _scrollDuration = Duration(milliseconds: 100);
  double _suggestionItemHeight = 65;

  BoxDecoration defaultDecoration = BoxDecoration(
      border: Border.all(
        color: Colors.grey,
      ),
      borderRadius: BorderRadius.all(Radius.circular(5)));

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialValue);
    _textFieldFocusNodeListener = () {
      if (widget.textFieldFocusNode.hasFocus) {
        overlayEntry = _createOverlayEntry();
        Overlay.of(context).insert(overlayEntry);
      } else {
        this.overlayEntry.remove();
        if (widget.parseOnLeaving != null) {
          List<T> parsedEntries = widget.parseOnLeaving!(_textController.text) as List<T>;
          parsedEntries.forEach((element) {
            selectSuggestion(element);
          });
        }
      }
    };
    widget.textFieldFocusNode.addListener(_textFieldFocusNodeListener);
  }

  @override
  @override
  void didUpdateWidget(covariant ChipsSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.initialValue, widget.initialValue)) {
      _items.replaceRange(0, _items.length, widget.initialValue);
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _overlayScrollController.dispose();
    _focusableActionDetectorFocusNode.dispose();
    _rawKeyboardListenerFocusNode.dispose();
    widget.textFieldFocusNode.removeListener(_textFieldFocusNodeListener);
    super.dispose();
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
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: GestureDetector(
              onTap: () {
                FocusScope.of(context).requestFocus(widget.textFieldFocusNode);
              },
              child: InputDecorator(
                decoration:
                    widget.decoration?.copyWith(labelStyle: TextStyle(color: widget.labelColor)) ?? InputDecoration(),
                child: FocusTraversalGroup(
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
                          children: _getWrapWidgets(),
                        ),
                      ),
                      CompositedTransformTarget(link: this._layerLink),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(key: _endOfTextField, width: 0),
      ],
    );
  }

  List<Widget> _getWrapWidgets() {
    List<Widget> wrapWidgets = [];
    _items.forEach((item) {
      wrapWidgets.add(widget.chipBuilder(context, this, item));
    });
    wrapWidgets.add(SizedBox(key: _endOfChips, width: 0));
    _updateTextInputWidth();
    wrapWidgets.add(_buildInput());
    return wrapWidgets;
  }

  Widget _buildInput() {
    return ValueListenableBuilder<double?>(
      valueListenable: _textInputWidth,
      builder: (context, textInputWidth, _) => Container(
        width: textInputWidth,
        child: FocusableActionDetector(
          focusNode: _focusableActionDetectorFocusNode,
          shortcuts: {
            // For some reason `DirectionalFocusIntent(TraversalDirection.down)` does not work
            // TODO investigate
            LogicalKeySet(LogicalKeyboardKey.arrowDown): _MyTraversalDownFocusIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowUp): _MyTraversalUpFocusIntent(),
            LogicalKeySet(LogicalKeyboardKey.enter): SelectIntent()
          },
          actions: {
            for (final intent in [_MyTraversalDownFocusIntent, _MyTraversalUpFocusIntent])
              intent: CallbackAction<DirectionalFocusIntent>(
                onInvoke: (intent) {
                  if (intent.direction == TraversalDirection.down) {
                    if (_suggestions.length > 0) {
                      setState(
                        () {
                          _selectedIndex = (_selectedIndex + 1 >= _suggestions.length) ? 0 : _selectedIndex + 1;
                          overlayEntry.markNeedsBuild();
                        },
                      );
                      _scrollDown();
                    }
                  } else if (intent.direction == TraversalDirection.up) {
                    if (_suggestions.length > 0) {
                      setState(
                        () {
                          _selectedIndex = (_selectedIndex - 1 < 0) ? _suggestions.length - 1 : _selectedIndex - 1;
                          overlayEntry.markNeedsBuild();
                        },
                      );
                      _scrollUp();
                    }
                  }
                  return;
                },
              ),
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
            focusNode: _rawKeyboardListenerFocusNode,
            onKey: (RawKeyEvent event) {
              if (event.isKeyPressed(LogicalKeyboardKey.arrowUp) || event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
                print("lololo");
              }
              if (event.isKeyPressed(LogicalKeyboardKey.delete) || event.isKeyPressed(LogicalKeyboardKey.backspace)) {
                if (_textController.text.length == 0 && _items.length > 0) {
                  setState(() {
                    _items.removeLast();
                  });
                  widget.onChanged(_items);
                }
              }
            },
            child: Padding(
              padding: EdgeInsets.only(top: _items.length > 0 ? 5 : 0),
              child: TextField(
                focusNode: widget.textFieldFocusNode,
                controller: _textController,
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
                        List<T> _suggestionsResult = (await widget.findSuggestions(newText)).cast();
                        setState(() {
                          _suggestions = _suggestionsResult;
                          if (_suggestions.length > 0) _selectedIndex = 0;
                        });
                      } else {
                        _suggestions.clear();
                        _selectedIndex = -1;
                      }
                      overlayEntry.markNeedsBuild();
                    }),
                  );
                },
                onEditingComplete: () {
                  widget.textFieldFocusNode.unfocus();
                  FocusScope.of(context).requestFocus(widget.nextFocusNode);
                },
                minLines: 1,
                maxLines: 1,
                autofocus: widget.autofocus ?? true,
                style: widget.style ?? Theme.of(context).textTheme.bodyText2,
                cursorColor: Theme.of(context).textSelectionTheme.cursorColor,
                decoration: InputDecoration(
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(style: BorderStyle.none)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: widget.underlineColor, width: 2, style: BorderStyle.solid)),
                ),
              ),
            ),
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
                    controller: _overlayScrollController,
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
    bool exists = _items.any((m) => m == data);
    // TODO ? maybe we should not show suggestions that dont exist
    if (!exists) {
      setState(() {
        _textController.clear();
        _items.add(data);
        _suggestions.clear();
      });
      widget.onChanged(_items);
      overlayEntry.markNeedsBuild();
    }
  }

  void triggerChange() {
    widget.onChanged(_items);
  }

  void clearInput() {
    setState(() {
      _textController.clear();
      _items = [];
      _selectedIndex = -1;
      _suggestions = [];
    });
  }

  void _scrollUp() {
    if (_selectedIndex <= 3) {
      if (_overlayScrollController.offset - _suggestionItemHeight > _overlayScrollController.position.minScrollExtent) {
        _overlayScrollController.animateTo(_overlayScrollController.offset - 65,
            duration: _scrollDuration, curve: Curves.easeIn);
      } else {
        _overlayScrollController.animateTo(_overlayScrollController.position.minScrollExtent,
            duration: _scrollDuration, curve: Curves.easeIn);
      }
    } else {
      _overlayScrollController.animateTo(_overlayScrollController.position.maxScrollExtent,
          duration: _scrollDuration, curve: Curves.easeIn);
    }
  }

  void _scrollDown() {
    if (_selectedIndex >= 3) {
      if (_overlayScrollController.offset + _suggestionItemHeight < _overlayScrollController.position.maxScrollExtent) {
        _overlayScrollController.animateTo(_overlayScrollController.offset + _suggestionItemHeight,
            duration: _scrollDuration, curve: Curves.easeIn);
      } else {
        _overlayScrollController.animateTo(_overlayScrollController.position.maxScrollExtent,
            duration: _scrollDuration, curve: Curves.easeIn);
      }
    } else {
      _overlayScrollController.animateTo(0, duration: _scrollDuration, curve: Curves.easeIn);
    }
  }

  void _updateTextInputWidth() {
    if (_endOfChips.currentContext != null) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) {
          if (mounted) {
            const minimumAllowedInputTextWidth = 100.0;
            final double start =
                (_endOfChips.currentContext?.findRenderObject() as RenderBox).localToGlobal(Offset.zero).dx;
            final double end =
                (_endOfTextField.currentContext?.findRenderObject() as RenderBox).localToGlobal(Offset.zero).dx;
            final double remainingGapWidth = end - start - 15;
            _textInputWidth.value =
                remainingGapWidth > minimumAllowedInputTextWidth ? remainingGapWidth : double.infinity;
          }
        },
      );
    }
  }
}

class _MyTraversalDownFocusIntent extends DirectionalFocusIntent {
  const _MyTraversalDownFocusIntent() : super(TraversalDirection.down);
}

class _MyTraversalUpFocusIntent extends DirectionalFocusIntent {
  _MyTraversalUpFocusIntent() : super(TraversalDirection.up);
}
