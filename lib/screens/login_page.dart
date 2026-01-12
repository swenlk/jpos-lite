import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:lite/api/endpoints.dart';
import 'package:lite/screens/home_page.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  TextEditingController usernameController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffd41818),
      body: SafeArea(
        child: Column(
          children: [
            // Red Header Section with Logo
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                color: Color(0xffd41818),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // JMAP Logo
                    Image.asset(
                      'assets/images/jpos-lite.png',
                      height: 80,
                      width: 380,
                    ),
                  ],
                ),
              ),
            ),

            // White Login Form Card
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30.0),
                    topRight: Radius.circular(30.0),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Section
                        Row(
                          children: [
                            Container(
                              width: 40.0,
                              height: 40.0,
                              decoration: BoxDecoration(
                                color: Color(0xffd41818),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20.0,
                              ),
                            ),
                            const SizedBox(width: 16.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome Back',
                                    style: TextStyle(
                                      fontSize: 24.0,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    'Sign in to continue',
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 40.0),

                        // Username Field
                        TextField(
                          controller: usernameController,
                          decoration: InputDecoration(
                            hintText: 'Enter username',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: Color(0xffd41818), width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: Color(0xffd41818), width: 2.0),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                          ),
                          onEditingComplete: () {
                            setState(() {});
                          },
                        ),

                        const SizedBox(height: 24.0),

                        // Password Field
                        TextField(
                          controller: passwordController,
                          obscureText: !_isPasswordVisible,
                          decoration: InputDecoration(
                            hintText: 'Enter password',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Color(0xffd41818),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: Color(0xffd41818), width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: Color(0xffd41818), width: 2.0),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                          ),
                          onEditingComplete: () {
                            setState(() {});
                          },
                        ),

                        const SizedBox(height: 32.0),

                        // Sign In Button
                        SizedBox(
                          width: double.infinity,
                          height: 56.0,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () {
                              onLoginPressed();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xffd41818),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 20.0,
                                ),
                                const SizedBox(width: 12.0),
                                _isLoading
                                    ? SizedBox(
                                  height: 20.0,
                                  width: 20.0,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 18.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 40.0),

                        // Copyright
                        Center(
                          child: Text(
                            '©${DateTime.now().year} JPosLite. All rights reserved.',
                            style: TextStyle(
                              fontSize: 12.0,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> onLoginPressed() async {
    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      SnackbarManager.showError(context, message: 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final username = usernameController.text;
      final password = passwordController.text;

      final dio = Dio();

      final url = AppConfigs.baseUrl+ApiEndpoints.authenticate;
      final response = await dio.post(
        url,
        data: {"username": username, "password": password},
      );
      final jsonResponse = response.data;

      if (jsonResponse['status_code'] == 'S1000') {
        final activeToken = jsonResponse['authentication_token'] ?? '';
        final businessName = jsonResponse['businessName'] ?? '';
        final customers = jsonResponse['customers'] ?? [];
        final items = jsonResponse['items'] ?? [];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('activeToken', activeToken);
        await prefs.setString('businessName', businessName);
        await prefs.setString('customers', json.encode(customers));
        await prefs.setString('items', json.encode(items));

        // Check if logo is enabled and download/store image if available
        final configurations = jsonResponse['configurations'] as Map<String, dynamic>?;
        if (configurations != null && configurations['logoEnabled'] == true) {
          final imageURL = jsonResponse['imageURL'] ?? '';
          if (imageURL.isNotEmpty) {
            await prefs.setString('imageURL', imageURL);
            // Download and cache the image
            await _downloadAndCacheImage(imageURL, prefs);
          }
        }

        // Store fingerprint value from configurations
        if (configurations != null && configurations['fingerprint'] != null) {
          await prefs.setBool('fingerprint', configurations['fingerprint'] == true);
        } else {
          await prefs.setBool('fingerprint', false);
        }

        // Store tileMode value from configurations
        if (configurations != null && configurations['tileLayout'] != null) {
          await prefs.setBool('tileLayout', configurations['tileLayout'] == true);
        } else {
          await prefs.setBool('tileLayout', false);
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      } else {
        SnackbarManager.showError(context, message: jsonResponse['status_description']);
      }
    } on DioError catch (e) {
      if (e.response != null) {
        final Map<String, dynamic> errorResponse = e.response!.data;
        SnackbarManager.showError(context, message: errorResponse['status_description'] ?? 'Server error.');
      } else {
        SnackbarManager.showError(context, message: 'Connection error. Please check your internet connection and try again.');
      }
    } catch (e) {
      SnackbarManager.showError(context, message: 'Connection error. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndCacheImage(String imageURL, SharedPreferences prefs) async {
    try {
      // Extract file extension from URL or default to .jpg
      final uri = Uri.parse(imageURL);
      final pathSegments = uri.pathSegments;
      final fileName = pathSegments.isNotEmpty 
          ? pathSegments.last 
          : 'business_logo.jpg';
      
      // Ensure filename has an extension
      final fileExtension = fileName.contains('.') 
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '.jpg';
      final finalFileName = fileName.contains('.') 
          ? fileName 
          : 'business_logo$fileExtension';

      // Use app's internal storage directory (works on Android without path_provider)
      // Construct path manually for Android: /data/data/<package_name>/files/images/
      String filePath;
      if (Platform.isAndroid) {
        // Android internal storage path
        const packageName = 'com.jsoft.jpos.lite';
        final imageDir = Directory('/data/data/$packageName/files/images');
        
        // Create images directory if it doesn't exist
        if (!await imageDir.exists()) {
          await imageDir.create(recursive: true);
        }
        
        filePath = '${imageDir.path}/$finalFileName';
      } else {
        // For other platforms, use a simple relative path
        final imageDir = Directory('./images');
        if (!await imageDir.exists()) {
          await imageDir.create(recursive: true);
        }
        filePath = '${imageDir.path}/$finalFileName';
      }

      // Download the image directly to file using Dio's download method
      final dio = Dio();
      await dio.download(
        imageURL,
        filePath,
        options: Options(
          responseType: ResponseType.stream,
        ),
      );

      // Verify file was created
      final file = File(filePath);
      if (await file.exists()) {
        // Store the local file path in SharedPreferences
        await prefs.setString('cachedImagePath', filePath);
        print('✅ Image downloaded and saved: $filePath');
      } else {
        throw Exception('File was not created after download');
      }
    } catch (e) {
      print('❌ Error downloading image: $e');
      // Don't throw error - allow login to continue even if image download fails
    }
  }

}
