import 'package:flutter/material.dart';
import 'package:lite/utils/app_configs.dart';

/// Displays a top-left banner for non-production app flavors.
class FlavorBanner extends StatelessWidget {
  final Widget child;
  final Color? color;
  final BannerLocation? location;

  const FlavorBanner({
    super.key,
    required this.child,
    this.color,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppConfigs.showFlavorBanner) {
      return child;
    }

    final bannerColor = color ?? Colors.red;
    final bannerTextColor =
        HSLColor.fromColor(bannerColor).lightness < 0.8
            ? Colors.white
            : Colors.black87;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        color: bannerColor,
        message: AppConfigs.appFlavor.name.toUpperCase(),
        location: location ?? BannerLocation.topStart,
        textStyle: TextStyle(
          color: bannerTextColor,
          fontSize: 12.0 * 0.85,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
        child: child,
      ),
    );
  }
}
