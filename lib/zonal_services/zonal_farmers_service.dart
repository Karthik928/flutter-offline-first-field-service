import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalFarmersResponse {
  final bool success;
  final List<dynamic>? data;
  final String? error;

  ZonalFarmersResponse({required this.success, this.data, this.error});
}

class ZonalApproveResponse {
  final bool success;
  final String? error;

  ZonalApproveResponse({required this.success, this.error});
}

class ZonalFarmersService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalFarmers;
  static const String approveEndpoint = AppConfig.zonalFarmersApprove;

  Future<ZonalFarmersResponse> fetchFarmers() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalFarmersResponse(success: false, error: 'UNAUTHORIZED');
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
        return ZonalFarmersResponse(
          success: true,
          data: (jsonData['data'] as List?) ?? [],
        );
      }

      if (response.statusCode == 401) {
        return ZonalFarmersResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalFarmersResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalFarmersResponse(success: false, error: e.toString());
    }
  }

  /// PUT /api/zonal-data/farmers/{farmer_id}/status
  Future<ZonalApproveResponse> approveFarmer(String farmerId) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalApproveResponse(success: false, error: 'UNAUTHORIZED');
      }

      final cleanFarmerId = farmerId.trim();
      
      // Validate that farmerId is not empty
      if (cleanFarmerId.isEmpty) {
        return ZonalApproveResponse(success: false, error: 'FARMER_ID_MISSING');
      }

      final url = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '${approveEndpoint.replaceAll('{farmer_id}', cleanFarmerId)}',
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

      if (response.statusCode == 401) {
        return ZonalApproveResponse(success: false, error: 'UNAUTHORIZED');
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
