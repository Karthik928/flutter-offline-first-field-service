import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' as client;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalEmployeesResponse {
  final bool success;
  final List<dynamic>? data;
  final String? error;

  ZonalEmployeesResponse({required this.success, this.data, this.error});
}

class ZonalEmployeesService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalEmployees;

  Future<ZonalEmployeesResponse> fetchEmployees() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalEmployeesResponse(success: false, error: 'UNAUTHORIZED');
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
        return ZonalEmployeesResponse(success: true, data: jsonData['data']);
      }

      if (response.statusCode == 401) {
        return ZonalEmployeesResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalEmployeesResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalEmployeesResponse(
        success: false,
        error: e.toString(), // important
      );
    }
  }

  Future<EmployeeProfileResult> fetchEmployeeById(String id) async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        return const EmployeeProfileResult(
          success: false,
          error: 'UNAUTHORIZED',
        );
      }

      final uri = AppConfig.u(AppConfig.employeeById.replaceFirst('{id}', id));

      final response = await client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        return const EmployeeProfileResult(
          success: false,
          error: 'UNAUTHORIZED',
        );
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        return EmployeeProfileResult(
          success: false,
          error: 'HTTP_${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      final employee = decoded['data']?['employee'] as Map<String, dynamic>?;

      if (employee == null) {
        return const EmployeeProfileResult(
          success: false,
          error: 'NO_EMPLOYEE_DATA',
        );
      }

      return EmployeeProfileResult(success: true, data: employee);
    } catch (e) {
      return EmployeeProfileResult(success: false, error: e.toString());
    }
  }
}

class EmployeeProfileResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  const EmployeeProfileResult({required this.success, this.data, this.error});
}
