import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar_manager.dart';
import '../utils/app_configs.dart';
import '../api/endpoints.dart';

class AddCustomerDialog extends StatefulWidget {
  final Function(String name, String contactNumber) onSave;
  final bool fingerprintEnabled;

  const AddCustomerDialog({
    super.key,
    required this.onSave,
    this.fingerprintEnabled = false,
  });

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  String? activeToken;
  bool _skipVerification = true;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _receivedOtp;
  String? _customerId;
  String? _fingerprintId;
  String? _fingerprintStatus;
  bool _customerCreated = false;

  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadActiveToken();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      activeToken = prefs.getString('activeToken');
      print('token - ${activeToken}');
    });
  }

  Future<void> _createCustomer() async {
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

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final requestBody = {
        'activeToken': activeToken,
        'name': _nameController.text.trim(),
        'contactNumber': _contactController.text.trim(),
        'skipVerification': _skipVerification,
      };

      print('📡 Calling create_customer API with: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.createCustomer,
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

      print('✅ Create customer response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          final customerData = jsonResponse['customer'];

          // Extract fingerprint data if present
          final fingerprintData = customerData['fingerprint'] as Map<String, dynamic>?;
          if (fingerprintData != null) {
            setState(() {
              _fingerprintId = fingerprintData['id']?.toString();
              _fingerprintStatus = fingerprintData['status']?.toString();
            });
            print('✅ Fingerprint data received - ID: $_fingerprintId, Status: $_fingerprintStatus');
          }

          if (_skipVerification) {
            // Always call onSave to refresh the customer list
            widget.onSave(
              _nameController.text.trim(),
              _contactController.text.trim(),
            );
            
            // Mark customer as created and disable Save button
            setState(() {
              _customerCreated = true;
            });
            
            // If fingerprint is enabled and fingerprint data is present, keep dialog open for scanning
            if (widget.fingerprintEnabled && _fingerprintId != null && _fingerprintId!.isNotEmpty) {
              SnackbarManager.showSuccess(
                context,
                message: 'Customer created successfully! You can now scan the fingerprint.',
              );
            } else {
              // Success - close dialog and show success message
              SnackbarManager.showSuccess(
                context,
                message: 'Customer created successfully!',
              );
              Navigator.of(context).pop();
            }
          } else {
            // OTP verification required
            setState(() {
              _otpSent = true;
              _receivedOtp = customerData['otp']?.toString();
              _customerId = customerData['_id']?.toString();
            });
            SnackbarManager.showSuccess(
              context,
              message: 'OTP sent successfully!',
            );
          }
        } else {
          final errorMessage = jsonResponse['status_description'] ??
              'Failed to create customer';
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage = jsonResponse['status_description'] ??
            jsonResponse['message'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during create customer: $e');
      String errorMessage = 'Error creating customer';
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

  Future<void> _verifyCustomer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final enteredOtp = _otpController.text.trim();

    if (enteredOtp != _receivedOtp) {
      SnackbarManager.showError(
        context,
        message: 'Invalid OTP. Please try again.',
      );
      return;
    }

    if (activeToken == null || _customerId == null) {
      SnackbarManager.showError(
        context,
        message: 'Missing required information. Please try again.',
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
        'activeToken': activeToken,
        'customerId': _customerId,
      };

      print('📡 Calling verify_customer API with: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.verifyCustomer,
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

      print('✅ Verify customer response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          SnackbarManager.showSuccess(
            context,
            message: 'Customer verified successfully!',
          );
          widget.onSave(
            _nameController.text.trim(),
            _contactController.text.trim(),
          );
          Navigator.of(context).pop();
        } else {
          final errorMessage = jsonResponse['status_description'] ??
              'Failed to verify customer';
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage = jsonResponse['status_description'] ??
            jsonResponse['message'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during verify customer: $e');
      String errorMessage = 'Error verifying customer';
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

  void _handleButtonPress() {
    if (!_skipVerification && _otpSent) {
      _verifyCustomer();
    } else {
      _createCustomer();
    }
  }

  Future<void> _scanFingerprint() async {
    if (activeToken == null || _fingerprintId == null || _fingerprintId!.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Missing required information for fingerprint scan.',
      );
      return;
    }

    // Get fingerprint device IP address from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final fingerprintDeviceIp = prefs.getString('fingerprintDeviceIp');

    if (fingerprintDeviceIp == null || fingerprintDeviceIp.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Please configure the fingerprint device IP address in settings.',
      );
      return;
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      print('🔍 Sending fingerprint scan request with ID: $_fingerprintId');

      final response = await dio.post(
        'http://$fingerprintDeviceIp/ID_NUMBER',
        data: {
          "activeToken": activeToken,
          "ID": _fingerprintId,
        },
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

      print('✅ Fingerprint scan response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data;
        final status = responseData?['status']?.toString() ?? '';
        final message = responseData?['message']?.toString() ?? 'Fingerprint scan initiated';
        final step = responseData?['step']?.toString() ?? '';
        final id = responseData?['ID']?.toString() ?? '';

        print('Status: $status, Step: $step, Message: $message, ID: $id');

        // Show the message from the API response based on status
        final statusLower = status.toLowerCase();
        if (statusLower == 'success') {
          SnackbarManager.showSuccess(
            context,
            message: message,
          );
          // Close the dialog on successful fingerprint scan
          Navigator.of(context).pop();
        } else if (statusLower == 'progress') {
          SnackbarManager.showInfo(
            context,
            message: message,
          );
          Navigator.of(context).pop();
        } else if (statusLower == 'error' || statusLower == 'failed') {
          SnackbarManager.showError(
            context,
            message: message,
          );
        } else {
          // Default to info for unknown statuses
          SnackbarManager.showInfo(
            context,
            message: message,
          );
        }
      } else {
        final errorMessage =
            response.data?['message'] ??
                response.data?['error'] ??
                'Server returned status ${response.statusCode}';
        SnackbarManager.showError(
          context,
          message: errorMessage,
        );
      }
    } on DioException catch (e) {
      print('❌ DioException during fingerprint scan: $e');
      String errorMessage = 'Error scanning fingerprint';

      if (e.response != null) {
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');
        errorMessage =
            e.response?.data?['message'] ??
                e.response?.data?['error'] ??
                'Server error (${e.response?.statusCode})';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Connection timeout. Please check your connection to the fingerprint scanner.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Request timeout. Please try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage =
            'Connection error. Please check if the fingerprint scanner is connected.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }

      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ General error during fingerprint scan: $e');
      SnackbarManager.showError(context, message: 'Unexpected error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
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
                  'Add New Customer',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 24.0),

                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    hintText: 'Enter customer name',
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
                      return 'Please enter customer name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16.0),

                // Contact field
                TextFormField(
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Contact Number',
                    hintText: 'Enter contact number',
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
                      return 'Please enter contact number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16.0),

                // Skip Verification toggle
                Row(
                  children: [
                    const Text(
                      'Skip Verification',
                      style: TextStyle(
                        fontSize: 16.0,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: _skipVerification,
                      onChanged: (value) {
                        setState(() {
                          _skipVerification = value;
                        });
                      },
                    ),
                  ],
                ),

                // Scan Fingerprint button (shown when fingerprint is enabled and customer is created with fingerprint data)
                if (widget.fingerprintEnabled && _customerCreated && _fingerprintId != null && _fingerprintId!.isNotEmpty) ...[
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _scanFingerprint,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Scan Fingerprint'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xffd41818),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ),
                ],

                // OTP text field (only shown when verification is not skipped and OTP is sent)
                if (!_skipVerification && _otpSent) ...[
                  const SizedBox(height: 16.0),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Enter OTP',
                      hintText: 'Enter the OTP received',
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
                      if (!_skipVerification && _otpSent) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter the OTP';
                        }
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 16.0),

                // Action buttons
                Row(
                  children: [
                    // Cancel button
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
                          onPressed: () {
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

                    // Save button
                    Expanded(
                      child: Container(
                        height: 44.0,
                        decoration: BoxDecoration(
                          color: (_customerCreated && widget.fingerprintEnabled) 
                              ? Colors.grey 
                              : Colors.green,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: TextButton(
                          onPressed: (_isLoading || (_customerCreated && widget.fingerprintEnabled)) 
                              ? null 
                              : _handleButtonPress,
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
                              : Text(
                                  _skipVerification
                                      ? 'Save'
                                      : (_otpSent ? 'Verify' : 'Send OTP'),
                                  style: const TextStyle(
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

  static void show({
    required BuildContext context,
    required Function(String name, String contactNumber) onSave,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AddCustomerDialog(onSave: onSave);
      },
    );
  }
}
