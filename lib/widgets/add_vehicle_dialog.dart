import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar_manager.dart';
import '../utils/app_configs.dart';
import '../api/endpoints.dart';

class AddVehicleDialog extends StatefulWidget {
  final String customerId;
  final VoidCallback onSave;

  const AddVehicleDialog({
    super.key,
    required this.customerId,
    required this.onSave,
  });

  @override
  State<AddVehicleDialog> createState() => _AddVehicleDialogState();

  static void show({
    required BuildContext context,
    required String customerId,
    required VoidCallback onSave,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AddVehicleDialog(
          customerId: customerId,
          onSave: onSave,
        );
      },
    );
  }
}

class _AddVehicleDialogState extends State<AddVehicleDialog> {
  String? activeToken;
  bool _isLoading = false;

  final _vehicleNumberController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadActiveToken();
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      activeToken = prefs.getString('activeToken');
    });
  }

  Future<void> _saveVehicleNumber() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    final vehicleNumber = _vehicleNumberController.text.trim();
    if (vehicleNumber.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Please enter vehicle number.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final requestBody = {
        'activeToken': activeToken ?? '',
        'customerId': widget.customerId,
        'value': vehicleNumber,
      };

      print('📡 Calling add_info API with: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.addInfo,
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (status) {
            return status != null && status < 500;
          },
        ),
      );

      print('✅ Add info response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          SnackbarManager.showSuccess(
            context,
            message: 'Vehicle number saved successfully!',
          );
          // Call onSave callback to trigger sync
          widget.onSave();
          Navigator.of(context).pop();
        } else {
          final errorMessage = jsonResponse['status_description'] ??
              'Failed to save vehicle number';
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage = jsonResponse['status_description'] ??
            jsonResponse['message'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during save vehicle number: $e');
      String errorMessage = 'Error saving vehicle number';
      if (e.response != null) {
        final errorResponse = e.response!.data;
        errorMessage = errorResponse['status_description'] ??
            errorResponse['message'] ??
            'Server error';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Connection timeout. Please try again.';
      } else {
        errorMessage = 'Connection error. Please check your internet connection.';
      }
      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ Unexpected error: $e');
      SnackbarManager.showError(
        context,
        message: 'An unexpected error occurred. Please try again.',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      elevation: 8.0,
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add New Vehicle',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24.0),
                TextFormField(
                  controller: _vehicleNumberController,
                  decoration: InputDecoration(
                    labelText: 'Vehicle Number',
                    hintText: 'Enter vehicle number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2.0,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter vehicle number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24.0),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44.0,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 1.0,
                          ),
                        ),
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Container(
                        height: 44.0,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: TextButton(
                          onPressed: _isLoading ? null : _saveVehicleNumber,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
