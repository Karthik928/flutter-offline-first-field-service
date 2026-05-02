// lib/provider/api_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/api_client.dart';

// Expose the existing global apiClient (initialized in main()) as a provider.
// This lets later providers consume ApiClient via ref.read(apiClientProvider).
final apiClientProvider = Provider<ApiClient>((ref) {
  // 'apiClient' is initialized in main() before runApp().
  return apiClient;
});
