import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalDealersResponse {
  final bool success;
  final List<dynamic>? data;
  final String? error;

  ZonalDealersResponse({required this.success, this.data, this.error});
}

class ZonalApproveResponse {
  final bool success;
  final String? error;

  ZonalApproveResponse({required this.success, this.error});
}

class ZonalDealersService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalDealers;
  static const String approveEndpoint = AppConfig.zonalDealersApprove;

  Future<ZonalDealersResponse> fetchDealers() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalDealersResponse(success: false, error: 'UNAUTHORIZED');
      }

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ZonalDealersResponse(
          success: true,
          data: (jsonData['data'] as List?) ?? [],
        );
      }

      if (response.statusCode == 401) {
        return ZonalDealersResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalDealersResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalDealersResponse(success: false, error: e.toString());
    }
  }

  /// PUT /api/zonal-data/dealers/{dealer_id}/status
  Future<ZonalApproveResponse> approveDealer(String dealerId) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalApproveResponse(success: false, error: 'UNAUTHORIZED');
      }

      final cleanId = dealerId.trim();
      
      // Validate that dealerId is not empty
      if (cleanId.isEmpty) {
        return ZonalApproveResponse(success: false, error: 'DEALER_ID_MISSING');
      }

      final url = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '${approveEndpoint.replaceAll('{dealer_id}', cleanId)}',
      );

      final body = json.encode({'status': 'approved'});

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ZonalApproveResponse(success: true);
      }

      return ZonalApproveResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalApproveResponse(success: false, error: e.toString());
    }
  }
}
