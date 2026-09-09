import 'package:flutter/material.dart';
import '../home_models.dart';

/// Swipeable tab view for mobile — allows swiping left/right between editor tabs.
class SwipeTabView extends StatefulWidget {
  final List<TabDef> tabs;
  final int activeIndex;
  final void Function(int index) onTabChanged;
  final Widget Function(BuildContext context, int index) tabBuilder;

  const SwipeTabView({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTabChanged,
    required this.tabBuilder,
  });

  @override
  State<SwipeTabView> createState() => _SwipeTabViewState();
}

class _SwipeTabViewState extends State<SwipeTabView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.activeIndex);
  }

  @override
  void didUpdateWidget(SwipeTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex && _pageController.hasClients) {
      _pageController.animateToPage(
        widget.activeIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) {
      return const Center(child: Text('No tabs open'));
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: widget.tabs.length,
      onPageChanged: widget.onTabChanged,
      itemBuilder: (ctx, index) => widget.tabBuilder(ctx, index),
    );
  }
}

/// Tab indicator dots shown at the bottom of the swipe view on mobile.
class TabDotIndicator extends StatelessWidget {
  final int count;
  final int activeIndex;
  final Color activeColor;
  final Color inactiveColor;

  const TabDotIndicator({
    super.key,
    required this.count,
    required this.activeIndex,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? activeColor : inactiveColor.withValues(alpha: 0.4),
          ),
        );
      }),
    );
  }
}
