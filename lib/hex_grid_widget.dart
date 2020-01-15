library hexagonal_grid_widget;

import 'dart:math';

import 'package:after_layout/after_layout.dart';
import 'package:flutter/material.dart';
import 'package:hexagonal_grid/hexagonal_grid.dart';
import 'hex_grid_child.dart';
import 'hex_grid_context.dart';

typedef HexGridChild FindHexGridChild(int q, int r, int s);

@immutable
class HexGridWidget extends StatefulWidget {
  HexGridWidget({
    @required this.hexGridContext,
    @required this.children,
    this.scrollListener
  });

  final HexGridContext hexGridContext;
  final FindHexGridChild children;

  final ValueChanged<Offset> scrollListener;
  final ValueNotifier<Offset> offsetNotifier = ValueNotifier(Offset(0, 0));

  @override
  State<StatefulWidget> createState() =>
      _HexGridWidgetState(hexGridContext, scrollListener, offsetNotifier);

  //Set the x and y scroll offset
  set offset(Offset offset) {
    offsetNotifier.value = offset;
  }
}

class _HexGridWidgetState extends State<HexGridWidget>
    with SingleTickerProviderStateMixin, AfterLayoutMixin<HexGridWidget> {
  final GlobalKey _containerKey = GlobalKey();
  bool _isAfterFirstLayout = false;

  HexGridContext _hexGridContext;

  double xPos = 0.0;
  double yPos = 0.0;
  double xViewPos = 0.0;
  double yViewPos = 0.0;
  Point origin = Point(0.0, 0.0);

  Animation<Offset> _flingAnimation;
  bool _enableFling = false;

  AnimationController _controller;
  ValueChanged<Offset> _scrollListener;
  ValueNotifier<Offset> _offsetNotifier;

  _HexGridWidgetState(
      HexGridContext hexGridContext,
      ValueChanged<Offset> scrollListener,
      ValueNotifier<Offset> offsetNotifier) {
    _hexGridContext = hexGridContext;

    if (scrollListener != null) {
      _scrollListener = scrollListener;
    }

    if (offsetNotifier != null) {
      _offsetNotifier = offsetNotifier;
      _offsetNotifier.addListener(updateOffsetFromNotifier);
    }
  }

  @override
  void initState() {
    super.initState();

    _isAfterFirstLayout = false;

    _controller = AnimationController(vsync: this)
      ..addListener(_handleFlingAnimation);
  }

  @override
  void dispose() {
    _controller?.dispose();

    //Don't dispose as other's might be using it. It would be up to the owner,
    // in this case HexGridWidget, to dispose of it. So only clean up after
    // ourselves (this class, _HexGridWidgetState)
    _offsetNotifier?.removeListener(updateOffsetFromNotifier);

    super.dispose();
  }

  @override
  void afterFirstLayout(BuildContext context) {
    _isAfterFirstLayout = true;

    final double containerWidth = this.containerWidth;
    final double containerHeight = this.containerHeight;

    //Determine the origin of the container. Since we'll be using origin w.r.t
    // to the bounding boxes of the hex children, which are positioned by
    // top and left values, we'll have to adjust by half of the widget size to
    // get the technical origin.
    origin = Point((containerWidth / 2) - (_hexGridContext.size / 2),
        (containerHeight / 2) - (_hexGridContext.size / 2));

    //Center the hex grid to origin
    offset = Offset(origin.x, origin.y);
  }

  void updateOffsetFromNotifier() => offset = _offsetNotifier.value;

  set offset(Offset offset) {
    setState(() {
      xViewPos = offset.dx;
      yViewPos = offset.dy;
    });
  }

  double get containerHeight {
    RenderBox containerBox = _containerKey.currentContext.findRenderObject();
    return containerBox.size.height;
  }

  double get containerWidth {
    RenderBox containerBox = _containerKey.currentContext.findRenderObject();
    return containerBox.size.width;
  }

  void _handleFlingAnimation() {
    if (!_enableFling ||
        _flingAnimation.value.dx.isNaN ||
        _flingAnimation.value.dy.isNaN) {
      return;
    }

    double newXPosition = xPos + _flingAnimation.value.dx;
    double newYPosition = yPos + _flingAnimation.value.dy;

    setState(() {
      xViewPos = newXPosition;
      yViewPos = newYPosition;
    });

    _sendScrollValues();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final RenderBox referenceBox = context.findRenderObject();
    final Offset position = referenceBox.globalToLocal(details.globalPosition);

    double newXPosition = xViewPos + (position.dx - xPos);
    double newYPosition = yViewPos + (position.dy - yPos);

    setState(() {
      xViewPos = newXPosition;
      yViewPos = newYPosition;
    });

    xPos = position.dx;
    yPos = position.dy;

    _sendScrollValues();
  }

  void _handlePanDown(DragDownDetails details) {
    _enableFling = false;
    final RenderBox referenceBox = context.findRenderObject();
    final Offset position = referenceBox.globalToLocal(details.globalPosition);

    xPos = position.dx;
    yPos = position.dy;
  }

  void _handlePanEnd(DragEndDetails details) {
    final double magnitude = details.velocity.pixelsPerSecond.distance;
    final double velocity = magnitude / 1000;

    final Offset direction = details.velocity.pixelsPerSecond / magnitude;
    final double distance = (Offset.zero & context.size).shortestSide;

    xPos = xViewPos;
    yPos = yViewPos;

    _enableFling = true;
    _flingAnimation = Tween<Offset>(
            begin: Offset(0.0, 0.0),
            end: direction * distance * _hexGridContext.velocityFactor)
        .animate(_controller);
    _controller
      ..value = 0.0
      ..fling(velocity: velocity);
  }

  _sendScrollValues() {
    if (_scrollListener != null) {
      _scrollListener(Offset(xViewPos, yViewPos));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget childToShow;
    if (!_isAfterFirstLayout) {
      childToShow = Container();
    } else {
      childToShow = Stack(
          children: _buildHexWidgets(
              _hexGridContext.size,
              xViewPos,
              yViewPos));
    }

    return GestureDetector(
      onPanDown: _handlePanDown,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).backgroundColor,
          ),
          key: _containerKey,
          child: childToShow),
    );
  }

  List<Widget> _buildHexWidgets(
    double hexSize,
    double layoutOriginX,
    double layoutOriginY) {

    final layoutOrigin = Point(
      layoutOriginX,
      layoutOriginY
    );
    final spiralOrigin = Point(origin.x - layoutOriginX, origin.y - layoutOriginY);

    HexLayout flatLayout = HexLayout.orientFlat(
      Point(hexSize, hexSize),
      layoutOrigin);

    final double containerWidth = this.containerWidth;
    final double containerHeight = this.containerHeight;
    final double largestAxis = max(containerWidth, containerHeight);

    //2.5 here is a magic number that just happens to get enough hexes to fill the screen with minimal rendering off canvas
    final int radiusInHexes = (largestAxis / hexSize / 2.5).ceil();

    final hexesToRender = hexSpiral(Hex.fromPoint(flatLayout, spiralOrigin), radiusInHexes);
    final List<Positioned> hexWidgetList = hexesToRender.map((hex) {
      final child = widget.children(hex.q, hex.r, hex.s);
      return _createPositionWidgetForHex(child, hex, flatLayout, containerWidth, containerHeight);
    }).where((h) => h != null).toList();

    return hexWidgetList;
  }

  ///Only return a [Positioned] if the widget will be visible, otherwise return
  /// null so we don't waste CPU cycles on rendering something that's not visible
  /// NOTE: As with the rest of a Hex grid, the x and y coordinates are reflected
  Positioned _createPositionWidgetForHex(
    HexGridChild hexGridChild,
    Hex hex,
    HexLayout hexLayout,
    double containerWidth,
    double containerHeight) {

    final Point hexToPixel = hex.toPixel(hexLayout);

    return Positioned(
        top: hexToPixel.y,
        left: hexToPixel.x,
        child: hexGridChild.toHexWidget(context, _hexGridContext, hex));
  }

  void _centerHexLayout() {
    xPos = xViewPos;
    yPos = yViewPos;

    _enableFling = true;
    _flingAnimation = Tween<Offset>(
            begin: Offset(0, 0), end: Offset(origin.x - xPos, origin.y - yPos))
        .animate(_controller);
    _controller
      ..value = 0.0
      ..fling(velocity: 1);
  }
}

List<Hex> hexSpiral(Hex originHex, int radiusInHexes) {
  List<Hex> hexList = [];
  hexList.add(originHex);

  //Start at one since we already seeded the origin
  Hex neighborHex = originHex;
  for (int orbital = 1; orbital < radiusInHexes; orbital++) {
    neighborHex = neighborHex.neighbor(0);
    for (int direction = 0; direction < Hex.directions.length; direction++) {
      for (int o = 0; o < orbital; o++) {
        hexList.add(neighborHex);
        neighborHex =
          neighborHex.neighbor((direction + 2) % Hex.directions.length);
      }
    }
  }
  return hexList;
}
