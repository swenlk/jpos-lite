import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class PrintService {
  /// Generate print bytes with business name and optional logo
  /// 
  /// [businessName] - The business name to print
  /// [content] - The rest of the receipt content (items, totals, etc.)
  /// [logoPath] - Optional path to the logo image file
  /// [paperSize] - Paper size for the printer (default: mm58)
  /// 
  /// Returns a list of bytes ready to be sent to the printer
  static Future<List<int>> generatePrintBytes({
    required String businessName,
    required String content,
    String? logoPath,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    try {
      // Load capability profile
      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      
      List<int> printBytes = [];
      
      // Initialize printer
      printBytes += generator.reset();
      
      // Try to load and print logo first if path is provided
      if (logoPath != null && logoPath.isNotEmpty) {
        try {
          final file = File(logoPath);
          if (await file.exists()) {
            final Uint8List imageBytes = await file.readAsBytes();
            img.Image? image = img.decodeImage(imageBytes);
            
            if (image != null) {
              // Optimize image for thermal printer
              // Resize to match printer width (58mm = ~384px at 203 DPI, 80mm = ~576px)
              final maxWidth = paperSize == PaperSize.mm80 ? 576 : 384;
              
              // Only resize if image is larger than printer width
              if (image.width > maxWidth) {
                final aspectRatio = image.height / image.width;
                final newHeight = (maxWidth * aspectRatio).round();
                image = img.copyResize(
                  image,
                  width: maxWidth,
                  height: newHeight,
                  interpolation: img.Interpolation.linear,
                );
                print('🔄 Image resized to ${image.width}x${image.height}');
              }
              
              // Convert to grayscale to reduce data size
              image = img.grayscale(image);
              
              // Print logo first (no extra space after)
              printBytes += generator.image(image);
              print('✅ Logo optimized and added to print data (${image.width}x${image.height})');
            } else {
              print('⚠️ Failed to decode image from file: $logoPath');
            }
          } else {
            print('⚠️ Logo file not found: $logoPath');
          }
        } catch (e) {
          print('⚠️ Error loading logo: $e');
          // Continue without logo if loading fails
        }
      }
      
      // Center align business name below the logo
      printBytes += generator.text(
        businessName,
        styles: const PosStyles(align: PosAlign.center),
      );
      
      // Add the rest of the content
      // Split content into lines and process
      // Remove leading and trailing empty lines from content
      final contentLines = content.split('\n');
      // Remove leading empty lines
      int startIndex = 0;
      while (startIndex < contentLines.length && contentLines[startIndex].trim().isEmpty) {
        startIndex++;
      }
      // Remove trailing empty lines
      int endIndex = contentLines.length;
      while (endIndex > startIndex && contentLines[endIndex - 1].trim().isEmpty) {
        endIndex--;
      }
      final lines = contentLines.sublist(startIndex, endIndex);
      bool isThankYouSection = false;
      
      for (final line in lines) {
        if (line.trim().isEmpty) {
          printBytes += generator.feed(1);
        } else {
          // Check if line should be centered (e.g., "Thank you" section)
          final shouldCenter = line.contains('Thank you') || line.contains('Software by');
          
          if (shouldCenter && !isThankYouSection) {
            // Start centering for thank you section
            isThankYouSection = true;
            printBytes += generator.text(
              line,
              styles: const PosStyles(align: PosAlign.center),
            );
          } else if (shouldCenter && isThankYouSection) {
            // Continue centering for software by line
            printBytes += generator.text(
              line,
              styles: const PosStyles(align: PosAlign.center),
            );
            // Reset alignment after software by
            isThankYouSection = false;
          } else {
            // Regular text (left-aligned by default)
            printBytes += generator.text(line);
          }
        }
      }
      
      // Add line feeds and cut
      // printBytes += generator.feed(2);
      printBytes += generator.cut();
      
      return printBytes;
    } catch (e) {
      print('❌ Error generating print bytes: $e');
      rethrow;
    }
  }
  
  /// Generate print bytes from asset image
  /// 
  /// [assetPath] - Path to the image asset (e.g., 'assets/images/logo.png')
  /// [businessName] - The business name to print above the logo
  /// [paperSize] - Paper size for the printer (default: mm58)
  /// 
  /// Returns a list of bytes ready to be sent to the printer
  static Future<List<int>> generatePrintBytesFromAsset({
    required String assetPath,
    String? businessName,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    try {
      // Load the image from assets
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) {
        throw Exception('Failed to decode image from asset: $assetPath');
      }
      
      // Optimize image for thermal printer
      // Resize to match printer width (58mm = ~384px at 203 DPI, 80mm = ~576px)
      final maxWidth = paperSize == PaperSize.mm80 ? 576 : 384;
      
      // Only resize if image is larger than printer width
      if (image.width > maxWidth) {
        final aspectRatio = image.height / image.width;
        final newHeight = (maxWidth * aspectRatio).round();
        image = img.copyResize(
          image,
          width: maxWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
        print('🔄 Image resized to ${image.width}x${image.height}');
      }
      
      // Convert to grayscale to reduce data size
      image = img.grayscale(image);
      
      // Initialize the ESC/POS Generator
      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      
      List<int> printBytes = [];
      
      // Initialize printer
      printBytes += generator.reset();
      
      // Print image first (no extra space after)
      printBytes += generator.image(image);
      
      // Add business name below the image if provided
      if (businessName != null && businessName.isNotEmpty) {
        printBytes += generator.text(
          businessName,
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      
      // Add line feeds and cut
      // printBytes += generator.feed(2);
      printBytes += generator.cut();
      
      return printBytes;
    } catch (e) {
      print('❌ Error generating print bytes from asset: $e');
      rethrow;
    }
  }
  
  /// Get cached logo path from SharedPreferences
  static Future<String?> getCachedLogoPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('cachedImagePath');
    } catch (e) {
      print('❌ Error getting cached logo path: $e');
      return null;
    }
  }
  
  /// Generate print bytes with business name and logo (if available)
  /// This is a convenience method that automatically loads the cached logo
  static Future<List<int>> generatePrintBytesWithLogo({
    required String businessName,
    required String content,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final logoPath = await getCachedLogoPath();
    return generatePrintBytes(
      businessName: businessName,
      content: content,
      logoPath: logoPath,
      paperSize: paperSize,
    );
  }
}

