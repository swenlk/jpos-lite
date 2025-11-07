import 'enums/flavors.dart';

class AppConfigs {
  static Flavor appFlavor = Flavor.prod;
  static bool showFlavorBanner = false;
  static String baseUrl = '';

  static void initializeFlavor({required Flavor flavor, bool showFlavorBanner=false, required String baseUrl}) {
    AppConfigs.appFlavor = flavor;
    AppConfigs.showFlavorBanner = showFlavorBanner;
    AppConfigs.baseUrl = baseUrl;
  }
}