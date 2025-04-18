part of 'card_swiper.dart';

class _CardSwiperState<T extends Widget> extends State<CardSwiper>
    with SingleTickerProviderStateMixin {
  late CardAnimation _cardAnimation;
  late AnimationController _animationController;

  SwipeType _swipeType = SwipeType.none;
  CardSwiperDirection _detectedDirection = CardSwiperDirection.none;
  CardSwiperDirection _detectedHorizontalDirection = CardSwiperDirection.none;
  CardSwiperDirection _detectedVerticalDirection = CardSwiperDirection.none;
  bool _tappedOnTop = false;

  final _undoableIndex = Undoable<int?>(null);
  Queue<CardSwiperDirection> _directionHistory = Queue();
  List<int> deletedList = [];
  int? get _currentIndex => _undoableIndex.state;

  int? get _nextIndex => getValidIndexOffset(1);

  int _numberOfCardsDisplayed = 0;

  bool get _canSwipe => _currentIndex != null && !widget.isDisabled;

  StreamSubscription<ControllerEvent>? controllerSubscription;

  void initData() {
    _undoableIndex.state = widget.initialIndex;

    controllerSubscription =
        widget.controller?.events.listen(_controllerListener);

    _animationController = AnimationController(
      duration: widget.duration,
      vsync: this,
    )
      ..addListener(_animationListener)
      ..addStatusListener(_animationStatusListener);

    _cardAnimation = CardAnimation(
      animationController: _animationController,
      maxAngle: widget.maxAngle,
      initialScale: widget.scale,
      allowedSwipeDirection: widget.allowedSwipeDirection,
      initialOffset: widget.backCardOffset,
      onSwipeDirectionChanged: onSwipeDirectionChanged,
    );
    _numberOfCardsDisplayed = widget.numberOfCardsDisplayed;
  }

  @override
  void initState() {
    initData();
    super.initState();
  }

  void onSwipeDirectionChanged(CardSwiperDirection direction) {
    switch (direction) {
      case CardSwiperDirection.none:
        _detectedVerticalDirection = direction;
        _detectedHorizontalDirection = direction;
      case CardSwiperDirection.right:
      case CardSwiperDirection.left:
        _detectedHorizontalDirection = direction;
      case CardSwiperDirection.top:
      case CardSwiperDirection.bottom:
        _detectedVerticalDirection = direction;
    }

    widget.onSwipeDirectionChange
        ?.call(_detectedHorizontalDirection, _detectedVerticalDirection);
  }

  @override
  void dispose() {
    _animationController.dispose();
    controllerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Padding(
          padding: widget.padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: List.generate(_numberOfCardsDisplayed, (index) {
                  if (index == 0) return _frontItem(constraints);
                  return _backItem(constraints, index);
                }).reversed.toList(),
              );
            },
          ),
        );
      },
    );
  }

  Widget _frontItem(BoxConstraints constraints) {
    return Positioned(
      left: _cardAnimation.left,
      top: _cardAnimation.top,
      child: GestureDetector(
        child: Transform.rotate(
          angle: -_cardAnimation.angle,
          child: ConstrainedBox(
            constraints: constraints,
            child: widget.cardBuilder(
              context,
              _currentIndex!,
              100 * _cardAnimation.left / widget.hThreshold,
              100 * _cardAnimation.top / widget.vThreshold,
            ),
          ),
        ),
        onTap: () async {
          if (widget.isDisabled) {
            await widget.onTapDisabled?.call();
          }
        },
        onPanStart: (tapInfo) {
          if (!widget.isDisabled) {
            final renderBox = context.findRenderObject()! as RenderBox;
            final position = renderBox.globalToLocal(tapInfo.globalPosition);

            if (position.dy < renderBox.size.height / 2) _tappedOnTop = true;
          }
        },
        onPanUpdate: (tapInfo) {
          if (!widget.isDisabled) {
            setState(
              () => _cardAnimation.update(
                tapInfo.delta.dx,
                tapInfo.delta.dy,
                _tappedOnTop,
              ),
            );
          }
        },
        onPanEnd: (tapInfo) {
          if (_canSwipe) {
            _tappedOnTop = false;
            _onEndAnimation();
          }
        },
      ),
    );
  }

  Widget _backItem(BoxConstraints constraints, int index) {
    return Positioned(
      top: (widget.backCardOffset.dy * index) - _cardAnimation.difference.dy,
      left: (widget.backCardOffset.dx * index) - _cardAnimation.difference.dx,
      child: Transform.scale(
        scale: _cardAnimation.scale - ((1 - widget.scale) * (index - 1)),
        child: ConstrainedBox(
          constraints: constraints,
          child: widget.cardBuilder(context, getValidIndexOffset(index)!, 0, 0),
        ),
      ),
    );
  }

  void _controllerListener(ControllerEvent event) {
    return switch (event) {
      ControllerSwipeEvent(:final direction) => _swipe(direction),
      ControllerUndoEvent() => _undo(),
      ControllerRefreshEvent() => _refresh(),
      ControllerMoveEvent(:final index) => _moveTo(index),
    };
  }

  void _refresh() {
    _undoableIndex.state = widget.initialIndex;
    _numberOfCardsDisplayed = widget.numberOfCardsDisplayed;
    _directionHistory = Queue();
    deletedList = [];
    _reset();
  }

  void _animationListener() {
    if (_animationController.status == AnimationStatus.forward) {
      setState(_cardAnimation.sync);
    }
  }

  Future<void> _animationStatusListener(AnimationStatus status) async {
    if (status == AnimationStatus.completed) {
      switch (_swipeType) {
        case SwipeType.swipe:
          await _handleCompleteSwipe();
        default:
          break;
      }

      _reset();
    }
  }

  Future<void> _handleCompleteSwipe() async {
    final isLastCard = _currentIndex! == widget.cardsCount - 1;
    final shouldCancelSwipe = await widget.onSwipe
            ?.call(_currentIndex!, _nextIndex, _detectedDirection) ==
        false;

    if (shouldCancelSwipe) {
      return;
    }

    _undoableIndex.state = _nextIndex;
    _directionHistory.add(_detectedDirection);

    if (isLastCard) {
      widget.onEnd?.call();
    }
  }

  void _reset() {
    onSwipeDirectionChanged(CardSwiperDirection.none);
    _detectedDirection = CardSwiperDirection.none;
    setState(() {
      _animationController.reset();
      _cardAnimation.reset();
      _swipeType = SwipeType.none;
    });
  }

  bool _currentSwipDirectionIsDeleted() {
    var isDeleted = false;
    final direction = _getEndAnimationDirection();
    if (direction == CardSwiperDirection.top &&
        widget.allowedDeleteDirection.up) {
      isDeleted = true;
    } else if (direction == CardSwiperDirection.bottom &&
        widget.allowedDeleteDirection.down) {
      isDeleted = true;
    }
    return isDeleted;
  }

  void _onEndAnimation() {
    final direction = _getEndAnimationDirection();
    final isValidDirection = _isValidDirection(direction);
    if (isValidDirection) {
      _swipe(direction);
    } else {
      if (_currentSwipDirectionIsDeleted()) {
        widget.onAllowedDeleted?.call().then((value) {
          if (!value) {
            _goBack();
          } else {
            _swipe(direction);
            setState(() {
              _numberOfCardsDisplayed = numberOfCardsOnScreen();
            });
          }
        });
      } else {
        _goBack();
      }
    }
  }

  CardSwiperDirection _getEndAnimationDirection() {
    if (_cardAnimation.left.abs() > widget.hThreshold) {
      return _cardAnimation.left.isNegative
          ? CardSwiperDirection.left
          : CardSwiperDirection.right;
    } else if (_cardAnimation.top.abs() > widget.vThreshold) {
      return _cardAnimation.top.isNegative
          ? CardSwiperDirection.top
          : CardSwiperDirection.bottom;
    }
    return CardSwiperDirection.none;
  }

  bool _isValidDirection(CardSwiperDirection direction) {
    return switch (direction) {
      CardSwiperDirection.left => widget.allowedSwipeDirection.left,
      CardSwiperDirection.right => widget.allowedSwipeDirection.right,
      CardSwiperDirection.top => widget.allowedSwipeDirection.up,
      CardSwiperDirection.bottom => widget.allowedSwipeDirection.down,
      _ => false
    };
  }

  void _swipe(CardSwiperDirection direction) {
    if (_currentIndex == null) return;
    _swipeType = SwipeType.swipe;
    _detectedDirection = direction;
    _cardAnimation.animate(context, direction);
  }

  void _goBack() {
    _swipeType = SwipeType.back;
    _cardAnimation.animateBack(context);
  }

  void _undo() {
    if (_directionHistory.isEmpty) return;
    if (_undoableIndex.previousState == null) return;

    final direction = _directionHistory.last;
    final shouldCancelUndo = widget.onUndo?.call(
          _currentIndex,
          _undoableIndex.previousState!,
          direction,
        ) ==
        false;

    if (shouldCancelUndo) {
      return;
    }

    _undoableIndex.undo();
    _directionHistory.removeLast();
    _swipeType = SwipeType.undo;
    _cardAnimation.animateUndo(context, direction);
  }

  void _moveTo(int index) {
    if (index == _currentIndex) return;
    if (index < 0 || index >= widget.cardsCount) return;

    setState(() {
      _undoableIndex.state = index;
    });
  }

  int numberOfCardsOnScreen() {
    if (widget.isHloop && _cardAnimation.left.abs() > widget.hThreshold) {
      return _numberOfCardsDisplayed;
    } else if (widget.isVloop && _cardAnimation.top.abs() > widget.vThreshold) {
      return _numberOfCardsDisplayed;
    }
    if (_currentIndex == null) {
      return 0;
    }

    print("deleted is ${_currentIndex}");
    deletedList.add(_currentIndex ?? 0);
    return math.min(
      _numberOfCardsDisplayed,
      widget.cardsCount - deletedList.length,
    );
  }

  int? getValidIndexOffset(int offset) {
    if (_currentIndex == null) {
      return null;
    }
    var index = _currentIndex! + offset;
    index = index % widget.cardsCount;
    if (deletedList.contains(index) && index != _currentIndex) {
      for (var i = index + 1; i < widget.cardsCount * 2; i++) {
        index = i % widget.cardsCount;
        if (!deletedList.contains(index)) {
          break;
        }
      }
    }
    return index;
    // return 0;
  }
}
