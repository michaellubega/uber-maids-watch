import 'dart:convert';

/// A signed-in user as returned by `/api/auth/me/`.
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.phoneNumber = '',
    this.capabilities = const <String, dynamic>{},
  });

  final String id;
  final String username;
  final String displayName;
  final String role;
  final String phoneNumber;
  final Map<String, dynamic> capabilities;

  bool get isStaff => const {
        'ADMIN',
        'OPERATIONS',
        'VERIFICATION',
        'CUSTOMER_CARE',
        'FINANCE',
        'READONLY',
      }.contains(role);

  bool get isAdmin => role == 'ADMIN';

  factory AppUser.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic> capabilities = const <String, dynamic>{},
  }) {
    return AppUser(
      id: '${json['id'] ?? ''}',
      username: '${json['username'] ?? ''}',
      displayName: '${json['display_name'] ?? json['username'] ?? ''}',
      role: '${json['role'] ?? 'READONLY'}',
      phoneNumber: '${json['phone_number'] ?? ''}',
      capabilities: capabilities,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'role': role,
        'phone_number': phoneNumber,
        'capabilities': capabilities,
      };

  factory AppUser.fromCache(Map<String, dynamic> json) => AppUser(
        id: '${json['id'] ?? ''}',
        username: '${json['username'] ?? ''}',
        displayName: '${json['display_name'] ?? json['username'] ?? ''}',
        role: '${json['role'] ?? 'READONLY'}',
        phoneNumber: '${json['phone_number'] ?? ''}',
        capabilities: Map<String, dynamic>.from(
          (json['capabilities'] as Map?) ?? const <String, dynamic>{},
        ),
      );
}

/// Device-persisted session.  Tokens are kept in the platform's secure store.
class Session {
  const Session({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.savedAt,
  });

  final AppUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime savedAt;

  Session copyWith({
    AppUser? user,
    String? accessToken,
    String? refreshToken,
    DateTime? savedAt,
  }) {
    return Session(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'access': accessToken,
        'refresh': refreshToken,
        'saved_at': savedAt.toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        user: AppUser.fromCache(
          Map<String, dynamic>.from((json['user'] as Map?) ?? const {}),
        ),
        accessToken: '${json['access'] ?? ''}',
        refreshToken: '${json['refresh'] ?? ''}',
        savedAt: DateTime.tryParse('${json['saved_at']}') ?? DateTime.now(),
      );

  static Session? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Session.fromJson(decoded);
      if (decoded is Map) {
        return Session.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Corrupt or legacy payload: treat as signed out.
    }
    return null;
  }

  String encode() => jsonEncode(toJson());
}

/// A record mirrored from the server (or created locally while offline).
class CachedRecord {
  CachedRecord({
    required this.entity,
    required this.id,
    required this.data,
    this.changeSeq = 0,
    this.deleted = false,
    this.dirty = false,
    this.baseVersion = 0,
    this.serverData,
    this.serverVersion,
  });

  final String entity;
  final String id;
  Map<String, dynamic> data;
  int changeSeq;
  bool deleted;
  bool dirty;
  int baseVersion;
  Map<String, dynamic>? serverData;
  int? serverVersion;

  bool get hasConflict => serverData != null;

  String get cacheKey => '$entity:$id';

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'id': id,
        'data': data,
        'change_seq': changeSeq,
        'deleted': deleted,
        'dirty': dirty,
        'base_version': baseVersion,
        if (serverData != null) 'server_data': serverData,
        if (serverVersion != null) 'server_version': serverVersion,
      };

  factory CachedRecord.fromJson(Map<String, dynamic> json) => CachedRecord(
        entity: '${json['entity'] ?? ''}',
        id: '${json['id'] ?? ''}',
        data: Map<String, dynamic>.from(
          (json['data'] as Map?) ?? const <String, dynamic>{},
        ),
        changeSeq: (json['change_seq'] as num?)?.toInt() ?? 0,
        deleted: json['deleted'] == true,
        dirty: json['dirty'] == true,
        baseVersion: (json['base_version'] as num?)?.toInt() ?? 0,
        serverData: json['server_data'] is Map
            ? Map<String, dynamic>.from(json['server_data'] as Map)
            : null,
        serverVersion: (json['server_version'] as num?)?.toInt(),
      );
}

