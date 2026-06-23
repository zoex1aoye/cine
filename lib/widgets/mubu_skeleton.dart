import 'package:flutter/material.dart';

class MubuSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Widget? child;

  const MubuSkeleton({
    Key? key,
    this.width = double.infinity,
    this.height = double.infinity,
    this.borderRadius = 8.0,
    this.child,
  }) : super(key: key);

  @override
  State<MubuSkeleton> createState() => _MubuSkeletonState();
}

class _MubuSkeletonState extends State<MubuSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.05, end: 0.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: widget.child,
        );
      },
    );
  }
}
