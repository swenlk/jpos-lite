
import 'main.dart';
import 'utils/app_configs.dart';
import 'utils/enums/flavors.dart';

Future<void> main() async {
  AppConfigs.initializeFlavor(flavor: Flavor.dev, showFlavorBanner: true, baseUrl: 'http://124.43.79.70:5000');
  mainConfigs();
}