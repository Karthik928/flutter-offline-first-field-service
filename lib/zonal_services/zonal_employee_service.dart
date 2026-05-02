import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class Employee {
  final String id;
  final String name;

  Employee({required this.id, required this.name});

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['_id'],
      name: "${json['firstName']} ${json['lastName']}",
    );
  }
}

class ZonalEmployeeService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalEmployeeList;

  Future<List<Employee>> fetchEmployees() async {
    try {
      final token = await SecureStorageService.getToken();

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final list = jsonData['data'] as List;

        return list.map((e) => Employee.fromJson(e)).toList();
      }

      return [];
    } catch (_) {
      return [];
    }
  }
}
