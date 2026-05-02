import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalCustomer {
  final String id;
  final String name;
  final String type;
  final String phone;
  final String? address;
  final String? shopName;
  final double? latitude;
  final double? longitude;
  final String? employeeName; // ✅ ADD

  ZonalCustomer({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    this.address,
    this.shopName,
    this.latitude,
    this.longitude,
    this.employeeName, // ✅ ADD
  });

  factory ZonalCustomer.fromJson(Map<String, dynamic> json) {
    final location = json['location'];

    double? lat;
    double? lng;
    if (location is Map<String, dynamic>) {
      lat = (location['latitude'] as num?)?.toDouble();
      lng = (location['longitude'] as num?)?.toDouble();
    }

    return ZonalCustomer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString(),
      shopName: json['shopName']?.toString(),
      latitude: lat,
      longitude: lng,
      employeeName: json['employeeName']?.toString(), // ✅ ADD
    );
  }

  String get displayName {
    final shop = shopName?.trim();
    if (shop != null && shop.isNotEmpty) {
      return '$name ($shop)';
    }
    return name;
  }
}

class ZonalCustomerResponse {
  final bool success;
  final List<ZonalCustomer> customers;
  final String? error;

  ZonalCustomerResponse({
    required this.success,
    required this.customers,
    this.error,
  });
}

class ZonalCustomerService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalDealersandFarmers;

  Future<ZonalCustomerResponse> fetchCustomers() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalCustomerResponse(
          success: false,
          customers: [],
          error: 'UNAUTHORIZED',
        );
      }

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final rawBody = utf8.decode(response.bodyBytes);

      debugPrint('CUSTOMERS STATUS => ${response.statusCode}');
      debugPrint('CUSTOMERS RESP   => $rawBody');

      if (response.statusCode == 401) {
        return ZonalCustomerResponse(
          success: false,
          customers: [],
          error: 'UNAUTHORIZED',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ZonalCustomerResponse(
          success: false,
          customers: [],
          error: 'Error ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic> && decoded['success'] == true) {
        final data = decoded['data'];
        if (data is List) {
          final customers = data
              .whereType<Map<String, dynamic>>()
              .map(ZonalCustomer.fromJson)
              .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
              .toList();

          return ZonalCustomerResponse(success: true, customers: customers);
        }
      }

      return ZonalCustomerResponse(
        success: false,
        customers: [],
        error: 'Invalid response',
      );
    } catch (e) {
      return ZonalCustomerResponse(
        success: false,
        customers: [],
        error: e.toString(),
      );
    }
  }
}
