import 'package:flutter/material.dart';
import 'responsive_content.dart';

/// Drop-in replacement for [showModalBottomSheet]: slides up from the bottom
/// on phones, but on wide viewports (Flutter web on desktop) shows the same
/// content as a centered dialog instead — a bottom sheet reads as a mobile
/// pattern once there's no thumb to reach the bottom edge with.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color? backgroundColor,
  bool isDismissible = true,
  double? maxWidth,
  double? maxHeight,
}) {
  if (!ResponsiveContent.isWide(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      isDismissible: isDismissible,
      builder: builder,
    );
  }

  return showDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: isDismissible,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: backgroundColor ?? Theme.of(dialogContext).canvasColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? 480,
          maxHeight: maxHeight ?? 680,
        ),
        child: builder(dialogContext),
      ),
    ),
  );
}
