import 'package:flutter/material.dart';
import 'mubu_button.dart';

class HoverCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  
  const HoverCloseButton({
    super.key, 
    required this.onTap, 
    this.size = 18
  });

  @override
  Widget build(BuildContext context) {
    // Custom height mapping since icon MubuButton scales with height
    return MubuButton(
      icon: Icons.close_rounded,
      type: MubuButtonType.icon,
      onPressed: onTap,
      customHeight: size + 14, // padding adjustment
    );
  }
}
