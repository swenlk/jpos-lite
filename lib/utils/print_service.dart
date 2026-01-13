import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class PrintService {
  /// Convert grayscale image to pure black and white using improved threshold
  /// Uses adaptive thresholding and better contrast to preserve all image details
  static img.Image _applyThreshold(img.Image image, {int threshold = 128}) {
    final result = img.Image(width: image.width, height: image.height);
    
    // First pass: calculate statistics for adaptive thresholding
    int totalBrightness = 0;
    int minBrightness = 255;
    int maxBrightness = 0;
    int pixelCount = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final grayValue = pixel.r.toInt();
        totalBrightness += grayValue;
        if (grayValue < minBrightness) minBrightness = grayValue;
        if (grayValue > maxBrightness) maxBrightness = grayValue;
        pixelCount++;
      }
    }
    
    // Calculate adaptive threshold based on image statistics
    final avgBrightness = pixelCount > 0 ? totalBrightness ~/ pixelCount : 128;
    final brightnessRange = maxBrightness - minBrightness;
    
    // Use Otsu's method inspired threshold: balance between preserving details
    // Lower threshold for dark images, higher for light images
    // But also consider the range - if range is small, use middle value
    int adaptiveThreshold;
    if (brightnessRange < 50) {
      // Low contrast image - use average
      adaptiveThreshold = avgBrightness;
    } else {
      // Use weighted average: 40% base threshold, 60% image average
      adaptiveThreshold = ((threshold * 0.4) + (avgBrightness * 0.6)).round();
    }
    
    // Clamp threshold to reasonable range, but allow lower values to capture more details
    // Lower minimum to capture very light colors like light green
    adaptiveThreshold = adaptiveThreshold.clamp(85, 160);
    
    // Second pass: apply threshold with better handling of edge cases
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final grayValue = pixel.r.toInt();
        
        // Use a much more aggressive lower threshold to capture light colors
        // Light green and other light colors need lower threshold to be visible
        // Reduce by 20-25 to ensure light colors are captured
        final effectiveThreshold = adaptiveThreshold - 20; // Very aggressive bias toward black
        
        // Special handling for light colors (200-255 range)
        // These are often light greens, yellows, etc. that should still print
        int value;
        if (grayValue < effectiveThreshold) {
          // Definitely black
          value = 0;
        } else if (grayValue >= 240) {
          // Very light (almost white) - keep as white
          value = 255;
        } else {
          // Medium-light colors (like light green) - make them black to ensure visibility
          // Use a wider range to capture light colors
          value = grayValue < (effectiveThreshold + 30) ? 0 : 255;
        }
        
        result.setPixel(x, y, img.ColorRgb8(value, value, value));
      }
    }
    
    return result;
  }
  
  /// Remove alpha channel by copying to RGB format
  static img.Image _removeAlphaChannel(img.Image image) {
    // Create a new RGB image (no alpha channel)
    final rgbImage = img.Image(width: image.width, height: image.height);
    
    // Copy pixels, ignoring alpha channel
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Convert num to int explicitly
        rgbImage.setPixel(x, y, img.ColorRgb8(
          pixel.r.toInt(), 
          pixel.g.toInt(), 
          pixel.b.toInt()
        ));
      }
    }
    
    return rgbImage;
  }
  /// Generate print bytes with business name and optional logo
  /// 
  /// [businessName] - The business name to print
  /// [content] - The rest of the receipt content (items, totals, etc.)
  /// [logoPath] - Optional path to the logo image file
  /// [contactNumber] - Optional contact number to display below business name
  /// [address] - Optional address to display below business name
  /// [paperSize] - Paper size for the printer (default: mm58)
  /// 
  /// Returns a list of bytes ready to be sent to the printer
  static Future<List<int>> generatePrintBytes({
    required String businessName,
    required String content,
    String? logoPath,
    String? contactNumber,
    String? address,
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
              
              // Remove alpha channel if present (convert RGBA to RGB)
              if (image.hasAlpha) {
                image = _removeAlphaChannel(image);
                print('🔄 Removed alpha channel');
              }
              
              // Enhance contrast and brightness before grayscale conversion
              // Higher contrast helps ensure all parts are visible, including light colors
              // Slight brightness reduction helps light colors become more visible
              image = img.adjustColor(image, contrast: 1.4, brightness: 0.95);
              
              // Convert to grayscale
              image = img.grayscale(image);
              
              // Apply improved threshold to convert to pure black and white (binary)
              // This ensures all parts print correctly on thermal printers
              // Uses adaptive thresholding based on image brightness
              image = _applyThreshold(image, threshold: 128);
              
              print('✅ Logo optimized and converted to black/white (${image.width}x${image.height})');
              
              // Print logo first (no extra space after)
              printBytes += generator.image(image);
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

      // Add address below business name if provided
      if (address != null && address.isNotEmpty) {
        printBytes += generator.text(
          address,
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      
      // Add contact number below business name if provided
      if (contactNumber != null && contactNumber.isNotEmpty) {
        printBytes += generator.text(
          'Phone: $contactNumber',
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      
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
      
      // Remove alpha channel if present (convert RGBA to RGB)
      if (image.hasAlpha) {
        image = _removeAlphaChannel(image);
        print('🔄 Removed alpha channel');
      }
      
      // Enhance contrast and brightness before grayscale conversion
      // Higher contrast helps ensure all parts are visible, including light colors
      // Slight brightness reduction helps light colors become more visible
      image = img.adjustColor(image, contrast: 1.4, brightness: 0.95);
      
      // Convert to grayscale
      image = img.grayscale(image);
      
      // Apply improved threshold to convert to pure black and white (binary)
      // This ensures all parts print correctly on thermal printers
      // Uses adaptive thresholding based on image brightness
      image = _applyThreshold(image, threshold: 128);
      
      print('✅ Image optimized and converted to black/white (${image.width}x${image.height})');
      
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
    String? contactNumber,
    String? address,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final logoPath = await getCachedLogoPath();
    return generatePrintBytes(
      businessName: businessName,
      content: content,
      logoPath: logoPath,
      contactNumber: contactNumber,
      address: address,
      paperSize: paperSize,
    );
  }
}

