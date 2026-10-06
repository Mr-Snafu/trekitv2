import 'package:flutter/material.dart';

import '../theme/trekit_theme.dart';

class QuickCaptureButton extends StatelessWidget {
  const QuickCaptureButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        onPressed: isLoading ? null : onPressed,
        tooltip: 'Quick capture',
        style: IconButton.styleFrom(
          backgroundColor: TrekItColors.deepTeal,
          disabledBackgroundColor: TrekItColors.teal.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          fixedSize: const Size.square(42),
        ),
        icon: isLoading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.photo_camera_rounded, size: 24),
      ),
    );
  }
}
