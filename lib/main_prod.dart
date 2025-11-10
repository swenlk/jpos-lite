

import 'main.dart';
import 'utils/app_configs.dart';
import 'utils/enums/flavors.dart';

Future<void> main() async {
  AppConfigs.initializeFlavor(flavor: Flavor.prod, baseUrl: 'https://api.jpos.lk');
  mainConfigs();
}