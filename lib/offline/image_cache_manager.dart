import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ProductImageCache {
  // Configured to keep images for 30 days and up to 200 files.
  static final CacheManager instance = CacheManager(
    Config(
      'productImageCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 200,
      // Optionally tweak repo/fileService if you need advanced behaviour
    ),
  );
}
