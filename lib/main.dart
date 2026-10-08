import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WifiVoucherApp());
}

// ============================================================
// CONFIGURATION
// ============================================================

const String appName = 'WIFI VOUCHER';

const String apiUrl =
    'https://script.google.com/macros/s/AKfycbz1NylDHQeB4kzSUJXRPQnWJn2PZn0Q0Orz8vkW_jNhk00y76aWa4pH-EBxDMQvMQ7AQg/exec';

// ============================================================
// APP
// ============================================================

class WifiVoucherApp extends StatelessWidget {
  const WifiVoucherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF087F5B),
        scaffoldBackgroundColor: const Color(0xFFF4FAF8),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFE0E0E0),
            ),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

String jsonValue(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final wantedKey in keys) {
    if (json.containsKey(wantedKey)) {
      final value = json[wantedKey];

      if (value != null) {
        return value.toString().trim();
      }
    }
  }

  for (final entry in json.entries) {
    final actual = entry.key
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');

    for (final wantedKey in keys) {
      final wanted = wantedKey
          .trim()
          .toLowerCase()
          .replaceAll('_', '')
          .replaceAll('-', '')
          .replaceAll(' ', '');

      if (actual == wanted) {
        if (entry.value != null) {
          return entry.value.toString().trim();
        }
      }
    }
  }

  return '';
}

dynamic findNestedValue(
  dynamic data,
  List<String> possibleKeys,
) {
  if (data is Map) {
    final map = Map<String, dynamic>.from(data);

    for (final key in possibleKeys) {
      if (map.containsKey(key)) {
        return map[key];
      }
    }

    for (final entry in map.entries) {
      final entryKey = entry.key
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll('_', '')
          .replaceAll('-', '')
          .replaceAll(' ', '');

      for (final key in possibleKeys) {
        final wanted = key
            .trim()
            .toLowerCase()
            .replaceAll('_', '')
            .replaceAll('-', '')
            .replaceAll(' ', '');

        if (entryKey == wanted) {
          return entry.value;
        }
      }
    }

    for (final entry in map.entries) {
      final nested = findNestedValue(
        entry.value,
        possibleKeys,
      );

      if (nested != null) {
        return nested;
      }
    }
  }

  return null;
}

String normalizeDateString(
  String value,
) {
  final text = value.trim();

  if (text.isEmpty) {
    return '';
  }

  final yyyyMmDd = RegExp(
    r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
  ).firstMatch(text);

  if (yyyyMmDd != null) {
    final year = int.tryParse(yyyyMmDd.group(1) ?? '');
    final month = int.tryParse(yyyyMmDd.group(2) ?? '');
    final day = int.tryParse(yyyyMmDd.group(3) ?? '');

    if (year != null && month != null && day != null) {
      return '${day.toString().padLeft(2, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '$year';
    }
  }

  final ddMmYyyy = RegExp(
    r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})',
  ).firstMatch(text);

  if (ddMmYyyy != null) {
    final day = int.tryParse(ddMmYyyy.group(1) ?? '');
    final month = int.tryParse(ddMmYyyy.group(2) ?? '');
    final year = int.tryParse(ddMmYyyy.group(3) ?? '');

    if (day != null && month != null && year != null) {
      return '${day.toString().padLeft(2, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '$year';
    }
  }

  try {
    final parsed = DateTime.tryParse(text);

    if (parsed != null) {
      return '${parsed.day.toString().padLeft(2, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.year}';
    }
  } catch (_) {}

  return text;
}

// ============================================================
// IMPORTANT HISTORY DATE + TIME SORT
// ============================================================

