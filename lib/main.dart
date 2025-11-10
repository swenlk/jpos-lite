import 'package:flutter/material.dart';
import 'package:lite/screens/home_page.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/app_consts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> mainConfigs() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Background services
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(AppConsts.baseUrl, AppConfigs.baseUrl); // Base url is needed for background services

  runApp(
      const MyApp()
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),

      home: const HomePage(),
    );
  }
}