/// One queued device write waiting to be pushed to the server.
class OutboxMutation {
  OutboxMutation({
    required this.mutationId,
    required this.entity,
    required this.id,
    required this.operation,
    required this.baseVersion,
    required this.data,
    required this.createdAt,
    this.status = OutboxStatus.pending,
    this.error,
    this.serverRecord,
  });

  final String mutationId;
  final String entity;
  final String id;
  final String operation;
  int baseVersion;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  String status;
  String? error;
  Map<String, dynamic>? serverRecord;

  bool get isPending => status == OutboxStatus.pending;

  Map<String, dynamic> toPayload() => {
        'mutation_id': mutationId,
        'entity': entity,
        'id': id,
        'operation': operation,
        'base_version': baseVersion,
        'data': data,
      };

  Map<String, dynamic> toJson() => {
        ...toPayload(),
        'created_at': createdAt.toIso8601String(),
        'status': status,
        if (error != null) 'error': error,
        if (serverRecord != null) 'server_record': serverRecord,
      };

  factory OutboxMutation.fromJson(Map<String, dynamic> json) => OutboxMutation(
        mutationId: '${json['mutation_id'] ?? ''}',
        entity: '${json['entity'] ?? ''}',
        id: '${json['id'] ?? ''}',
        operation: '${json['operation'] ?? 'upsert'}',
        baseVersion: (json['base_version'] as num?)?.toInt() ?? 0,
        data: Map<String, dynamic>.from(
          (json['data'] as Map?) ?? const <String, dynamic>{},
        ),
        createdAt:
            DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
        status: '${json['status'] ?? OutboxStatus.pending}',
        error: json['error']?.toString(),
        serverRecord: json['server_record'] is Map
            ? Map<String, dynamic>.from(json['server_record'] as Map)
            : null,
      );
}

class OutboxStatus {
  static const pending = 'pending';
  static const conflict = 'conflict';
  static const rejected = 'rejected';
}

/// Fields the server accepts for each syncable entity.  Read-only and
/// server-computed fields are stripped before a mutation leaves the device.
const Map<String, Set<String>> writableFields = {
  'worker': {
    'full_name',
    'phone',
    'area',
    'date_of_birth',
    'national_id_type',
    'national_id_number',
    'emergency_contact_name',
    'emergency_contact_phone',
    'skills',
    'languages',
    'service_categories',
    'experience_years',
    'expected_salary_ugx',
    'availability',
    'status',
    'verification_status',
    'exception_reason',
    'notes',
    'user',
  },
  'client': {
    'full_name',
    'phone',
    'email',
    'area',
    'preferred_contact',
    'notes',
    'status',
    'user',
  },
  'service': {
    'name',
    'category',
    'description',
    'pricing_type',
    'price_min_ugx',
    'price_max_ugx',
    'requirements',
    'active',
    'public_visibility',
  },
  'booking': {
    'client',
    'service',
    'requested_start_date',
    'location',
    'schedule',
    'requirements',
    'budget_ugx',
    'special_instructions',
    'status',
    'assigned_staff_name',
    'confirmed_at',
  },
  'placement': {
    'booking',
    'client',
    'worker',
    'start_date',
    'terms',
    'status',
    'guarantee_days',
    'responsible_staff_name',
    'client_acknowledgement',
    'notes',
  },
  'follow_up': {
    'placement',
    'due_date',
    'completed_at',
    'staff_name',
    'contact_method',
    'outcome',
    'satisfaction',
    'notes',
    'next_follow_up_date',
  },
  'incident': {
    'placement',
    'category',
    'description',
    'status',
    'notes',
  },
  'replacement_case': {
    'placement',
    'issue_reported_date',
    'problem_category',
    'description',
  },
  'payment': {
    'client',
    'booking',
    'placement',
    'amount_ugx',
    'currency',
    'payment_method',
    'reference',
    'status',
    'notes',
  },
};

Map<String, dynamic> payloadForEntity(String entity, Map<String, dynamic> data) {
  final allowed = writableFields[entity];
  final cleaned = <String, dynamic>{};
  for (final entry in data.entries) {
    if (allowed == null || allowed.contains(entry.key)) {
      cleaned[entry.key] = entry.value;
    }
  }
  return cleaned;
}

/// Reads the `exp` claim from a JWT without verifying it (the server is the
/// only verifier).  Used to refresh tokens before they expire.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = jsonDecode(payload);
    final exp = decoded is Map ? decoded['exp'] : null;
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
  } catch (_) {
    // Malformed token: let the server reject it.
  }
  return null;
}

String asString(dynamic value) => value?.toString() ?? '';

double asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