DateTime parseVoucherDateTime(
  String date,
  String time,
) {
  try {
    final dateText = normalizeDateString(date);

    final dateParts = dateText.split('-');

    if (dateParts.length == 3) {
      final day = int.tryParse(dateParts[0]) ?? 1;
      final month = int.tryParse(dateParts[1]) ?? 1;
      final year = int.tryParse(dateParts[2]) ?? 2000;

      final cleanTime = time.trim();

      final timeParts = cleanTime.split(':');

      final hour = timeParts.isNotEmpty
          ? int.tryParse(
                timeParts[0].replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0
          : 0;

      final minute = timeParts.length > 1
          ? int.tryParse(
                timeParts[1].replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0
          : 0;

      final second = timeParts.length > 2
          ? int.tryParse(
                timeParts[2].split('.').first.replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0
          : 0;

      return DateTime(
        year,
        month,
        day,
        hour,
        minute,
        second,
      );
    }
  } catch (e) {
    debugPrint(
      'DATE TIME PARSE ERROR: $e',
    );
  }

  return DateTime(2000);
}

// ============================================================
// MODELS
// ============================================================

class Employee {
  final String empCode;
  final String name;
  final String company;
  final String mobile;

  Employee({
    required this.empCode,
    required this.name,
    required this.company,
    required this.mobile,
  });

  factory Employee.fromJson(
    Map<String, dynamic> json,
  ) {
    return Employee(
      empCode: jsonValue(
        json,
        [
          'empCode',
          'employeeCode',
          'emp_code',
          'Emp Code',
          'Employee Code',
          'code',
        ],
      ),
      name: jsonValue(
        json,
        [
          'name',
          'employeeName',
          'employee_name',
          'Name',
          'Employee Name',
        ],
      ),
      company: jsonValue(
        json,
        [
          'company',
          'Company',
        ],
      ),
      mobile: jsonValue(
        json,
        [
          'mobile',
          'mobileNo',
          'mobileNumber',
          'phone',
          'Mobile',
          'Mobile No',
          'Mobile Number',
        ],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'empCode': empCode,
      'name': name,
      'company': company,
      'mobile': mobile,
    };
  }
}

class VoucherRecord {
  final String date;
  final String time;
  final String empCode;
  final String name;
  final String company;
  final String mobile;
  final String room;
  final String pin;
  final String status;
  final String issuedBy;

  VoucherRecord({
    required this.date,
    required this.time,
    required this.empCode,
    required this.name,
    required this.company,
    required this.mobile,
    required this.room,
    required this.pin,
    required this.status,
    required this.issuedBy,
  });

  factory VoucherRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawDate = jsonValue(
      json,
      [
        'date',
        'Date',
        'issueDate',
        'issuedDate',
        'Issue Date',
      ],
    );

    return VoucherRecord(
      date: normalizeDateString(rawDate),
      time: jsonValue(
        json,
        [
          'time',
          'Time',
          'issueTime',
          'issuedTime',
          'Issue Time',
        ],
      ),
      empCode: jsonValue(
        json,
        [
          'empCode',
          'employeeCode',
          'emp_code',
          'Emp Code',
          'Employee Code',
          'code',
        ],
      ),
      name: jsonValue(
        json,
        [
          'name',
          'employeeName',
          'employee_name',
          'Name',
          'Employee Name',
        ],
      ),
      company: jsonValue(
        json,
        [
          'company',
          'Company',
        ],
      ),
      mobile: jsonValue(
        json,
        [
          'mobile',
          'mobileNo',
          'mobileNumber',
          'phone',
          'Mobile',
          'Mobile No',
          'Mobile Number',
        ],
      ),
      room: jsonValue(
        json,
        [
          'room',
          'roomNo',
          'roomNumber',
          'room_no',
          'Room',
          'Room No',
          'Room Number',
        ],
      ),
      pin: jsonValue(
        json,
        [
          'pin',
          'PIN',
          'voucherPin',
          'voucherPIN',
          'voucher',
          'Voucher PIN',
          'Voucher',
        ],
      ),
      status: jsonValue(
        json,
        [
          'status',
          'Status',
        ],
      ),
      issuedBy: jsonValue(
        json,
        [
          'issuedBy',
          'issued_by',
          'Issued By',
          'user',
          'username',
          'User',
          'Username',
        ],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'time': time,
      'empCode': empCode,
      'name': name,
      'company': company,
      'mobile': mobile,
      'room': room,
      'pin': pin,
      'status': status,
      'issuedBy': issuedBy,
    };
  }
}

// ============================================================
// API SERVICE
// ============================================================

class ApiService {
  static const String employeeCachePrefix = 'wifi_employee_cache_';

  static const String employeeMasterCacheKey = 'wifi_employee_master_cache';

  static const String employeeMasterVersionKey = 'wifi_employee_master_version';

  // ==========================================================
  // HISTORY LOCAL CACHE
  // ==========================================================

  static const String historyCacheKey = 'wifi_voucher_history_cache_v1';

  String _historyRecordKey(
    VoucherRecord record,
  ) {
    final pin = record.pin.trim();

    if (pin.isNotEmpty) {
      return 'PIN:$pin';
    }

    return '${record.date}|${record.time}|'
        '${record.empCode.trim().toUpperCase()}|'
        '${record.name.trim().toUpperCase()}|'
        '${record.room.trim().toUpperCase()}';
  }

  bool _isUsedHistoryRecord(
    VoucherRecord record,
  ) {
    final status = record.status.trim().toUpperCase();

    return status.isEmpty || status == 'USED';
  }

  void _sortHistory(
    List<VoucherRecord> records,
  ) {
    records.sort(
      (a, b) {
        return parseVoucherDateTime(
          b.date,
          b.time,
        ).compareTo(
          parseVoucherDateTime(
            a.date,
            a.time,
          ),
        );
      },
    );
  }

  Future<List<VoucherRecord>> getCachedHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(
      historyCacheKey,
    );

    if (value == null || value.trim().isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is! List) {
        return [];
      }

      final records = <VoucherRecord>[];

      for (final item in decoded) {
        if (item is Map) {
          try {
            final record = VoucherRecord.fromJson(
              Map<String, dynamic>.from(item),
            );

            if (record.pin.isNotEmpty ||
                record.empCode.isNotEmpty ||
                record.name.isNotEmpty) {
              records.add(record);
            }
          } catch (e) {
            debugPrint(
              'HISTORY CACHE ITEM ERROR: $e',
            );
          }
        }
      }

      _sortHistory(records);

      return records;
    } catch (e) {
      debugPrint(
        'HISTORY CACHE READ ERROR: $e',
      );

      return [];
    }
  }

  Future<List<VoucherRecord>> mergeHistoryCache(
    List<VoucherRecord> newRecords,
  ) async {
    final existing = await getCachedHistory();

    final Map<String, VoucherRecord> merged = {};

    for (final record in existing) {
      if (_isUsedHistoryRecord(record)) {
        merged[_historyRecordKey(record)] = record;
      }
    }

    for (final record in newRecords) {
      if (_isUsedHistoryRecord(record)) {
        merged[_historyRecordKey(record)] = record;
      }
    }

    final result = merged.values.toList();

    _sortHistory(result);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      historyCacheKey,
      jsonEncode(
        result.map((e) => e.toJson()).toList(),
      ),
    );

    debugPrint(
      'HISTORY CACHE SAVED: ${result.length} records',
    );

    return result;
  }

  Future<void> saveHistoryRecordToCache(
    VoucherRecord record,
  ) async {
    await mergeHistoryCache([
      record,
    ]);
  }

  // ==========================================================
  // API POST
  // ==========================================================

  Future<Map<String, dynamic>> post(
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse(apiUrl);
    final action = '${data['action'] ?? ''}'.trim();

    debugPrint('========================================');
    debugPrint('WIFI VOUCHER API POST');
    debugPrint('ACTION: $action');
    debugPrint('URL: $uri');
    debugPrint('DATA: ${jsonEncode(data)}');
    debugPrint('========================================');

    try {
      final request = http.Request(
        'POST',
        uri,
      );

      request.followRedirects = false;
      request.maxRedirects = 0;

      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });

      request.body = jsonEncode(data);

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        'POST STATUS: ${response.statusCode}',
      );

      debugPrint(
        'POST LOCATION: ${response.headers['location']}',
      );

      debugPrint(
        'POST BODY: ${response.body}',
      );

      final body = response.body.trim();

      if (body.isNotEmpty &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        return decodeResponse(body);
      }

      final location = response.headers['location'];

      if (location != null && location.trim().isNotEmpty) {
        debugPrint(
          'GOOGLE REDIRECT FOUND',
        );

        try {
          final redirectUri = Uri.parse(
            location,
          );

          final redirectResponse = await http.get(
            redirectUri,
            headers: const {
              'Accept': 'application/json',
            },
          ).timeout(
            const Duration(seconds: 30),
          );

          final redirectBody = redirectResponse.body.trim();

          debugPrint(
            'REDIRECT STATUS: ${redirectResponse.statusCode}',
          );

          debugPrint(
            'REDIRECT BODY: $redirectBody',
          );

          if (redirectBody.isNotEmpty) {
            return decodeResponse(
              redirectBody,
            );
          }
        } catch (redirectError) {
          debugPrint(
            'REDIRECT ERROR: $redirectError',
          );

          if (action == 'issueVoucher' || action == 'addVoucher') {
            throw Exception(
              'Server response could not be received. '
              'Please check History before trying again.',
            );
          }
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw Exception(
          'Empty server response.',
        );
      }

      if (action == 'issueVoucher' || action == 'addVoucher') {
        throw Exception(
          'Voucher server response could not be received. '
          'Please check History before trying again.',
        );
      }

      const readOnlyActions = {
        'getEmployee',
        'getEmployees',
        'getEmployeeVersion',
        'getAvailableVouchers',
        'getHistory',
        'getVoucher',
      };

      if (readOnlyActions.contains(action)) {
        return await getFallback(data);
      }

      throw Exception(
        'Server did not return a valid response.',
      );
    } catch (e) {
      debugPrint(
        'POST ERROR: $e',
      );

      if (action == 'issueVoucher' || action == 'addVoucher') {
        if (e is Exception &&
            e.toString().contains(
                  'Please check History before trying again',
                )) {
          rethrow;
        }

        throw Exception(
          'Server connection failed. '
          'Please check History before trying again.',
        );
      }

      const readOnlyActions = {
        'getEmployee',
        'getEmployees',
        'getEmployeeVersion',
        'getAvailableVouchers',
        'getHistory',
        'getVoucher',
      };

      if (readOnlyActions.contains(action)) {
        try {
          return await getFallback(data);
        } catch (getError) {
          debugPrint(
            'GET FALLBACK ERROR: $getError',
          );

          throw Exception(
            'Server connection failed.',
          );
        }
      }

      rethrow;
    }
  }

  // ==========================================================
  // GET FALLBACK
  // ==========================================================

  Future<Map<String, dynamic>> getFallback(
    Map<String, dynamic> data,
  ) async {
    final queryParameters = <String, String>{};

    data.forEach(
      (key, value) {
        queryParameters[key] = value.toString();
      },
    );

    final uri = Uri.parse(apiUrl).replace(
      queryParameters: queryParameters,
    );

    debugPrint(
      'GET FALLBACK URL: $uri',
    );

    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 30),
    );

    final body = response.body.trim();

    debugPrint(
      'GET FALLBACK STATUS: ${response.statusCode}',
    );

    debugPrint(
      'GET FALLBACK BODY: $body',
    );

    if (body.isEmpty) {
      throw Exception(
        'Empty server response.',
      );
    }

    return decodeResponse(body);
  }

  // ==========================================================
  // RAW GET
  // ==========================================================

  Future<dynamic> getRaw(
    Map<String, dynamic> data,
  ) async {
    final queryParameters = <String, String>{};

    data.forEach(
      (key, value) {
        queryParameters[key] = value.toString();
      },
    );

    final uri = Uri.parse(apiUrl).replace(
      queryParameters: queryParameters,
    );

    debugPrint('========================================');
    debugPrint('WIFI VOUCHER RAW GET');
    debugPrint('URL: $uri');
    debugPrint('========================================');

    final client = http.Client();

    try {
      final request = http.Request(
        'GET',
        uri,
      );

      request.followRedirects = false;
      request.maxRedirects = 0;

      request.headers.addAll({
        'Accept': 'application/json',
      });

      final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 30),
          );

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        'RAW GET STATUS: ${response.statusCode}',
      );

      debugPrint(
        'RAW GET LOCATION: '
        '${response.headers['location']}',
      );

      debugPrint(
        'RAW GET BODY: ${response.body}',
      );

      String body = response.body.trim();

      final location = response.headers['location'];

      if (location != null && location.trim().isNotEmpty) {
        debugPrint(
          'RAW GET REDIRECT FOUND',
        );

        final redirectUri = Uri.parse(
          location,
        );

        final redirectResponse = await http.get(
          redirectUri,
          headers: const {
            'Accept': 'application/json',
          },
        ).timeout(
          const Duration(seconds: 30),
        );

        debugPrint(
          'RAW REDIRECT STATUS: '
          '${redirectResponse.statusCode}',
        );

        debugPrint(
          'RAW REDIRECT BODY: '
          '${redirectResponse.body}',
        );

        body = redirectResponse.body.trim();
      }

      if (body.isEmpty) {
        throw Exception(
          'Empty server response.',
        );
      }

      dynamic decoded;

      try {
        decoded = jsonDecode(body);
      } catch (e) {
        debugPrint(
          'RAW JSON ERROR: $e',
        );

        throw Exception(
          'Invalid server response.',
        );
      }

      return decoded;
    } finally {
      client.close();
    }
  }

  // ==========================================================
  // DIRECT GET
  // ==========================================================

  Future<Map<String, dynamic>> get(
    Map<String, dynamic> data,
  ) async {
    final queryParameters = <String, String>{};

    data.forEach(
      (key, value) {
        queryParameters[key] = value.toString();
      },
    );

    final uri = Uri.parse(apiUrl).replace(
      queryParameters: queryParameters,
    );

    debugPrint('========================================');
    debugPrint('WIFI VOUCHER API GET');
    debugPrint('URL: $uri');
    debugPrint('========================================');

    try {
      final client = http.Client();

      try {
        final request = http.Request(
          'GET',
          uri,
        );

        request.followRedirects = false;
        request.maxRedirects = 0;

        request.headers.addAll({
          'Accept': 'application/json',
        });

        final streamedResponse = await client.send(request).timeout(
              const Duration(seconds: 30),
            );

        final response = await http.Response.fromStream(
          streamedResponse,
        );

        debugPrint(
          'GET STATUS: ${response.statusCode}',
        );

        debugPrint(
          'GET LOCATION: '
          '${response.headers['location']}',
        );

        debugPrint(
          'GET BODY: '
          '${response.body}',
        );

        String body = response.body.trim();

        final location = response.headers['location'];

        if (location != null && location.trim().isNotEmpty) {
          final redirectUri = Uri.parse(location);

          final redirectResponse = await http.get(
            redirectUri,
            headers: const {
              'Accept': 'application/json',
            },
          ).timeout(
            const Duration(seconds: 30),
          );

          body = redirectResponse.body.trim();
        }

        if (body.isEmpty) {
          throw Exception(
            'Empty server response.',
          );
        }

        return decodeResponse(body);
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint(
        'DIRECT GET ERROR: $e',
      );

      rethrow;
    }
  }

  // ==========================================================
  // DECODE
  // ==========================================================

  Map<String, dynamic> decodeResponse(
    String body,
  ) {
    dynamic decoded;

    try {
      decoded = jsonDecode(body);
    } catch (e) {
      debugPrint(
        'JSON DECODE ERROR: $e',
      );

      debugPrint(
        'RAW RESPONSE: $body',
      );

      throw Exception(
        'Invalid server response.',
      );
    }

    if (decoded is! Map) {
      throw Exception(
        'Invalid server response.',
      );
    }

    final result = Map<String, dynamic>.from(
      decoded,
    );

    if (result['success'] != true) {
      throw Exception(
        '${result['message'] ?? 'Unknown server error'}',
      );
    }

    return result;
  }

  // ==========================================================
  // LOGIN
  // ==========================================================

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final enteredUsername = username.trim();

    final result = await post(
      {
        'action': 'login',
        'username': enteredUsername,
        'password': password,
      },
    );

    String serverUsername = '${result['username'] ?? ''}'.trim();

    if (serverUsername.isEmpty) {
      serverUsername = '${result['userName'] ?? ''}'.trim();
    }

    if (serverUsername.isEmpty) {
      serverUsername = '${result['name'] ?? ''}'.trim();
    }

    if (serverUsername.isEmpty) {
      serverUsername = enteredUsername;
    }

    if (serverUsername.isEmpty) {
      throw Exception(
        'Username could not be identified.',
      );
    }

    return serverUsername;
  }

  // ==========================================================
  // EMPLOYEE CACHE
  // ==========================================================

  Future<void> saveEmployeeCache(
    Employee employee,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final key = '$employeeCachePrefix'
        '${employee.empCode.trim().toUpperCase()}';

    await prefs.setString(
      key,
      jsonEncode(
        employee.toJson(),
      ),
    );
  }

  Future<Employee?> getCachedEmployee(
    String empCode,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final key = '$employeeCachePrefix'
        '${empCode.trim().toUpperCase()}';

    final value = prefs.getString(key);

    if (value == null || value.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return Employee.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (e) {
      debugPrint(
        'CACHE READ ERROR: $e',
      );
    }

    return null;
  }

  Future<void> saveAllEmployeesCache(
    List<Employee> employees,
    String version,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> cache = {};

    for (final employee in employees) {
      final code = employee.empCode.trim().toUpperCase();

      if (code.isEmpty) {
        continue;
      }

      cache[code] = employee.toJson();
    }

    await prefs.setString(
      employeeMasterCacheKey,
      jsonEncode(cache),
    );

    await prefs.setString(
      employeeMasterVersionKey,
      version,
    );

    for (final employee in employees) {
      await saveEmployeeCache(employee);
    }

    debugPrint(
      'EMPLOYEE MASTER CACHE SAVED: '
      '${employees.length} employees',
    );

    debugPrint(
      'MASTER VERSION: $version',
    );
  }

  Future<Map<String, Employee>> getAllCachedEmployees() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(
      employeeMasterCacheKey,
    );

    final Map<String, Employee> result = {};

    if (value == null || value.trim().isEmpty) {
      return result;
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        decoded.forEach(
          (key, value) {
            if (value is Map) {
              final employee = Employee.fromJson(
                Map<String, dynamic>.from(value),
              );

              final code = employee.empCode.trim().toUpperCase();

              if (code.isNotEmpty) {
                result[code] = employee;
              }
            }
          },
        );
      }
    } catch (e) {
      debugPrint(
        'MASTER CACHE READ ERROR: $e',
      );
    }

    return result;
  }

  Future<String> getSavedMasterVersion() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(
          employeeMasterVersionKey,
        ) ??
        '';
  }

  Future<String> getMasterVersion() async {
    final result = await post(
      {
        'action': 'getEmployeeVersion',
      },
    );

    return '${result['version'] ?? ''}'.trim();
  }

  Future<void> syncEmployeesFromServer() async {
    final result = await post(
      {
        'action': 'getEmployees',
      },
    );

    final dynamic rawEmployees = result['employees'];

    final List data = rawEmployees is List ? rawEmployees : [];

    final String version = '${result['version'] ?? ''}'.trim();

    final List<Employee> employees = data
        .whereType<Map>()
        .map(
          (e) => Employee.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();

    await saveAllEmployeesCache(
      employees,
      version,
    );
  }

  Future<void> syncEmployeesIfNeeded({
    bool force = false,
  }) async {
    try {
      final savedVersion = await getSavedMasterVersion();

      if (force || savedVersion.isEmpty) {
        await syncEmployeesFromServer();
        return;
      }

      final serverVersion = await getMasterVersion();

      if (serverVersion.isEmpty) {
        return;
      }

      if (serverVersion != savedVersion) {
        debugPrint(
          'MASTER CHANGED.',
        );

        debugPrint(
          'OLD VERSION: $savedVersion',
        );

        debugPrint(
          'NEW VERSION: $serverVersion',
        );

        await syncEmployeesFromServer();
      } else {
        debugPrint(
          'MASTER CACHE IS UP TO DATE.',
        );
      }
    } catch (e) {
      debugPrint(
        'MASTER CACHE SYNC ERROR: $e',
      );
    }
  }

  Future<Employee?> getEmployeeFromMasterCache(
    String empCode,
  ) async {
    final code = empCode.trim().toUpperCase();

    if (code.isEmpty) {
      return null;
    }

    final employees = await getAllCachedEmployees();

    return employees[code];
  }

  Future<Employee> getEmployee(
    String empCode,
  ) async {
    final code = empCode.trim();

    if (code.isEmpty) {
      throw Exception(
        'Enter Emp Code.',
      );
    }

    final masterCached = await getEmployeeFromMasterCache(code);

    if (masterCached != null) {
      debugPrint(
        'LOCAL MASTER CACHE USED: $code',
      );

      return masterCached;
    }

    final individualCached = await getCachedEmployee(code);

    if (individualCached != null) {
      debugPrint(
        'INDIVIDUAL CACHE USED: $code',
      );

      return individualCached;
    }

    try {
      final result = await post(
        {
          'action': 'getEmployee',
          'empCode': code,
        },
      );

      final employeeData = result['employee'];

      if (employeeData == null) {
        throw Exception(
          'Employee not found.',
        );
      }

      if (employeeData is! Map) {
        throw Exception(
          'Invalid employee data.',
        );
      }

      final employee = Employee.fromJson(
        Map<String, dynamic>.from(
          employeeData,
        ),
      );

      await saveEmployeeCache(employee);

      return employee;
    } catch (e) {
      if (individualCached != null) {
        return individualCached;
      }

      rethrow;
    }
  }

  // ==========================================================
  // ADD VOUCHER
  // ==========================================================

  Future<void> addVoucher(
    String pin,
    String issuedBy,
  ) async {
    await post(
      {
        'action': 'addVoucher',
        'pin': pin,
        'issuedBy': issuedBy,
      },
    );
  }

  // ==========================================================
  // ISSUE VOUCHER
  // ==========================================================

  Future<VoucherRecord> issueVoucher({
    required String empCode,
    required String name,
    required String company,
    required String mobile,
    required String room,
    required String issuedBy,
  }) async {
    debugPrint(
      '========================================',
    );

    debugPrint(
      'ISSUE VOUCHER START',
    );

    debugPrint(
      'EMP CODE: $empCode',
    );

    debugPrint(
      'NAME: $name',
    );

    debugPrint(
      'ROOM: $room',
    );

    debugPrint(
      'ISSUED BY: $issuedBy',
    );

    debugPrint(
      '========================================',
    );

    final result = await post(
      {
        'action': 'issueVoucher',
        'empCode': empCode,
        'name': name,
        'company': company,
        'mobile': mobile,
        'room': room,
        'issuedBy': issuedBy,
      },
    );

    debugPrint(
      'ISSUE VOUCHER RESPONSE: $result',
    );

    final voucherData = result['voucher'];

    if (voucherData == null) {
      throw Exception(
        'Voucher data not returned.',
      );
    }

    if (voucherData is! Map) {
      throw Exception(
        'Invalid voucher data returned.',
      );
    }

    final voucher = VoucherRecord.fromJson(
      Map<String, dynamic>.from(
        voucherData,
      ),
    );

    if (voucher.pin.trim().isEmpty) {
      throw Exception(
        'Voucher PIN was not returned.',
      );
    }

    debugPrint(
      'VOUCHER SUCCESS: ${voucher.pin}',
    );

    return voucher;
  }

  // ==========================================================
  // HISTORY
  // ==========================================================

  Future<List<VoucherRecord>> getHistory({
    required String fromDate,
    required String toDate,
  }) async {
    debugPrint(
      '========================================',
    );

    debugPrint(
      'GET HISTORY START',
    );

    debugPrint(
      'FROM DATE: $fromDate',
    );

    debugPrint(
      'TO DATE: $toDate',
    );

    debugPrint(
      '========================================',
    );

    final rawResponse = await getRaw(
      {
        'action': 'getHistory',
        'fromDate': fromDate,
        'toDate': toDate,
      },
    );

    debugPrint(
      'RAW HISTORY RESPONSE: $rawResponse',
    );

    if (rawResponse is Map) {
      final serverMap = Map<String, dynamic>.from(rawResponse);

      if (serverMap.containsKey('success') && serverMap['success'] == false) {
        throw Exception(
          '${serverMap['message'] ?? 'Unable to load History'}',
        );
      }
    }

    dynamic rawHistory = _extractHistory(rawResponse);

    debugPrint(
      'EXTRACTED HISTORY: $rawHistory',
    );

    if (rawHistory == null) {
      debugPrint(
        'HISTORY DATA NOT FOUND',
      );

      return [];
    }

    if (rawHistory is String) {
      final text = rawHistory.trim();

      if (text.isNotEmpty) {
        try {
          rawHistory = jsonDecode(text);
        } catch (_) {}
      }
    }

    if (rawHistory is! List) {
      throw Exception(
        'Invalid history data returned.',
      );
    }

    final List<VoucherRecord> records = [];

    for (final item in rawHistory) {
      if (item is Map) {
        try {
          final record = VoucherRecord.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (record.pin.isNotEmpty ||
              record.empCode.isNotEmpty ||
              record.name.isNotEmpty) {
            records.add(record);
          }
        } catch (e) {
          debugPrint(
            'HISTORY ITEM ERROR: $e',
          );
        }
      }
    }

    _sortHistory(records);

    debugPrint(
      'HISTORY RECORD COUNT: ${records.length}',
    );

    if (records.isNotEmpty) {
      debugPrint(
        'NEWEST HISTORY: '
        '${records.first.date} '
        '${records.first.time} '
        '${records.first.empCode} '
        '${records.first.pin}',
      );
    }

    // ========================================================
    // SAVE SERVER HISTORY INTO LOCAL CACHE
    // ========================================================

    try {
      await mergeHistoryCache(records);
    } catch (e) {
      debugPrint(
        'HISTORY CACHE SAVE ERROR: $e',
      );
    }

    return records;
  }

  dynamic _extractHistory(
    dynamic data,
  ) {
    if (data == null) {
      return null;
    }

    if (data is List) {
      return data;
    }

    if (data is String) {
      final text = data.trim();

      if (text.isEmpty) {
        return null;
      }

      try {
        final decoded = jsonDecode(text);

        return _extractHistory(decoded);
      } catch (_) {
        return null;
      }
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);

      const keys = [
        'history',
        'records',
        'vouchers',
        'items',
        'results',
        'data',
        'list',
      ];

      for (final key in keys) {
        if (map.containsKey(key)) {
          final value = map[key];

          if (value is List) {
            return value;
          }

          if (value is String) {
            final parsed = _extractHistory(value);

            if (parsed != null) {
              return parsed;
            }
          }

          if (value is Map) {
            final nested = _extractHistory(value);

            if (nested != null) {
              return nested;
            }
          }
        }
      }

      for (final entry in map.entries) {
        final key = entry.key
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll('_', '')
            .replaceAll('-', '')
            .replaceAll(' ', '');

        if (key == 'history' ||
            key == 'records' ||
            key == 'vouchers' ||
            key == 'items' ||
            key == 'results' ||
            key == 'data' ||
            key == 'list') {
          final nested = _extractHistory(entry.value);

          if (nested != null) {
            return nested;
          }
        }
      }

      for (final entry in map.entries) {
        if (entry.value is Map ||
            entry.value is List ||
            entry.value is String) {
          final nested = _extractHistory(entry.value);

          if (nested != null) {
            return nested;
          }
        }
      }

      if (_looksLikeVoucherRecord(map)) {
        return [map];
      }
    }

    return null;
  }

  bool _looksLikeVoucherRecord(
    Map<String, dynamic> map,
  ) {
    final pin = jsonValue(
      map,
      [
        'pin',
        'PIN',
        'voucherPin',
        'voucherPIN',
      ],
    );

    final empCode = jsonValue(
      map,
      [
        'empCode',
        'employeeCode',
        'Emp Code',
      ],
    );

    final date = jsonValue(
      map,
      [
        'date',
        'Date',
      ],
    );

    return pin.isNotEmpty || empCode.isNotEmpty || date.isNotEmpty;
  }

  // ==========================================================
  // GET VOUCHER
  // ==========================================================

  Future<VoucherRecord> getVoucher({
    required String date,
    required String time,
    required String empCode,
    required String pin,
  }) async {
    final result = await get(
      {
        'action': 'getVoucher',
        'date': date,
        'time': time,
        'empCode': empCode,
        'pin': pin,
      },
    );

    final voucherData = result['voucher'];

    if (voucherData == null) {
      throw Exception(
        'Voucher not found.',
      );
    }

    if (voucherData is! Map) {
      throw Exception(
        'Invalid voucher data.',
      );
    }

    return VoucherRecord.fromJson(
      Map<String, dynamic>.from(
        voucherData,
      ),
    );
  }
}

