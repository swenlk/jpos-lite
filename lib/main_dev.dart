
import 'main.dart';
import 'utils/app_configs.dart';
import 'utils/enums/flavors.dart';

Future<void> main() async {
  AppConfigs.initializeFlavor(flavor: Flavor.dev, showFlavorBanner: true, baseUrl: 'http://169.58.42.245:5000');
  mainConfigs();
}