import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RESPONSE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

class ZonalTicketResponse {
  final bool success;
  final List<TicketData> tickets;
  final String? error;

  ZonalTicketResponse({
    required this.success,
    required this.tickets,
    this.error,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// POND SUB-MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class PhysicalReading {
  final int stockingPL;
  final int doc;
  final double feedIntakePerDay;
  final int count;
  final double avgWeight;
  final DateTime recordedAt;

  const PhysicalReading({
    required this.stockingPL,
    required this.doc,
    required this.feedIntakePerDay,
    required this.count,
    required this.avgWeight,
    required this.recordedAt,
  });

  factory PhysicalReading.fromJson(Map<String, dynamic> j) => PhysicalReading(
    stockingPL: (j['stockingPL'] as num? ?? 0).toInt(),
    doc: (j['doc'] as num? ?? 0).toInt(),
    feedIntakePerDay: (j['feedIntakePerDay'] as num? ?? 0).toDouble(),
    count: (j['count'] as num? ?? 0).toInt(),
    avgWeight: (j['avgWeight'] as num? ?? 0).toDouble(),
    recordedAt:
        DateTime.tryParse(j['recordedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class ChemicalReading {
  final double salinity;
  final double ph;
  final double alkalinity;
  final double ammonia;
  final double nitrite;
  final double dissolvedOxygen;
  final DateTime recordedAt;

  const ChemicalReading({
    required this.salinity,
    required this.ph,
    required this.alkalinity,
    required this.ammonia,
    required this.nitrite,
    required this.dissolvedOxygen,
    required this.recordedAt,
  });

  factory ChemicalReading.fromJson(Map<String, dynamic> j) => ChemicalReading(
    salinity: (j['salinity'] as num? ?? 0).toDouble(),
    ph: (j['ph'] as num? ?? 0).toDouble(),
    alkalinity: (j['alkalinity'] as num? ?? 0).toDouble(),
    ammonia: (j['ammonia'] as num? ?? 0).toDouble(),
    nitrite: (j['nitrite'] as num? ?? 0).toDouble(),
    dissolvedOxygen: (j['dissolvedOxygen'] as num? ?? 0).toDouble(),
    recordedAt:
        DateTime.tryParse(j['recordedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class DiseaseReading {
  final double vibrios;
  final DateTime recordedAt;

  const DiseaseReading({required this.vibrios, required this.recordedAt});

  factory DiseaseReading.fromJson(Map<String, dynamic> j) => DiseaseReading(
    vibrios: (j['vibrios'] as num? ?? 0).toDouble(),
    recordedAt:
        DateTime.tryParse(j['recordedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class PondData {
  final String pondName;
  final double culturedArea;
  final String culturedSpecies;
  final List<PhysicalReading> physicalReadings;
  final List<ChemicalReading> chemicalReadings;
  final List<DiseaseReading> diseaseReadings;

  const PondData({
    required this.pondName,
    required this.culturedArea,
    required this.culturedSpecies,
    required this.physicalReadings,
    required this.chemicalReadings,
    required this.diseaseReadings,
  });

  factory PondData.fromJson(Map<String, dynamic> j) => PondData(
    pondName: j['pondName']?.toString() ?? '',
    culturedArea: (j['culturedArea'] as num? ?? 0).toDouble(),
    culturedSpecies: j['culturedSpecies']?.toString() ?? '',
    physicalReadings: (j['physicalReadings'] as List? ?? [])
        .map((e) => PhysicalReading.fromJson(e as Map<String, dynamic>))
        .toList(),
    chemicalReadings: (j['chemicalReadings'] as List? ?? [])
        .map((e) => ChemicalReading.fromJson(e as Map<String, dynamic>))
        .toList(),
    diseaseReadings: (j['diseaseReadings'] as List? ?? [])
        .map((e) => DiseaseReading.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TICKET DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class TicketData {
  final String id;
  final String ticketId;
  final String type;
  final String customer;
  final String mobileNumber;
  final String location;
  final String remarks;
  final String status;
  final DateTime date;
  final String? response;
  // Farmer-only fields
  final List<String> images;
  final List<PondData> ponds;

  const TicketData({
    required this.id,
    required this.ticketId,
    required this.type,
    required this.customer,
    required this.mobileNumber,
    required this.location,
    required this.remarks,
    required this.status,
    required this.date,
    this.response,
    this.images = const [],
    this.ponds = const [],
  });

  bool get isFarmer => type.toLowerCase() == 'farmer';

  factory TicketData.fromApi(Map<String, dynamic> json) => TicketData(
    id: json['id']?.toString() ?? '',
    ticketId: json['ticketId']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    customer: json['customer']?.toString() ?? '',
    mobileNumber: json['mobileNumber']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    remarks: json['remarks']?.toString() ?? '',
    status: json['status']?.toString() ?? 'Pending',
    response: json['solution']?.toString(),
    date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
    images: (json['images'] as List? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList(),
    ponds: (json['ponds'] as List? ?? [])
        .map((e) => PondData.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  bool get isNew {
    final s = status.toLowerCase();
    return s != 'resolved' && s != 'solved';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class ZonalTicketService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalAllTickets;

  Future<ZonalTicketResponse> fetchTickets() async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        return ZonalTicketResponse(
          success: false,
          tickets: [],
          error: 'UNAUTHORIZED',
        );
      }

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      final rawBody = utf8.decode(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
        final list = (decoded['data'] as List? ?? [])
            .map((e) => TicketData.fromApi(e as Map<String, dynamic>))
            .toList();
        return ZonalTicketResponse(success: true, tickets: list);
      }

      if (response.statusCode == 401) {
        return ZonalTicketResponse(
          success: false,
          tickets: [],
          error: 'UNAUTHORIZED',
        );
      }

      String errorMsg = 'Error ${response.statusCode}';
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          errorMsg = decoded['message']?.toString() ?? errorMsg;
        }
      } catch (_) {}

      return ZonalTicketResponse(success: false, tickets: [], error: errorMsg);
    } catch (e) {
      return ZonalTicketResponse(
        success: false,
        tickets: [],
        error: e.toString(),
      );
    }
  }

  Future<bool> updateTicket({
    required String id,
    required String type,
    required String status,
    required String solution,
  }) async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) return false;

      final url = Uri.parse('$baseUrl/api/zonal-data/tickets/$id?type=$type');
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'status': status, 'solution': solution}),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
