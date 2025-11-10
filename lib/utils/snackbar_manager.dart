import 'package:flutter/material.dart';

class SnackbarManager {
  static void showSuccess(
    BuildContext context, {
    required String message,
  }) {
    _showSnackBar(
      context,
      message: message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle_outline,
    );
  }

  static void showError(
    BuildContext context, {
    required String message,
  }) {
    _showSnackBar(
      context,
      message: message,
      backgroundColor: const Color(0xffd41818),
      icon: Icons.error_outline,
    );
  }

  static void showWarning(
    BuildContext context, {
    required String message,
  }) {
    _showSnackBar(
      context,
      message: message,
      backgroundColor: Colors.orange,
      icon: Icons.warning_outlined,
    );
  }

  static void showInfo(
    BuildContext context, {
    required String message,
  }) {
    _showSnackBar(
      context,
      message: message,
      backgroundColor: Colors.blue,
      icon: Icons.info_outline,
    );
  }

  static void _showSnackBar(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Clear any existing snackbar first
    ScaffoldMessenger.of(context).clearSnackBars();
    
    final snackBar = SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12.0),
          ],
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16.0),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      margin: const EdgeInsets.all(16.0),
      duration: duration,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