final ApiService api = ApiService();

// ============================================================
// VALID UNTIL
// ============================================================

String calculateValidUntil(
  String date,
) {
  try {
    final normalized = normalizeDateString(date);

    final parts = normalized.split('-');

    if (parts.length == 3) {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      final issueDate = DateTime(
        year,
        month,
        day,
      );

      final validDate = issueDate.add(
        const Duration(days: 30),
      );

      return '${validDate.day.toString().padLeft(2, '0')}-'
          '${validDate.month.toString().padLeft(2, '0')}-'
          '${validDate.year}';
    }
  } catch (_) {}

  return '';
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final username = usernameController.text.trim();

    final password = passwordController.text;

    if (username.isEmpty) {
      showMessage('Enter User Name.');
      return;
    }

    if (password.isEmpty) {
      showMessage('Enter Password.');
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final loggedUser = await api.login(
        username: username,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            loggedUser: loggedUser,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF087F5B),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.wifi,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'WIFI VOUCHER',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Login to continue',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: usernameController,
                            textCapitalization: TextCapitalization.none,
                            decoration: const InputDecoration(
                              labelText: 'User Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            onSubmitted: (_) {
                              if (!loading) {
                                login();
                              }
                            },
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    obscurePassword = !obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            onSubmitted: (_) {
                              if (!loading) {
                                login();
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: loading ? null : login,
                              icon: const Icon(
                                Icons.login,
                              ),
                              label: loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'LOGIN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatefulWidget {
  final String loggedUser;

  const HomePage({
    super.key,
    required this.loggedUser,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int currentIndex = 0;

  late final List<Widget> pages;

  Timer? employeeSyncTimer;

  bool syncingEmployeeCache = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    pages = [
      IssueVoucherPage(
        loggedUser: widget.loggedUser,
      ),
      VoucherUploadPage(
        loggedUser: widget.loggedUser,
      ),
      const HistoryPage(),
    ];

    syncEmployeeCache();

    employeeSyncTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        syncEmployeeCache();
      },
    );
  }

  Future<void> syncEmployeeCache() async {
    if (syncingEmployeeCache) {
      return;
    }

    syncingEmployeeCache = true;

    try {
      await api.syncEmployeesIfNeeded();
    } catch (e) {
      debugPrint(
        'BACKGROUND EMPLOYEE SYNC ERROR: $e',
      );
    } finally {
      syncingEmployeeCache = false;
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      syncEmployeeCache();
    }
  }

  @override
  void dispose() {
    employeeSyncTimer?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: currentIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi),
            label: 'Issue',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_card),
            label: 'Voucher',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ISSUE VOUCHER PAGE
// ============================================================

class IssueVoucherPage extends StatefulWidget {
  final String loggedUser;

  const IssueVoucherPage({
    super.key,
    required this.loggedUser,
  });

  @override
  State<IssueVoucherPage> createState() => _IssueVoucherPageState();
}

class _IssueVoucherPageState extends State<IssueVoucherPage> {
  final TextEditingController empController = TextEditingController();

  final TextEditingController roomController = TextEditingController();

  final TextEditingController notesController = TextEditingController();

  Employee? employee;

  bool loading = false;

  @override
  void dispose() {
    empController.dispose();
    roomController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> searchEmployee() async {
    FocusScope.of(context).unfocus();

    final code = empController.text.trim();

    if (code.isEmpty) {
      showMessage('Enter Emp Code.');
      return;
    }

    setState(() {
      loading = true;
      employee = null;
      roomController.clear();
      notesController.clear();
    });

    try {
      final result = await api.getEmployee(code);

      if (!mounted) return;

      FocusScope.of(context).unfocus();

      setState(() {
        employee = result;
        roomController.clear();
        notesController.clear();
      });
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> scanQr() async {
    FocusScope.of(context).unfocus();

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(),
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }

    final code = result.trim();

    if (empController.text.trim() == code) {
      return;
    }

    empController.text = code;

    await searchEmployee();
  }

  Future<void> submitVoucher() async {
    if (loading) {
      return;
    }

    if (employee == null) {
      showMessage(
        'Search employee first.',
      );
      return;
    }

    final room = roomController.text.trim();

    final notes = notesController.text.trim();

    if (room.isEmpty && notes.isEmpty) {
      showMessage(
        'Enter Room No. or Notes.',
      );
      return;
    }

    String finalRoom = room;

    if (room.isNotEmpty && notes.isNotEmpty) {
      finalRoom = '$room | $notes';
    } else if (room.isEmpty && notes.isNotEmpty) {
      finalRoom = notes;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Confirm Voucher',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emp Code: ${employee!.empCode}',
              ),
              Text(
                'Name: ${employee!.name}',
              ),
              Text(
                'Company: ${employee!.company}',
              ),
              Text(
                'Mobile No.: ${employee!.mobile}',
              ),
              Text(
                'Room No.: $finalRoom',
              ),
              const SizedBox(height: 12),
              const Text(
                'Voucher will be issued only after you press SUBMIT.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'CANCEL',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'SUBMIT',
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final voucher = await api.issueVoucher(
        empCode: employee!.empCode,
        name: employee!.name,
        company: employee!.company,
        mobile: employee!.mobile,
        room: finalRoom,
        issuedBy: widget.loggedUser,
      );

      // ======================================================
      // NEW:
      // SAVE NEWLY ISSUED VOUCHER TO LOCAL HISTORY CACHE
      // ======================================================

      try {
        await api.saveHistoryRecordToCache(
          voucher,
        );
      } catch (cacheError) {
        debugPrint(
          'NEW VOUCHER CACHE ERROR: $cacheError',
        );
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoucherResultPage(
            voucher: voucher,
          ),
        ),
      );

      if (mounted) {
        clearForm();
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void clearForm() {
    setState(() {
      empController.clear();
      roomController.clear();
      notesController.clear();
      employee = null;
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        appHeader(
          title: 'WIFI VOUCHER',
          subtitle: 'Issue Internet Voucher',
          icon: Icons.wifi,
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : scanQr,
                    icon: const Icon(
                      Icons.qr_code_scanner,
                    ),
                    label: const Text(
                      'QR SCAN',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: empController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Emp Code',
                    prefixIcon: Icon(
                      Icons.badge,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!loading) {
                      searchEmployee();
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : searchEmployee,
                    icon: const Icon(
                      Icons.search,
                    ),
                    label: const Text(
                      'SEARCH',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                if (employee != null) employeeCard(),
                if (employee != null) const SizedBox(height: 15),
                if (employee != null)
                  TextField(
                    controller: roomController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Room No.',
                      prefixIcon: Icon(
                        Icons.meeting_room,
                      ),
                    ),
                  ),
                if (employee != null) const SizedBox(height: 12),
                if (employee != null)
                  TextField(
                    controller: notesController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(
                        Icons.note,
                      ),
                    ),
                  ),
                if (employee != null) const SizedBox(height: 20),
                if (employee != null)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: loading ? null : submitVoucher,
                      icon: const Icon(
                        Icons.send,
                      ),
                      label: const Text(
                        'SUBMIT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget employeeCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 30,
              child: Icon(
                Icons.person,
                size: 35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              employee!.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              employee!.empCode,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(employee!.company),
            const SizedBox(height: 5),
            Text(
              'Mobile: ${employee!.mobile}',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// VOUCHER UPLOAD PAGE
// ============================================================

class VoucherUploadPage extends StatefulWidget {
  final String loggedUser;

  const VoucherUploadPage({
    super.key,
    required this.loggedUser,
  });

  @override
  State<VoucherUploadPage> createState() => _VoucherUploadPageState();
}

class _VoucherUploadPageState extends State<VoucherUploadPage>
    with WidgetsBindingObserver {
  final TextEditingController pinController = TextEditingController();

  bool loading = false;
  bool loadingAvailable = false;
  int availableVoucherCount = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    loadAvailableVoucherCount();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      loadAvailableVoucherCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    pinController.dispose();

    super.dispose();
  }

  Future<void> loadAvailableVoucherCount() async {
    if (loadingAvailable) {
      return;
    }

    if (mounted) {
      setState(() {
        loadingAvailable = true;
      });
    }

    try {
      final result = await api.get(
        {
          'action': 'getAvailableVouchers',
        },
      );

      debugPrint(
        'AVAILABLE VOUCHER RESPONSE: $result',
      );

      final count = extractAvailableVoucherCount(
        result,
      );

      if (!mounted) return;

      setState(() {
        availableVoucherCount = count;
      });
    } catch (e) {
      debugPrint(
        'AVAILABLE VOUCHER COUNT ERROR: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          loadingAvailable = false;
        });
      }
    }
  }

  int extractAvailableVoucherCount(
    Map<String, dynamic> result,
  ) {
    const possibleKeys = [
      'availableCount',
      'availableVoucherCount',
      'availableVouchers',
      'available',
      'count',
      'totalAvailable',
      'remaining',
      'remainingVouchers',
      'balance',
    ];

    for (final key in possibleKeys) {
      if (result.containsKey(key)) {
        final value = result[key];

        final parsed = int.tryParse(
          '$value'.trim(),
        );

        if (parsed != null) {
          return parsed;
        }

        if (value is List) {
          return value.length;
        }
      }
    }

    final nestedCandidates = [
      result['data'],
      result['vouchers'],
      result['availableVoucherList'],
      result['availableVoucher'],
      result['result'],
    ];

    for (final value in nestedCandidates) {
      if (value is List) {
        return value.length;
      }

      if (value is Map) {
        final nestedMap = Map<String, dynamic>.from(value);

        for (final key in possibleKeys) {
          if (nestedMap.containsKey(key)) {
            final nestedValue = nestedMap[key];

            final parsed = int.tryParse(
              '$nestedValue'.trim(),
            );

            if (parsed != null) {
              return parsed;
            }

            if (nestedValue is List) {
              return nestedValue.length;
            }
          }
        }
      }
    }

    return 0;
  }

  Future<void> addManualPin() async {
    final pin = pinController.text.trim();

    if (!RegExp(r'^\d{12}$').hasMatch(pin)) {
      showMessage(
        'Voucher PIN must contain exactly 12 digits.',
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      await api.addVoucher(
        pin,
        widget.loggedUser,
      );

      if (!mounted) return;

      pinController.clear();

      showMessage(
        'Voucher PIN added successfully.',
      );

      await loadAvailableVoucherCount();
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        appHeader(
          title: 'VOUCHER',
          subtitle: 'Add Available Voucher PIN',
          icon: Icons.add_card,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadAvailableVoucherCount,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 55,
                            height: 55,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE8F5E9,
                              ),
                              borderRadius: BorderRadius.circular(
                                15,
                              ),
                            ),
                            child: const Icon(
                              Icons.confirmation_number,
                              color: Color(
                                0xFF087F5B,
                              ),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'AVAILABLE VOUCHER',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                loadingAvailable
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        '$availableVoucherCount',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Color(
                                            0xFF087F5B,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh Available Voucher',
                            onPressed: loadingAvailable
                                ? null
                                : loadAvailableVoucherCount,
                            icon: const Icon(
                              Icons.refresh,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.confirmation_number,
                            size: 65,
                            color: Color(
                              0xFF087F5B,
                            ),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'MANUAL PIN',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Enter exactly 12 digits.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 12,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Voucher PIN',
                              hintText: '652587421023',
                              prefixIcon: Icon(
                                Icons.password,
                              ),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: loading ? null : addManualPin,
                              icon: const Icon(
                                Icons.add,
                              ),
                              label: loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'ADD PIN',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: ListTile(
                        leading: Icon(
                          Icons.picture_as_pdf,
                        ),
                        title: Text(
                          'PDF / OCR',
                        ),
                        subtitle: Text(
                          'PDF OCR will be added after the real voucher sample is provided.',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// QR SCANNER
// ============================================================

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController scannerController;

  bool scanned = false;
  bool torchOn = false;
  bool cameraStarted = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(
      this,
    );

    scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    scannerController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      if (!scanned) {
        startCamera();
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopCamera();
    }
  }

  Future<void> startCamera() async {
    if (scanned) {
      return;
    }

    try {
      await scannerController.start();

      if (!mounted) return;

      setState(() {
        cameraStarted = true;
      });
    } catch (e) {
      debugPrint(
        'CAMERA START ERROR: $e',
      );
    }
  }

  Future<void> stopCamera() async {
    try {
      await scannerController.stop();

      if (!mounted) return;

      setState(() {
        cameraStarted = false;
      });
    } catch (e) {
      debugPrint(
        'CAMERA STOP ERROR: $e',
      );
    }
  }

  Future<void> toggleTorch() async {
    try {
      await scannerController.toggleTorch();

      if (!mounted) return;

      setState(() {
        torchOn = !torchOn;
      });
    } catch (e) {
      debugPrint(
        'TORCH ERROR: $e',
      );
    }
  }

  Future<void> onDetect(
    BarcodeCapture capture,
  ) async {
    if (scanned) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;

      if (value != null && value.trim().isNotEmpty) {
        scanned = true;

        try {
          await scannerController.stop();
        } catch (_) {}

        if (!mounted) return;

        Navigator.pop(
          context,
          value.trim(),
        );

        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SCAN EMPLOYEE QR',
        ),
        actions: [
          IconButton(
            tooltip: torchOn ? 'Turn Flash Off' : 'Turn Flash On',
            onPressed: toggleTorch,
            icon: Icon(
              torchOn ? Icons.flash_on : Icons.flash_off,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                0,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: scannerController,
                        onDetect: onDetect,
                        onDetectError: (
                          error,
                          stackTrace,
                        ) {
                          debugPrint(
                            'QR CAMERA ERROR: $error',
                          );
                        },
                      ),
                      Center(
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(
                            30,
                          ),
                          child: IconButton(
                            tooltip: torchOn ? 'Flash Off' : 'Flash On',
                            onPressed: toggleTorch,
                            icon: Icon(
                              torchOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place employee QR inside the frame',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  30,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    const Icon(
                      Icons.qr_code_scanner,
                      size: 65,
                      color: Color(
                        0xFF087F5B,
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Scan Employee QR Code',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Keep the QR code inside the camera frame.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'The camera remains active while this scanner is open.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// VOUCHER RESULT PAGE
// ============================================================

class VoucherResultPage extends StatelessWidget {
  final VoucherRecord voucher;

  const VoucherResultPage({
    super.key,
    required this.voucher,
  });

  Future<Uint8List> createPrintPdf() async {
    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'WIFI VOUCHER',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                voucher.pin,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: voucher.pin,
                width: 130,
                height: 130,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Emp Code: ${voucher.empCode}',
              ),
              pw.Text(
                'Name: ${voucher.name}',
              ),
              pw.Text(
                'Company: ${voucher.company}',
              ),
              pw.Text(
                'Mobile No: ${voucher.mobile}',
              ),
              pw.Text(
                'Room No: ${voucher.room}',
              ),
              pw.Text(
                'Date: ${voucher.date}',
              ),
              pw.Text(
                'Time: ${voucher.time}',
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Issued By: ${voucher.issuedBy}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Valid Until: '
                '${calculateValidUntil(voucher.date)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );

    return document.save();
  }

  Future<void> printVoucher(
    BuildContext context,
  ) async {
    try {
      await Printing.layoutPdf(
        onLayout: (format) async {
          return createPrintPdf();
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              'Print error: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> shareVoucher(
    BuildContext context,
  ) async {
    final text = '''
WIFI VOUCHER

PIN: ${voucher.pin}

Emp Code: ${voucher.empCode}
Name: ${voucher.name}
Company: ${voucher.company}
Mobile No: ${voucher.mobile}
Room No: ${voucher.room}

Date: ${voucher.date}
Time: ${voucher.time}

Issued By: ${voucher.issuedBy}

Valid Until: ${calculateValidUntil(voucher.date)}
''';

    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'VOUCHER',
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            40,
          ),
          child: Column(
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'WIFI VOUCHER',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        voucher.pin,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 15),
                      QrImageView(
                        data: voucher.pin,
                        size: 210,
                        backgroundColor: Colors.white,
                      ),
                      const Divider(
                        height: 30,
                      ),
                      infoRow(
                        'Emp Code',
                        voucher.empCode,
                      ),
                      infoRow(
                        'Name',
                        voucher.name,
                      ),
                      infoRow(
                        'Company',
                        voucher.company,
                      ),
                      infoRow(
                        'Mobile No',
                        voucher.mobile,
                      ),
                      infoRow(
                        'Room No',
                        voucher.room,
                      ),
                      infoRow(
                        'Date',
                        voucher.date,
                      ),
                      infoRow(
                        'Time',
                        voucher.time,
                      ),
                      infoRow(
                        'Issued By',
                        voucher.issuedBy,
                      ),
                      infoRow(
                        'Valid Until',
                        calculateValidUntil(
                          voucher.date,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        shareVoucher(
                          context,
                        );
                      },
                      icon: const Icon(
                        Icons.share,
                      ),
                      label: const Text(
                        'WHATSAPP',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        printVoucher(
                          context,
                        );
                      },
                      icon: const Icon(
                        Icons.print,
                      ),
                      label: const Text(
                        'PRINT',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  Widget infoRow(
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HISTORY PAGE
// ============================================================

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with WidgetsBindingObserver {
  DateTime fromDate = DateTime.now();

  DateTime toDate = DateTime.now();

  bool loading = false;

  List<VoucherRecord> history = [];

  final TextEditingController empCodeController = TextEditingController();

  Timer? historySyncTimer;

  bool syncingHistory = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(
      this,
    );

    // ========================================================
    // LOAD LOCAL CACHE IMMEDIATELY
    // THEN SYNC SERVER IN BACKGROUND
    // ========================================================

    _loadHistoryCacheAndSync();

    // ========================================================
    // BACKGROUND SYNC EVERY 2 MINUTES
    // ========================================================

    historySyncTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        _syncHistoryInBackground();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      _syncHistoryInBackground();
    }
  }

  @override
  void dispose() {
    historySyncTimer?.cancel();

    WidgetsBinding.instance.removeObserver(
      this,
    );

    empCodeController.dispose();

    super.dispose();
  }

  // ==========================================================
  // LOAD CACHE + BACKGROUND SERVER SYNC
  // ==========================================================

  Future<void> _loadHistoryCacheAndSync() async {
    try {
      final cached = await api.getCachedHistory();

      if (mounted) {
        setState(() {
          history = _filterHistory(
            cached,
          );
        });
      }
    } catch (e) {
      debugPrint(
        'HISTORY CACHE LOAD ERROR: $e',
      );
    }

    // Do not wait for this before showing cache.
    await _syncHistoryInBackground();
  }

  Future<void> _syncHistoryInBackground() async {
    if (syncingHistory) {
      return;
    }

    syncingHistory = true;

    try {
      final from = dateString(fromDate);
      final to = dateString(toDate);

      await api.getHistory(
        fromDate: from,
        toDate: to,
      );

      final cached = await api.getCachedHistory();

      if (mounted) {
        setState(() {
          history = _filterHistory(
            cached,
          );
        });
      }
    } catch (e) {
      // ======================================================
      // IMPORTANT:
      // BACKGROUND SYNC ERROR SHOULD NOT REMOVE CACHE
      // ======================================================

      debugPrint(
        'BACKGROUND HISTORY SYNC ERROR: $e',
      );
    } finally {
      syncingHistory = false;
    }
  }

  // ==========================================================
  // DATE PICKER
  // ==========================================================

  Future<void> selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        fromDate = picked;
      });

      // Refresh current selected range in background.
      _syncHistoryInBackground();
    }
  }

  Future<void> selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        toDate = picked;
      });

      // Refresh current selected range in background.
      _syncHistoryInBackground();
    }
  }

  String dateString(
    DateTime date,
  ) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // FILTER LOCAL CACHE
  // ==========================================================

  List<VoucherRecord> _filterHistory(
    List<VoucherRecord> source,
  ) {
    final start = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    );

    final end = DateTime(
      toDate.year,
      toDate.month,
      toDate.day,
      23,
      59,
      59,
      999,
    );

    final searchEmpCode = empCodeController.text.trim().toUpperCase();

    final filtered = source.where((item) {
      final recordDateTime = parseVoucherDateTime(
        item.date,
        item.time,
      );

      if (recordDateTime.isBefore(start) || recordDateTime.isAfter(end)) {
        return false;
      }

      if (searchEmpCode.isEmpty) {
        return true;
      }

      return item.empCode.trim().toUpperCase().contains(searchEmpCode);
    }).toList();

    filtered.sort(
      (a, b) {
        return parseVoucherDateTime(
          b.date,
          b.time,
        ).compareTo(
          parseVoucherDateTime(
            a.date,
            a.time,
          ),
        );
      },
    );

    return filtered;
  }

  // ==========================================================
  // SEARCH HISTORY
  //
  // 1. Show cache immediately
  // 2. Server sync
  // 3. Show updated merged cache
  // ==========================================================

  Future<void> searchHistory() async {
    if (loading) {
      return;
    }

    if (fromDate.isAfter(toDate)) {
      showMessage(
        'From Date cannot be after To Date.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    // ========================================================
    // FIRST SHOW LOCAL CACHE
    // ========================================================

    final cached = await api.getCachedHistory();

    if (!mounted) return;

    final cachedFiltered = _filterHistory(cached);

    setState(() {
      history = cachedFiltered;
      loading = true;
    });

    try {
      final from = dateString(fromDate);

      final to = dateString(toDate);

      final searchEmpCode = empCodeController.text.trim().toUpperCase();

      debugPrint(
        '========================================',
      );

      debugPrint(
        'HISTORY SEARCH',
      );

      debugPrint(
        'FROM: $from',
      );

      debugPrint(
        'TO: $to',
      );

      debugPrint(
        'EMP CODE: $searchEmpCode',
      );

      debugPrint(
        '========================================',
      );

      // ======================================================
      // SERVER DATA WILL ALSO BE SAVED INTO CACHE
      // ======================================================

      await api.getHistory(
        fromDate: from,
        toDate: to,
      );

      // ======================================================
      // READ MERGED CACHE
      // ======================================================

      final merged = await api.getCachedHistory();

      if (!mounted) return;

      final filteredResult = _filterHistory(merged);

      setState(() {
        history = filteredResult;
      });

      debugPrint(
        'CACHED + SERVER HISTORY: '
        '${merged.length}',
      );

      debugPrint(
        'FILTERED HISTORY: '
        '${filteredResult.length}',
      );

      if (filteredResult.isNotEmpty) {
        final first = filteredResult.first;

        debugPrint(
          'FIRST HISTORY RECORD:',
        );

        debugPrint(
          'DATE: ${first.date}',
        );

        debugPrint(
          'TIME: ${first.time}',
        );

        debugPrint(
          'EMP CODE: ${first.empCode}',
        );

        debugPrint(
          'PIN: ${first.pin}',
        );
      }

      if (filteredResult.isEmpty) {
        if (searchEmpCode.isEmpty) {
          showMessage(
            'No records found for selected date.',
          );
        } else {
          showMessage(
            'No records found for Emp Code: '
            '$searchEmpCode',
          );
        }
      }
    } catch (e) {
      debugPrint(
        'HISTORY ERROR: $e',
      );

      // ======================================================
      // SERVER ERROR:
      // KEEP LOCAL CACHE RESULT
      // ======================================================

      if (!mounted) return;

      if (cachedFiltered.isEmpty) {
        showMessage(
          'Failed to load history',
        );
      } else {
        debugPrint(
          'SERVER FAILED. SHOWING LOCAL HISTORY CACHE.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // ==========================================================
  // OPEN VOUCHER
  // ==========================================================

  Future<void> openVoucher(
    VoucherRecord item,
  ) async {
    debugPrint(
      'OPEN HISTORY VOUCHER: ${item.pin}',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoucherResultPage(
          voucher: item,
        ),
      ),
    );

    if (!mounted) return;

    debugPrint(
      'RETURNED TO HISTORY PAGE',
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        appHeader(
          title: 'HISTORY',
          subtitle: 'Voucher Issue History',
          icon: Icons.history,
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: empCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Emp Code',
                  hintText: 'Enter Emp Code',
                  prefixIcon: Icon(Icons.badge),
                ),
                onSubmitted: (_) {
                  if (!loading) {
                    searchHistory();
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : selectFromDate,
                      icon: const Icon(
                        Icons.calendar_month,
                      ),
                      label: Text(
                        formatDate(
                          fromDate,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : selectToDate,
                      icon: const Icon(
                        Icons.calendar_month,
                      ),
                      label: Text(
                        formatDate(
                          toDate,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: loading ? null : searchHistory,
                  icon: const Icon(
                    Icons.search,
                  ),
                  label: const Text(
                    'SEARCH HISTORY',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(15),
            child: CircularProgressIndicator(),
          ),
        Expanded(
          child: history.isEmpty
              ? const Center(
                  child: Text(
                    'No records found.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: history.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    final item = history[index];

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(
                        bottom: 10,
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(
                            Icons.wifi,
                          ),
                        ),
                        title: Text(
                          item.pin.isEmpty ? 'NO PIN' : item.pin,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${item.empCode} • '
                          '${item.name}\n'
                          'Room: ${item.room} • '
                          '${item.date} '
                          '${item.time}\n'
                          'By: ${item.issuedBy}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(
                          Icons.chevron_right,
                        ),
                        onTap: () {
                          openVoucher(
                            item,
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================
// HEADER
// ============================================================

Widget appHeader({
  required String title,
  required String subtitle,
  required IconData icon,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      18,
      18,
      18,
      16,
    ),
    decoration: const BoxDecoration(
      color: Color(0xFF087F5B),
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(20),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF087F5B),
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// DATE DISPLAY
// ============================================================

String formatDate(
  DateTime date,
) {
  return '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.year}';
}
