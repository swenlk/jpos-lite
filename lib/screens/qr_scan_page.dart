import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite/api/endpoints.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/snackbar_manager.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _permissionGranted = false;
  bool _permissionChecked = false;
  String? _scannedValue;
  String? _customerName;
  String? _customerId;
  bool _isCheckingCode = false;
  bool _isUpdatingInfo = false;
  String? _lastRequestedCode;
  bool _hasCheckedIn = false;
  bool _hasMeal = false;
  bool _isScanSuccess = false;
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    returnImage: false,
  );

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    // Request camera permission automatically as soon as the page loads.
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _permissionGranted = status.isGranted;
        _permissionChecked = true;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;
    if (!mounted) return;

    // Avoid spamming the API with the same code or while a request is in-flight.
    if (_isCheckingCode || rawValue == _lastRequestedCode) {
      return;
    }

    setState(() {
      _scannedValue = rawValue;
    });

    _handleQrScanned(rawValue);
  }

  Future<String?> _getActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('activeToken');
  }

  Future<void> _handleQrScanned(String qrCode) async {
    final activeToken = await _getActiveToken();
    if (activeToken == null || activeToken.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    setState(() {
      _isCheckingCode = true;
      _lastRequestedCode = qrCode;
      _customerName = null;
      _customerId = null;
      _hasCheckedIn = false;
      _hasMeal = false;
      _isScanSuccess = false;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final requestBody = {
        'activeToken': activeToken,
        'qrCode': qrCode,
      };

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.qrScan,
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

      final data = response.data;
      if (response.statusCode == 200 &&
          data != null &&
          data['status_code'] == 'S1000') {
        final customer = data['customer'] as Map<String, dynamic>?;
        if (customer == null) {
          throw Exception('Customer data not found in response');
        }

        final info = customer['info'];
        bool checkedIn = false;
        bool meal = false;

        if (info is List) {
          for (final entry in info) {
            if (entry is Map && entry.containsKey(qrCode)) {
              final qrObject = entry[qrCode];
              if (qrObject is Map) {
                checkedIn = qrObject['checkedIn'] == true;
                meal = qrObject['meal'] == true;
              }
              break;
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _customerName = customer['name'] as String?;
          _customerId = customer['_id'] as String?;
          _hasCheckedIn = checkedIn;
          _hasMeal = meal;
          _isScanSuccess = true;
        });
      } else {
        final errorMessage = data?['status_description'] ??
            'Failed to fetch customer for QR code';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      String message = 'Error validating QR code';
      if (e.response != null) {
        message = e.response?.data?['status_description'] ??
            e.response?.data?['message'] ??
            'Server error (${e.response?.statusCode})';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Connection timeout. Please try again.';
      } else {
        message = 'Network error: ${e.message}';
      }
      if (mounted) {
        SnackbarManager.showError(context, message: message);
      }
    } catch (e) {
      if (mounted) {
        SnackbarManager.showError(
          context,
          message: 'Unexpected error: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingCode = false;
        });
      }
    }
  }

  Future<void> _updateInfo({
    required String qrCode,
    required bool checkedIn,
    required bool meal,
  }) async {
    final activeToken = await _getActiveToken();
    if (activeToken == null || activeToken.isEmpty || _customerId == null) {
      SnackbarManager.showError(
        context,
        message: 'Missing data. Please scan again or login.',
      );
      return;
    }

    setState(() {
      _isUpdatingInfo = true;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final value = {
        qrCode: {
          'checkedIn': checkedIn,
          'meal': meal,
        },
      };

      final requestBody = {
        'activeToken': activeToken,
        'customerId': _customerId,
        // Send QR info as an array to match the `info` structure.
        'value': [value],
      };

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.updateInfo,
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

      final data = response.data;
      if (response.statusCode == 200 &&
          data != null &&
          data['status_code'] == 'S1000') {
        if (mounted) {
          setState(() {
            _hasCheckedIn = checkedIn;
            _hasMeal = meal;
            // Clear current scan state after a successful update
            _scannedValue = null;
            _customerName = null;
            _customerId = null;
            _lastRequestedCode = null;
            _isScanSuccess = false;
          });
          SnackbarManager.showSuccess(
            context,
            message: 'Customer info updated successfully.',
          );
        }
      } else {
        final errorMessage = data?['status_description'] ??
            'Failed to update customer info';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      String message = 'Error updating info';
      if (e.response != null) {
        message = e.response?.data?['status_description'] ??
            e.response?.data?['message'] ??
            'Server error (${e.response?.statusCode})';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Connection timeout. Please try again.';
      } else {
        message = 'Network error: ${e.message}';
      }
      if (mounted) {
        SnackbarManager.showError(context, message: message);
      }
    } catch (e) {
      if (mounted) {
        SnackbarManager.showError(
          context,
          message: 'Unexpected error: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingInfo = false;
        });
      }
    }
  }

  List<Widget> _buildScannedContent() {
    final List<Widget> widgets = [];
    if (_customerName != null) {
      widgets.add(
        Text(
          _customerName!,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      widgets.add(const SizedBox(height: 4));
    }
    widgets.add(
      Text(
        _scannedValue ?? '—',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xffd41818),
        foregroundColor: Colors.white,
        title: const Text('Scan QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: !_permissionChecked
            ? const Center(child: CircularProgressIndicator())
            : !_permissionGranted
                ? _buildPermissionDenied()
                : _buildScanner(),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Camera access is needed to scan QR codes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await openAppSettings();
              _requestCameraPermission();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open settings'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffd41818),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _requestCameraPermission,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Scanned value',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildScannedContent(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isScanSuccess && _scannedValue != null && !_isCheckingCode)
                  Row(
                    children: [
                      if (!_hasCheckedIn) ...[
                        Expanded(
                          child: FilledButton(
                            onPressed: _isUpdatingInfo
                                ? null
                                : () => _updateInfo(
                                      qrCode: _scannedValue!,
                                      checkedIn: true,
                                      meal: false,
                                    ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xffd41818),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isUpdatingInfo
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Text('Check In'),
                          ),
                        ),
                      ] else if (_hasCheckedIn && !_hasMeal) ...[
                        Expanded(
                          child: FilledButton(
                            onPressed: _isUpdatingInfo
                                ? null
                                : () => _updateInfo(
                                      qrCode: _scannedValue!,
                                      checkedIn: true,
                                      meal: true,
                                    ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xffd41818),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isUpdatingInfo
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Text('Meals'),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
