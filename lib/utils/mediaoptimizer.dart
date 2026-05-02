import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class MediaOptimizer {
  static const int maxImageWidth = 720;
  static const int maxImageHeight = 720;
  static const int maxImageQuality = 70;
  static const int maxVideoSizeMB = 50;
  static const int maxImageSizeMB = 5;

  /// Compress and optimize image file
  static Future<File?> compressImage(File imageFile) async {
    try {
      // Get file size in MB
      final fileSizeMB = await imageFile.length() / (1024 * 1024);

      // If file is already small enough, return original
      // if (fileSizeMB < 2) {
      //   return imageFile;
      // }

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final compressedPath = '${tempDir.path}/compressed_$timestamp.jpg';

      // Compress image
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        compressedPath,
        quality: maxImageQuality,
        minWidth: 300,
        minHeight: 300,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (compressedFile != null) {
        final compressedFileObj = File(compressedFile.path);
        final compressedSizeMB =
            await compressedFileObj.length() / (1024 * 1024);

        // If compression didn't help much, return original
        if (compressedSizeMB > fileSizeMB * 0.8) {
          await compressedFileObj.delete();
          return imageFile;
        }

        return compressedFileObj;
      }

      return imageFile;
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return imageFile;
    }
  }

  /// Resize image to optimal dimensions
  static Future<File?> resizeImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return imageFile;

      // Calculate new dimensions while maintaining aspect ratio
      int newWidth = image.width;
      int newHeight = image.height;

      if (image.width > maxImageWidth || image.height > maxImageHeight) {
        final aspectRatio = image.width / image.height;

        if (image.width > image.height) {
          newWidth = maxImageWidth;
          newHeight = (maxImageWidth / aspectRatio).round();
        } else {
          newHeight = maxImageHeight;
          newWidth = (maxImageHeight * aspectRatio).round();
        }
      }

      // Only resize if needed
      if (newWidth != image.width || newHeight != image.height) {
        final resizedImage = img.copyResize(
          image,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.average,
        );

        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final resizedPath = '${tempDir.path}/resized_$timestamp.jpg';
        final resizedFile = File(resizedPath);

        await resizedFile.writeAsBytes(
          img.encodeJpg(resizedImage, quality: maxImageQuality),
        );
        return resizedFile;
      }

      return imageFile;
    } catch (e) {
      debugPrint('Error resizing image: $e');
      return imageFile;
    }
  }

  /// Get optimized image file (compressed and resized)
  static Future<File?> getOptimizedImage(File imageFile) async {
    try {
      // First resize the image
      final resizedFile = await resizeImage(imageFile);
      if (resizedFile == null) return imageFile;

      // Then compress the resized image
      final compressedFile = await compressImage(resizedFile);

      // Clean up intermediate file if it's different from original
      if (resizedFile.path != imageFile.path &&
          resizedFile.path != compressedFile?.path) {
        try {
          await resizedFile.delete();
        } catch (e) {
          debugPrint('Error deleting intermediate file: $e');
        }
      }

      return compressedFile ?? imageFile;
    } catch (e) {
      debugPrint('Error optimizing image: $e');
      return imageFile;
    }
  }

  /// Check if file size is acceptable
  static Future<bool> isFileSizeAcceptable(
    File file, {
    bool isVideo = false,
  }) async {
    try {
      final fileSizeMB = await file.length() / (1024 * 1024);
      final maxSize = isVideo ? maxVideoSizeMB : maxImageSizeMB;
      return fileSizeMB <= maxSize;
    } catch (e) {
      debugPrint('Error checking file size: $e');
      return false;
    }
  }

  /// Get file size in MB
  static Future<double> getFileSizeMB(File file) async {
    try {
      return await file.length() / (1024 * 1024);
    } catch (e) {
      debugPrint('Error getting file size: $e');
      return 0.0;
    }
  }

  /// Format file size for display
  static String formatFileSize(double sizeMB) {
    if (sizeMB < 1) {
      return '${(sizeMB * 1024).toStringAsFixed(0)} KB';
    } else {
      return '${sizeMB.toStringAsFixed(1)} MB';
    }
  }

  /// Create thumbnail for video
  static Future<File?> createVideoThumbnail(File videoFile) async {
    try {
      // This would require video_thumbnail package for actual implementation
      // For now, return null to use default video player thumbnail
      return null;
    } catch (e) {
      debugPrint('Error creating video thumbnail: $e');
      return null;
    }
  }

  /// Clean up temporary files
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();

      for (final file in files) {
        if (file is File &&
            (file.path.contains('compressed_') ||
                file.path.contains('resized_') ||
                file.path.contains('thumbnail_'))) {
          try {
            await file.delete();
          } catch (e) {
            debugPrint('Error deleting temp file: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
    }
  }
}
