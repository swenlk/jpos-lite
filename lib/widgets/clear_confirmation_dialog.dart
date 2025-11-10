import 'package:flutter/material.dart';

class ClearConfirmationDialog extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback onCancel;

  const ClearConfirmationDialog({
    super.key,
    required this.onClear,
    required this.onCancel,
  });

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red circular icon with clear symbol
            Container(
              width: 60.0,
              height: 60.0,
              decoration: BoxDecoration(
                color: Colors.grey[600], // Red color matching app theme
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.clear_all,
                color: Colors.white,
                size: 30.0,
              ),
            ),
            
            const SizedBox(height: 20.0),
            
            // Title
            const Text(
              'Clear All',
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 16.0),
            
            // Message text
            const Text(
              'Are you sure?',
              style: TextStyle(
                fontSize: 16.0,
                color: Colors.grey,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 4.0),
            
            const Text(
              'This will clear all selected items and cart data.',
              style: TextStyle(
                fontSize: 16.0,
                color: Colors.grey,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24.0),
            
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
                      onPressed: onCancel,
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
                
                // Clear button
                Expanded(
                  child: Container(
                    height: 44.0,
                    decoration: BoxDecoration(
                      color:  Colors.grey[600],
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: TextButton(
                      onPressed: onClear,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: const Text(
                        'Clear',
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
    );
  }

  static void show({
    required BuildContext context,
    required VoidCallback onClear,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ClearConfirmationDialog(
          onClear: () {
            Navigator.of(context).pop();
            onClear();
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        );
      },
    );
  }
}

