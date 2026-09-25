import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material 3 window size classes.
enum WindowSize {
  /// Phones in portrait (< 600 dp wide).
  compact,

  /// Large phones in landscape, small tablets, unfolded foldables (< 840 dp).
  medium,

  /// Tablets, desktops, Chromebooks, DeX (>= 840 dp).
  expanded;

  static WindowSize of(double width) {
    if (width < 600) return WindowSize.compact;
    if (width < 840) return WindowSize.medium;
    return WindowSize.expanded;
  }
}

extension ResponsiveContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);

  /// Horizontal page padding that grows with the window.
  double get pagePadding => switch (windowSize) {
    WindowSize.compact => 16,
    WindowSize.medium => 24,
    WindowSize.expanded => 32,
  };

  /// True on devices whose shortest side is tablet-sized.
  bool get isTabletLike => MediaQuery.sizeOf(this).shortestSide >= 600;
}

/// Number of list columns that fit [width] with items at least
/// [minItemWidth] wide.
int adaptiveColumns(
  double width, {
  double minItemWidth = 420,
  int maxColumns = 3,
}) => math.max(1, math.min(maxColumns, (width / minItemWidth).floor()));

/// Centers [child] and caps its width, for forms and reading layouts that
/// look stretched on tablets and in landscape.
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// A sliver list that becomes a multi-column layout on wide windows.
///
/// Unlike a grid, rows size to their tallest item, so list tiles with
/// variable height (long titles, large text settings) never clip.
class SliverAdaptiveList extends StatelessWidget {
  const SliverAdaptiveList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 420,
    this.maxColumns = 3,
    this.spacing = 12,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = adaptiveColumns(
          constraints.crossAxisExtent,
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
        );
        if (columns == 1) {
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              itemBuilder,
              childCount: itemCount,
            ),
          );
        }
        final rows = (itemCount + columns - 1) ~/ columns;
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, row) {
            final start = row * columns;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(
                      child: start + c < itemCount
                          ? itemBuilder(context, start + c)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          }, childCount: rows),
        );
      },
    );
  }
}

/// Orientation policy for browsing screens (the player manages its own).
abstract final class AppOrientation {
  /// Phones browse in portrait; tablets, foldables and large screens may
  /// rotate freely.
  static List<DeviceOrientation> browsing() => _isTabletLike()
      ? DeviceOrientation.values
      : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];

  static Future<void> applyBrowsing() =>
      SystemChrome.setPreferredOrientations(browsing());

  /// Native orientation command matching [browsing] for the
  /// `parthi_play/orientation` channel.
  static String nativeBrowsingCommand() =>
      _isTabletLike() ? 'setFullSensor' : 'setSensorPortrait';

  static bool _isTabletLike() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }
}
