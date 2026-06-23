import 'package:flutter/material.dart';
import '../api/mubu_constants.dart';
import 'mubu_button.dart';

/// A shared "Load More" button used across all pages.
/// Now implemented using the unified MubuButton component.
class LoadMoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const LoadMoreButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MubuButton(
      label: MubuConstants.loadMore,
      icon: Icons.expand_more_rounded,
      type: MubuButtonType.secondary,
      onPressed: onTap,
    );
  }
}
