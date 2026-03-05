import 'dart:ui' as ui;

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
  String? _checkedInTime;
  String? _mealConfirmedTime;
  bool _isCheckingCode = false;
  bool _isUpdatingInfo = false;
  bool _isScannerPaused = false;
  String? _lastRequestedCode;
  bool _hasCheckedIn = false;
  bool _hasMeal = false;
  bool _isScanSuccess = false;
  bool _hasExistingInfoEntry = false;
  List<dynamic>? _currentInfoList;
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
      _checkedInTime = null;
      _mealConfirmedTime = null;
      _hasCheckedIn = false;
      _hasMeal = false;
      _isScanSuccess = false;
      _hasExistingInfoEntry = false;
      _currentInfoList = null;
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
        bool hasExistingEntry = false;
        String? checkedInTime;
        String? mealConfirmedTime;

        if (info is List) {
          for (final entry in info) {
            if (entry is Map && entry.containsKey(qrCode)) {
              final qrObject = entry[qrCode];
              if (qrObject is Map) {
                checkedIn = qrObject['checkedIn'] == true;
                meal = qrObject['meal'] == true;
                hasExistingEntry = true;
                final dynamic timeVal = qrObject['checkedInTime'];
                if (timeVal != null) {
                  checkedInTime = timeVal.toString();
                }
                final dynamic mealTimeVal = qrObject['mealConfirmedTime'];
                if (mealTimeVal != null) {
                  mealConfirmedTime = mealTimeVal.toString();
                }
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
          _hasExistingInfoEntry = hasExistingEntry;
          _checkedInTime = checkedInTime;
          _mealConfirmedTime = mealConfirmedTime;
          _currentInfoList = info is List ? List<dynamic>.from(info) : null;
        });

        // Pause the camera preview after a successful scan.
        if (!_isScannerPaused) {
          await _controller.stop();
          if (mounted) {
            setState(() {
              _isScannerPaused = true;
            });
          }
        }
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
        final detail = e.message ?? e.error?.toString() ?? '';
        print('Network error: $detail');
        message = detail.isNotEmpty
            ? 'Network error: $detail'
            : 'Network error. Please check your connection.';
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
    required bool isNewEntry,
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

      // Base QR object for this code.
      // For new entries (add_info), also include the checked-in time,
      // using Asia/Colombo time (UTC+5:30) and serialize as ISO8601.
      DateTime? checkedInTime;
      DateTime? mealConfirmedTime;
      if (isNewEntry) {
        final nowUtc = DateTime.now().toUtc();
        checkedInTime = nowUtc.add(const Duration(hours: 5, minutes: 30));
        // checkedInTime = DateTime.now();
      }

      final baseQrObject = <String, dynamic>{
        'checkedIn': checkedIn,
        'meal': meal,
        if (checkedInTime != null)
          'checkedInTime': checkedInTime.toIso8601String(),
      };

      Map<String, dynamic> singleValue = {};
      List<dynamic> valueList = [];

      if (isNewEntry) {
        // For add_info, send only the new QR object
        singleValue = {
          qrCode: baseQrObject,
        };
      } else {
        // For update_info, update only this QR entry inside the full info[] array
        final List<dynamic> sourceList =
            _currentInfoList is List ? List<dynamic>.from(_currentInfoList!) : [];

        // When confirming meal, set mealConfirmedTime (Asia/Colombo) like checkedInTime.
        if (meal) {
          final nowUtc = DateTime.now().toUtc();
          mealConfirmedTime = nowUtc.add(const Duration(hours: 5, minutes: 30));
        }

        bool updated = false;
        valueList = sourceList.map((entry) {
          if (entry is Map && entry.containsKey(qrCode)) {
            final existingObj = entry[qrCode];
            final Map<String, dynamic> updatedObj =
                existingObj is Map<String, dynamic>
                    ? Map<String, dynamic>.from(existingObj)
                    : <String, dynamic>{};
            updatedObj['checkedIn'] = checkedIn;
            updatedObj['meal'] = meal;
            if (mealConfirmedTime != null) {
              updatedObj['mealConfirmedTime'] =
                  mealConfirmedTime.toIso8601String();
            }
            updated = true;
            return {qrCode: updatedObj};
          }
          return entry;
        }).toList();

        // If for some reason no entry existed, append a new one
        if (!updated) {
          valueList.add({
            qrCode: baseQrObject,
          });
        }
      }

      final requestBody = isNewEntry
          ? {
              'activeToken': activeToken,
              'customerId': _customerId,
              'value': singleValue,
            }
          : {
              'activeToken': activeToken,
              'customerId': _customerId,
              'value': valueList,
            };

      final String endpoint =
          isNewEntry ? ApiEndpoints.addInfo : ApiEndpoints.updateInfo;

      final response = await dio.post(
        AppConfigs.baseUrl + endpoint,
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
            if (meal && mealConfirmedTime != null) {
              _mealConfirmedTime = mealConfirmedTime.toIso8601String();
            }
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
        final detail = e.message ?? e.error?.toString() ?? '';
        print('Network error: $detail');
        message = detail.isNotEmpty
            ? 'Network error: $detail'
            : 'Network error. Please check your connection.';
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

  /// Formats a date-time string for display as yyyy:MM:dd hh:mm a (AM/PM).
  String _formatCheckedInTime(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final amPm = dt.hour < 12 ? 'AM' : 'PM';
      return '${dt.year}:${dt.month.toString().padLeft(2, '0')}:${dt.day.toString().padLeft(2, '0')} '
          '${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return raw;
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
        _scannedValue ?? '',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    if (_hasCheckedIn && _checkedInTime != null) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
            const SizedBox(width: 6),
            Text(
              'Checked In: ${_formatCheckedInTime(_checkedInTime!)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    if (_mealConfirmedTime != null) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
            const SizedBox(width: 6),
            Text(
              'Meal Dispatched: ${_formatCheckedInTime(_mealConfirmedTime!)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return widgets;
  }

  Future<void> _onRescan() async {
    setState(() {
      _scannedValue = null;
      _customerName = null;
      _customerId = null;
      _checkedInTime = null;
      _mealConfirmedTime = null;
      _hasCheckedIn = false;
      _hasMeal = false;
      _isScanSuccess = false;
      _hasExistingInfoEntry = false;
      _currentInfoList = null;
      _lastRequestedCode = null;
    });

    if (_isScannerPaused) {
      await _controller.start();
      if (mounted) {
        setState(() {
          _isScannerPaused = false;
        });
      }
    }
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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: _buildScanner(),
                        ),
                      );
                    },
                  ),
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
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              // Prevent the camera preview from growing too tall,
              // especially in landscape orientation.
              maxHeight: 400,
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                    if (_isScanSuccess)
                      Positioned.fill(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: Container(
                              color: Colors.black.withOpacity(0.4),
                              child: Center(
                                child: FilledButton.icon(
                                  onPressed: _onRescan,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xffd41818),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text(
                                    'Rescan',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          // color: Colors.grey[100],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Text(
              //   'Customer Details',
              //   style: TextStyle(
              //     fontSize: 14,
              //     fontWeight: FontWeight.w600,
              //     color: Colors.grey[700],
              //   ),
              // ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildScannedContent(),
                ),
              ),
              const SizedBox(height: 16),
              if (_isScanSuccess && _scannedValue != null && !_isCheckingCode)
                Builder(
                  builder: (context) {
                    Widget? slider;

                    // Case 1: No existing info entry and not yet checked in → interactive Check In slider.
                    if (!_hasCheckedIn) {
                      slider = _SlideToConfirm(
                        label: 'Check In',
                        isCompleted: false,
                        isLoading: _isUpdatingInfo,
                        onConfirm: _isUpdatingInfo
                            ? null
                            : () => _updateInfo(
                                  qrCode: _scannedValue!,
                                  checkedIn: true,
                                  meal: false,
                                  isNewEntry: !_hasExistingInfoEntry,
                                ),
                      );
                    }
                    // Case 2: Just completed Check In for a QR that had no prior entry.
                    // Show Check In slider in completed state; do NOT show Confirm Meals yet.
                    else if (_hasCheckedIn && !_hasMeal && !_hasExistingInfoEntry) {
                      slider = const _SlideToConfirm(
                        label: 'Check In',
                        isCompleted: true,
                        isLoading: false,
                        onConfirm: null,
                      );
                    }
                    // Case 3: QR already had a Check In entry, but meal not taken yet → interactive Confirm Meals.
                    else if (_hasCheckedIn && !_hasMeal && _hasExistingInfoEntry) {
                      slider = _SlideToConfirm(
                        label: 'Confirm Meals',
                        isCompleted: false,
                        isLoading: _isUpdatingInfo,
                        onConfirm: _isUpdatingInfo
                            ? null
                            : () => _updateInfo(
                                  qrCode: _scannedValue!,
                                  checkedIn: true,
                                  meal: true,
                                  isNewEntry: false,
                                ),
                      );
                    }
                    // Case 4: Both Check In and Meals completed → do not show any slider.

                    if (slider == null) return const SizedBox.shrink();

                    return Row(
                      children: [
                        Expanded(child: slider),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slide-from-left-to-right control: user must complete the slide to trigger the action.
class _SlideToConfirm extends StatefulWidget {
  const _SlideToConfirm({
    required this.label,
    required this.onConfirm,
    required this.isLoading,
    required this.isCompleted,
  });

  final String label;
  final VoidCallback? onConfirm;
  final bool isLoading;
  final bool isCompleted;

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm> {
  double _dragOffset = 0;

  static const double _thumbSize = 48;
  static const double _trackHeight = 52;
  static const double _padding = 4;
  static const Color _themeColor = Color(0xffd41818);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _thumbSize - _padding * 2;
        final triggerThreshold = maxDrag * 0.85;

        final bool disabled =
            widget.onConfirm == null || widget.isLoading || widget.isCompleted;

        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(_trackHeight / 2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: disabled ? Colors.grey[600] : Colors.grey[800],
                  ),
                ),
              ),
              Positioned(
                left: _padding +
                    (widget.isCompleted ? maxDrag : _dragOffset.clamp(0.0, maxDrag)),
                top: _padding,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (disabled) return;
                    setState(() {
                      _dragOffset =
                          (_dragOffset + d.delta.dx).clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (d) {
                    if (disabled) return;
                    if (_dragOffset >= triggerThreshold) {
                      widget.onConfirm!();
                      setState(() => _dragOffset = 0);
                    } else {
                      setState(() => _dragOffset = 0);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: widget.onConfirm == null || widget.isLoading
                          ? Colors.grey[500]
                          : _themeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: widget.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
