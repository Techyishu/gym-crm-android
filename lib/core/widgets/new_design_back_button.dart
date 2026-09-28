import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Where the ← on Money / Check-in returns to. Those screens are shell
/// branches, so opening them from another branch leaves no pop history —
/// the opener records its own location here instead.
String? _returnTo;

/// Opens a branch screen (Money, Check-in) from Home or the Dashboard and
/// remembers where to come back to. [location] may carry a query
/// (`/staff/billing?tab=plans`).
void openWithReturn(BuildContext context, String location) {
  _returnTo = GoRouter.of(context).routerDelegate.currentConfiguration.uri
      .toString();
  context.go(location);
}

/// Money and Check-in are nav tabs in the old design but open from Home cards
/// in the new one, so there they get a ← that returns wherever they were opened
/// from (Home card, Dashboard's Collect…), or Home when that's unknown
/// (a notification, a web refresh). The phone's back button does the same.
/// Renders nothing for old-design gyms.
class NewDesignBackButton extends ConsumerWidget {
  /// The screen's own route, so the back-button hook only acts while that
  /// screen is the one showing (tab screens stay mounted offstage).
  final String route;
  final bool onDark;
  const NewDesignBackButton({
    super.key,
    required this.route,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym =
        ref.watch(staffProfileProvider).valueOrNull?['gyms']
            as Map<String, dynamic>?;
    if (!usesNewHome(gym)) return const SizedBox.shrink();

    void back() {
      final target = _returnTo ?? '/staff/home';
      _returnTo = null;
      GoRouter.of(context).go(target);
    }

    return BackButtonListener(
      onBackButtonPressed: () async {
        final router = GoRouter.of(context);
        final loc = router.routerDelegate.currentConfiguration.uri.path;
        // Only while this screen is the one showing — tab screens stay
        // mounted offstage. A sheet or pushed page on top pops first.
        if (!loc.startsWith(route) || router.canPop()) return false;
        back();
        return true;
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
          button: true,
          label: 'Back',
          child: GestureDetector(
            onTap: back,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: onDark ? AppTheme.darkInset : AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                AppIcons.arrowBack,
                size: 20,
                color: onDark ? AppTheme.onDark : AppTheme.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
