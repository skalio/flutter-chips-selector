library flutter_chips_selector;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

typedef ChipsBuilder<T> = Widget Function(
  BuildContext context,
  ChipsSelectorState<T> state,
  T data,
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

  // TODO we should replace this with set since we enforce uniqueness in selectSuggestion anyways
  final List<T> initialValue;

  // TODO we should rename this to onChangeChips or something like that
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
  OverlayEntry? suggestionOverlayEntry;
  final LayerLink _layerLink = LayerLink();
  Timer? searchOnStoppedTyping;

  final GlobalKey _endOfChips = GlobalKey(), _endOfTextField = GlobalKey();
  final ValueNotifier<double?> _textInputWidth = ValueNotifier(null);

  final FocusNode _focusableActionDetectorFocusNode = FocusNode(
    debugLabel: "#chip selector: focusableActionDetector focus node",
    skipTraversal: true,
  );

  final FocusNode _rawKeyboardListenerFocusNode = FocusNode(
    debugLabel: "#chip selector: rawKeyboardListener focus node",
    skipTraversal: true,
  );

  /// The chips that are already included
  List<T> _items = [];

  /// Suggestions returned by [widget.findSuggestions]
  /// filtered to remove duplicates that are already in [_items]
  List<T> _suggestionsWithoutItems = [];

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
    widget.textFieldFocusNode.addListener(_textFieldFocusListener);
  }

  void _textFieldFocusListener() {
    if (widget.textFieldFocusNode.hasFocus) {
      suggestionOverlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(suggestionOverlayEntry!);
    } else {
      suggestionOverlayEntry?.remove();
      if (widget.parseOnLeaving != null) {
        List<T> parsedEntries = widget.parseOnLeaving!(_textController.text) as List<T>;
        parsedEntries.forEach((element) {
          selectSuggestion(element);
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChipsSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.initialValue, widget.initialValue)) {
      _items = [...widget.initialValue];
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _overlayScrollController.dispose();
    _focusableActionDetectorFocusNode.dispose();
    _rawKeyboardListenerFocusNode.dispose();
    widget.textFieldFocusNode.removeListener(_textFieldFocusListener);
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
            child: InputDecorator(
              decoration: widget.decoration?.copyWith(
                    labelStyle: TextStyle(color: widget.labelColor),
                  ) ??
                  InputDecoration(),
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
            LogicalKeySet(LogicalKeyboardKey.arrowDown): _SuggestionsTraverseDownIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowUp): _SuggestionsTraverseUpIntent(),
            LogicalKeySet(LogicalKeyboardKey.enter): SelectIntent(),
            LogicalKeySet(LogicalKeyboardKey.delete): _DeleteLastChipIntent(),
            LogicalKeySet(LogicalKeyboardKey.backspace): _DeleteLastChipIntent(),
          },
          actions: {
            if (_textController.text.length == 0 && _items.length > 0)
              _DeleteLastChipIntent: CallbackAction<_DeleteLastChipIntent>(
                onInvoke: (_) {
                  setState(() {
                    _items.removeLast();
                  });
                  widget.onChanged(_items);

                  return;
                },
              ),
            SelectIntent: CallbackAction<SelectIntent>(
              onInvoke: (_) => _onEnterSelectOrMoveNextFocus(),
            ),
            _SuggestionsTraverseDownIntent: CallbackAction<DirectionalFocusIntent>(
              onInvoke: (intent) {
                assert(intent.direction == TraversalDirection.down);
                if (_suggestionsWithoutItems.length > 0) {
                  setState(
                    () {
                      _selectedIndex = (_selectedIndex + 1 >= _suggestionsWithoutItems.length) ? 0 : _selectedIndex + 1;
                      suggestionOverlayEntry?.markNeedsBuild();
                    },
                  );
                  _scrollDown();
                }
                return;
              },
            ),
            _SuggestionsTraverseUpIntent: CallbackAction<DirectionalFocusIntent>(
              onInvoke: (intent) {
                assert(intent.direction == TraversalDirection.up);
                if (_suggestionsWithoutItems.length > 0) {
                  setState(
                    () {
                      _selectedIndex =
                          (_selectedIndex - 1 < 0) ? _suggestionsWithoutItems.length - 1 : _selectedIndex - 1;
                      suggestionOverlayEntry?.markNeedsBuild();
                    },
                  );
                  _scrollUp();
                }
                return;
              },
            ),
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
              onTapOutside: (_) {
                // do nothing, especially not the default behaviour
                // we handle the unfocus in our overlay with a TapRegion
              },
              onSubmitted: (_) {},
              onEditingComplete: () {},
              onChanged: (String newText) async {
                print(_rawKeyboardListenerFocusNode.hasFocus);
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
                        _suggestionsWithoutItems =
                            _suggestionsResult.where((element) => !_items.contains(element)).toList();
                        if (_suggestionsWithoutItems.length > 0) _selectedIndex = 0;
                      });
                    } else {
                      _suggestionsWithoutItems.clear();
                      _selectedIndex = -1;
                    }
                    suggestionOverlayEntry?.markNeedsBuild();
                  }),
                );
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
    );
  }

  void _onEnterSelectOrMoveNextFocus() {
    if (_selectedIndex > -1) {
      selectSuggestion(_suggestionsWithoutItems[_selectedIndex]);
      setState(() {
        _selectedIndex = -1;
      });
    } else {
      widget.nextFocusNode.requestFocus();
    }
  }

  bool get _overlayIsVisible => _suggestionsWithoutItems.isNotEmpty;
  OverlayEntry _createOverlayEntry() {
    RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    var size = renderBox?.size;

    return OverlayEntry(
      builder: (context) {
        return Positioned(
          width: size!.width,
          child: CompositedTransformFollower(
            link: this._layerLink,
            showWhenUnlinked: false,
            child: FocusScope(
              child: Material(
                elevation: 4.0,
                child: TapRegion(
                  behavior: HitTestBehavior.opaque,
                  onTapOutside: (event) {
                    FocusScope.of(context).unfocus();
                  },
                  // Visibility is down here because we still want to use the tapRegion of the overlay
                  // if we introduce another tap region outside the overlay for unfocusing the textField
                  // we get the same issues as if we used the default onTapOutside of TextField
                  child: Visibility(
                    visible: _overlayIsVisible,
                    child: LimitedBox(
                      //suggestion list shall be one third of the viewport max
                      maxHeight: MediaQuery.of(context).size.height / 3,
                      child: ListView.builder(
                        controller: _overlayScrollController,
                        shrinkWrap: true,
                        addAutomaticKeepAlives: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _suggestionsWithoutItems.length,
                        itemBuilder: (BuildContext context, int index) {
                          return Container(
                            color: _selectedIndex == index ? Theme.of(context).hoverColor : Colors.transparent,
                            child: widget.suggestionBuilder(context, this, _suggestionsWithoutItems[index]),
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
      },
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
    if (!exists) {
      setState(() {
        _textController.clear();
        _items.add(data);
        _suggestionsWithoutItems.clear();
      });
      widget.onChanged(_items);
      suggestionOverlayEntry?.markNeedsBuild();
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
      _suggestionsWithoutItems = [];
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

class _SuggestionsTraverseDownIntent extends DirectionalFocusIntent {
  const _SuggestionsTraverseDownIntent() : super(TraversalDirection.down);
}

class _SuggestionsTraverseUpIntent extends DirectionalFocusIntent {
  _SuggestionsTraverseUpIntent() : super(TraversalDirection.up);
}

class _DeleteLastChipIntent extends Intent {
  const _DeleteLastChipIntent();
}
