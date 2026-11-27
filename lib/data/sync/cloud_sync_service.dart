import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';

import '../../domain/enums.dart';
import '../database.dart';
import '../repositories/settings_repository.dart';

class SyncStatus {
  const SyncStatus({
    required this.connected,
    this.syncing = false,
    this.workspaceId,
    this.version = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool connected;
  final bool syncing;
  final String? workspaceId;
  final int version;
  final String? lastSyncedAt;
  final String? lastError;

  SyncStatus copyWith({
    bool? connected,
    bool? syncing,
    String? workspaceId,
    int? version,
    String? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncStatus(
      connected: connected ?? this.connected,
      syncing: syncing ?? this.syncing,
      workspaceId: workspaceId ?? this.workspaceId,
      version: version ?? this.version,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Multi-device cloud sync service connecting Android phones & Web via the
/// Render Node + PostgreSQL Sync API (`/api/sync/*`).
class CloudSyncService {
  CloudSyncService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const defaultServerUrl = 'https://barbell-therapy.onrender.com';

  static const _localOnlySettingKeys = {
    SettingKeys.syncEnabled,
    SettingKeys.syncServerUrl,
    SettingKeys.syncWorkspaceId,
    SettingKeys.syncPasscode,
    SettingKeys.syncVersion,
    SettingKeys.syncLastAt,
    SettingKeys.webThemePreset,
  };

  final _statusController =
      BehaviorSubject<SyncStatus>.seeded(const SyncStatus(connected: false));
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get currentStatus => _statusController.value;

  StreamSubscription<void>? _dbWatcher;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _applyingRemote = false;
  bool _dirty = false;
  bool _syncInFlight = false;

  String resolveDefaultUrl() {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http')) return origin;
    }
    return defaultServerUrl;
  }

  Future<void> init() async {
    final all = await _settings.getAll();
    final enabled = all[SettingKeys.syncEnabled] == '1';
    final ws = all[SettingKeys.syncWorkspaceId];
    final ver = int.tryParse(all[SettingKeys.syncVersion] ?? '0') ?? 0;
    final lastAt = all[SettingKeys.syncLastAt];

    _statusController.add(SyncStatus(
      connected: enabled && ws != null && ws.isNotEmpty,
      workspaceId: ws,
      version: ver,
      lastSyncedAt: lastAt,
    ));

    _startWatchers();

    if (enabled && ws != null && ws.isNotEmpty) {
      unawaited(syncNow(pushLocalChanges: false));
    }
  }

  void _startWatchers() {
    _dbWatcher?.cancel();
    _dbWatcher = _db
        .tableUpdates(TableUpdateQuery.onAllTables([
          _db.members,
          _db.plans,
          _db.addons,
          _db.subscriptions,
          _db.subscriptionAddons,
          _db.payments,
          _db.freezes,
          _db.templates,
          _db.messageLog,
        ]))
        .listen((_) {
      if (_applyingRemote) return;
      _dirty = true;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        if (currentStatus.connected) {
          unawaited(syncNow(pushLocalChanges: true));
        }
      });
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (currentStatus.connected && !_syncInFlight) {
        unawaited(syncNow(pushLocalChanges: _dirty));
      }
    });
  }

  void dispose() {
    _dbWatcher?.cancel();
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _statusController.close();
  }

  String _cleanUrl(String raw) {
    var u = raw.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  /// Connects to an existing or new Gym Sync workspace.
  Future<SyncStatus> connect({
    required String serverUrl,
    required String workspaceId,
    required String passcode,
  }) async {
    final url = _cleanUrl(serverUrl);
    final ws = workspaceId.trim().toLowerCase();
    final pass = passcode.trim();

    _statusController.add(currentStatus.copyWith(syncing: true, clearError: true));

    try {
      final resp = await http
          .post(
            Uri.parse('$url/api/sync/connect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'workspaceId': ws, 'passcode': pass}),
          )
          .timeout(const Duration(seconds: 25));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(body['error'] ?? 'Connection failed (${resp.statusCode})');
      }

      await _settings.setAll({
        SettingKeys.syncEnabled: '1',
        SettingKeys.syncServerUrl: url,
        SettingKeys.syncWorkspaceId: ws,
        SettingKeys.syncPasscode: pass,
      });

      final serverVersion = (body['version'] as num?)?.toInt() ?? 0;
      final serverPayload = body['payload'] as Map<String, dynamic>?;

      int finalVersion = serverVersion;
      if (serverPayload != null && serverVersion > 0) {
        // Merge local (if any members exist) with server payload, or apply server payload
        final local = await exportSnapshot();
        final localMembers = (local['members'] as List?) ?? const [];
        if (localMembers.isNotEmpty) {
          final merged = _mergeSnapshots(local, serverPayload);
          await applySnapshot(merged);
          finalVersion = await _pushPayload(url, ws, pass, serverVersion, merged);
        } else {
          await applySnapshot(serverPayload);
        }
      } else {
        // Server is brand new — push local database right away
        final local = await exportSnapshot();
        finalVersion = await _pushPayload(url, ws, pass, 0, local);
      }

      final nowIso = DateTime.now().toIso8601String();
      await _settings.setAll({
        SettingKeys.syncVersion: '$finalVersion',
        SettingKeys.syncLastAt: nowIso,
      });
      _dirty = false;

      final next = SyncStatus(
        connected: true,
        syncing: false,
        workspaceId: ws,
        version: finalVersion,
        lastSyncedAt: nowIso,
      );
      _statusController.add(next);
      return next;
    } catch (e) {
      final errStatus = currentStatus.copyWith(
        syncing: false,
        lastError: '$e'.replaceFirst('Exception: ', ''),
      );
      _statusController.add(errStatus);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _settings.setAll({
      SettingKeys.syncEnabled: '0',
    });
    _dirty = false;
    _statusController.add(const SyncStatus(connected: false));
  }

  /// Synchronizes local database with the Render server.
  Future<void> syncNow({bool pushLocalChanges = true}) async {
    if (_syncInFlight) return;
    final all = await _settings.getAll();
    if (all[SettingKeys.syncEnabled] != '1') return;

    final url = _cleanUrl(all[SettingKeys.syncServerUrl] ?? resolveDefaultUrl());
    final ws = all[SettingKeys.syncWorkspaceId] ?? '';
    final pass = all[SettingKeys.syncPasscode] ?? '';
    if (ws.isEmpty || pass.isEmpty) return;

    var localVersion = int.tryParse(all[SettingKeys.syncVersion] ?? '0') ?? 0;

    _syncInFlight = true;
    _statusController.add(currentStatus.copyWith(syncing: true, clearError: true));

    try {
      final pullResp = await http
          .post(
            Uri.parse('$url/api/sync/pull'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'workspaceId': ws, 'passcode': pass}),
          )
          .timeout(const Duration(seconds: 25));

      final pullBody = jsonDecode(pullResp.body) as Map<String, dynamic>;
      if (pullResp.statusCode != 200) {
        throw Exception(pullBody['error'] ?? 'Sync pull failed (${pullResp.statusCode})');
      }

      final serverVersion = (pullBody['version'] as num?)?.toInt() ?? 0;
      final serverPayload = pullBody['payload'] as Map<String, dynamic>?;

      if (serverVersion > localVersion && serverPayload != null) {
        if (pushLocalChanges || _dirty) {
          final local = await exportSnapshot();
          final merged = _mergeSnapshots(local, serverPayload);
          await applySnapshot(merged);
          localVersion =
              await _pushPayload(url, ws, pass, serverVersion, merged);
        } else {
          await applySnapshot(serverPayload);
          localVersion = serverVersion;
        }
      } else if (pushLocalChanges || _dirty) {
        final local = await exportSnapshot();
        localVersion = await _pushPayload(url, ws, pass, localVersion, local);
      }

      final nowIso = DateTime.now().toIso8601String();
      await _settings.setAll({
        SettingKeys.syncVersion: '$localVersion',
        SettingKeys.syncLastAt: nowIso,
      });
      _dirty = false;

      _statusController.add(SyncStatus(
        connected: true,
        syncing: false,
        workspaceId: ws,
        version: localVersion,
        lastSyncedAt: nowIso,
      ));
    } catch (e) {
      _statusController.add(currentStatus.copyWith(
        syncing: false,
        lastError: '$e'.replaceFirst('Exception: ', ''),
      ));
    } finally {
      _syncInFlight = false;
    }
  }

  Future<int> _pushPayload(
    String url,
    String ws,
    String pass,
    int baseVersion,
    Map<String, dynamic> payload,
  ) async {
    final resp = await http
        .post(
          Uri.parse('$url/api/sync/push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'workspaceId': ws,
            'passcode': pass,
            'baseVersion': baseVersion,
            'payload': payload,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 409 && body['payload'] != null) {
      final serverVer = (body['version'] as num?)?.toInt() ?? baseVersion;
      final merged =
          _mergeSnapshots(payload, body['payload'] as Map<String, dynamic>);
      await applySnapshot(merged);
      return _pushPayload(url, ws, pass, serverVer, merged);
    }
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Sync push failed (${resp.statusCode})');
    }
    return (body['version'] as num?)?.toInt() ?? (baseVersion + 1);
  }

  // ── Snapshot Export / Apply / Smart Merge ────────────────────────────────

  Future<Map<String, dynamic>> exportSnapshot() async {
    final members = await _db.select(_db.members).get();
    final plans = await _db.select(_db.plans).get();
    final addons = await _db.select(_db.addons).get();
    final subscriptions = await _db.select(_db.subscriptions).get();
    final subAddons = await _db.select(_db.subscriptionAddons).get();
    final payments = await _db.select(_db.payments).get();
    final freezes = await _db.select(_db.freezes).get();
    final messageLog = await _db.select(_db.messageLog).get();
    final templates = await _db.select(_db.templates).get();
    final settings = await _db.select(_db.settingsEntries).get();

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'plans': plans.map((p) => p.toJson()).toList(),
      'addons': addons.map((a) => a.toJson()).toList(),
      'members': members.map((m) => m.toJson()).toList(),
      'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
      'subscriptionAddons': subAddons.map((a) => a.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'freezes': freezes.map((f) => f.toJson()).toList(),
      'messageLog': messageLog.map((m) => m.toJson()).toList(),
      'templates': templates.map((t) => t.toJson()).toList(),
      'settings': settings
          .where((s) => !_localOnlySettingKeys.contains(s.key))
          .map((s) => s.toJson())
          .toList(),
    };
  }

  Future<void> applySnapshot(Map<String, dynamic> data) async {
    _applyingRemote = true;
    try {
      await _db.transaction(() async {
        await _db.delete(_db.messageLog).go();
        await _db.delete(_db.freezes).go();
        await _db.delete(_db.payments).go();
        await _db.delete(_db.subscriptionAddons).go();
        await _db.delete(_db.subscriptions).go();
        await _db.delete(_db.members).go();
        await _db.delete(_db.plans).go();
        await _db.delete(_db.addons).go();
        await _db.delete(_db.templates).go();

        for (final p in (data['plans'] as List? ?? const [])) {
          final m = p as Map<String, dynamic>;
          await _db.into(_db.plans).insert(PlansCompanion(
                id: Value(m['id'] as int),
                name: Value(m['name'] as String),
                durationMonths: Value(m['durationMonths'] as int),
                price: Value(m['price'] as int),
                isActive: Value((m['isActive'] as bool?) ?? true),
                sortOrder: Value((m['sortOrder'] as int?) ?? 0),
              ));
        }

        for (final a in (data['addons'] as List? ?? const [])) {
          final m = a as Map<String, dynamic>;
          await _db.into(_db.addons).insert(AddonsCompanion(
                id: Value(m['id'] as int),
                name: Value(m['name'] as String),
                price: Value(m['price'] as int),
                billing: Value(AddonBilling.values.firstWhere(
                    (e) => e.name == m['billing'],
                    orElse: () => AddonBilling.one_time)),
                isActive: Value((m['isActive'] as bool?) ?? true),
              ));
        }

        for (final row in (data['members'] as List? ?? const [])) {
          final m = row as Map<String, dynamic>;
          await _db.into(_db.members).insert(MembersCompanion(
                id: Value(m['id'] as int),
                memberCode: Value(m['memberCode'] as String),
                name: Value(m['name'] as String),
                phone: Value(m['phone'] as String),
                age: Value(m['age'] as int?),
                gender: Value(m['gender'] as String?),
                photoPath: Value(m['photoPath'] as String?),
                joinedOn: Value(m['joinedOn'] as String),
                notes: Value(m['notes'] as String?),
                isArchived: Value((m['isArchived'] as bool?) ?? false),
                createdAt: Value(DateTime.parse(m['createdAt'] as String)),
              ));
        }

        for (final row in (data['subscriptions'] as List? ?? const [])) {
          final s = row as Map<String, dynamic>;
          await _db.into(_db.subscriptions).insert(SubscriptionsCompanion(
                id: Value(s['id'] as int),
                memberId: Value(s['memberId'] as int),
                planId: Value(s['planId'] as int),
                planNameSnapshot: Value(s['planNameSnapshot'] as String),
                planPriceSnapshot: Value(s['planPriceSnapshot'] as int),
                startDate: Value(s['startDate'] as String),
                originalEndDate: Value(s['originalEndDate'] as String),
                endDate: Value(s['endDate'] as String),
                admissionFee: Value((s['admissionFee'] as int?) ?? 0),
                discountType: Value(DiscountType.values.firstWhere(
                    (e) => e.name == s['discountType'],
                    orElse: () => DiscountType.none)),
                discountValue: Value((s['discountValue'] as int?) ?? 0),
                totalAmount: Value(s['totalAmount'] as int),
                statusOverride: Value(s['statusOverride'] as String?),
                cancelReason: Value(s['cancelReason'] as String?),
                createdAt: Value(DateTime.parse(s['createdAt'] as String)),
              ));
        }

        for (final row in (data['subscriptionAddons'] as List? ?? const [])) {
          final sa = row as Map<String, dynamic>;
          await _db.into(_db.subscriptionAddons).insert(SubscriptionAddonsCompanion(
                id: Value(sa['id'] as int),
                subscriptionId: Value(sa['subscriptionId'] as int),
                addonId: Value(sa['addonId'] as int),
                nameSnapshot: Value(sa['nameSnapshot'] as String),
                priceSnapshot: Value(sa['priceSnapshot'] as int),
              ));
        }

        for (final row in (data['payments'] as List? ?? const [])) {
          final py = row as Map<String, dynamic>;
          await _db.into(_db.payments).insert(PaymentsCompanion(
                id: Value(py['id'] as int),
                subscriptionId: Value(py['subscriptionId'] as int?),
                memberId: Value(py['memberId'] as int),
                amount: Value(py['amount'] as int),
                mode: Value(PaymentMode.values.firstWhere(
                    (e) => e.name == py['mode'],
                    orElse: () => PaymentMode.cash)),
                paidOn: Value(py['paidOn'] as String),
                note: Value(py['note'] as String?),
                voided: Value((py['voided'] as bool?) ?? false),
                voidReason: Value(py['voidReason'] as String?),
                voidedAt: Value(py['voidedAt'] != null
                    ? DateTime.parse(py['voidedAt'] as String)
                    : null),
                createdAt: Value(DateTime.parse(py['createdAt'] as String)),
              ));
        }

        for (final row in (data['freezes'] as List? ?? const [])) {
          final f = row as Map<String, dynamic>;
          await _db.into(_db.freezes).insert(FreezesCompanion(
                id: Value(f['id'] as int),
                subscriptionId: Value(f['subscriptionId'] as int),
                memberId: Value(f['memberId'] as int),
                freezeStart: Value(f['freezeStart'] as String),
                freezeEnd: Value(f['freezeEnd'] as String),
                days: Value(f['days'] as int),
                reason: Value(f['reason'] as String?),
                endedEarlyOn: Value(f['endedEarlyOn'] as String?),
                createdAt: Value(DateTime.parse(f['createdAt'] as String)),
              ));
        }

        for (final row in (data['templates'] as List? ?? const [])) {
          final t = row as Map<String, dynamic>;
          await _db.into(_db.templates).insert(TemplatesCompanion(
                id: Value(t['id'] as int),
                key: Value(t['key'] as String),
                language: Value(t['language'] as String),
                title: Value(t['title'] as String?),
                body: Value(t['body'] as String),
                isDefault: Value((t['isDefault'] as bool?) ?? true),
              ));
        }

        for (final row in (data['messageLog'] as List? ?? const [])) {
          final ml = row as Map<String, dynamic>;
          await _db.into(_db.messageLog).insert(MessageLogCompanion(
                id: Value(ml['id'] as int),
                memberId: Value(ml['memberId'] as int?),
                type: Value(MessageType.values.firstWhere(
                    (e) => e.name == ml['type'],
                    orElse: () => MessageType.announcement)),
                subscriptionId: Value(ml['subscriptionId'] as int?),
                sentAt: Value(DateTime.parse(ml['sentAt'] as String)),
                templateId: Value(ml['templateId'] as int?),
                channel: Value((ml['channel'] as String?) ?? 'whatsapp'),
                campaignTitle: Value(ml['campaignTitle'] as String?),
              ));
        }

        for (final st in (data['settings'] as List? ?? const [])) {
          final map = st as Map<String, dynamic>;
          final key = map['key'] as String;
          if (_localOnlySettingKeys.contains(key)) continue;
          await _db.into(_db.settingsEntries).insertOnConflictUpdate(
                SettingsEntriesCompanion(
                  key: Value(key),
                  value: Value(map['value'] as String?),
                ),
              );
        }
      });
    } finally {
      _applyingRemote = false;
    }
  }

  /// Merges local and remote snapshots by natural keys when both devices edited
  /// offline, so neither device's new members/payments are lost.
  Map<String, dynamic> _mergeSnapshots(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    List<Map<String, dynamic>> mergeByKey(
      List? a,
      List? b,
      String Function(Map<String, dynamic>) keyOf,
    ) {
      final map = <String, Map<String, dynamic>>{};
      for (final item in (b ?? const [])) {
        final m = Map<String, dynamic>.from(item as Map);
        map[keyOf(m)] = m;
      }
      for (final item in (a ?? const [])) {
        final m = Map<String, dynamic>.from(item as Map);
        map.putIfAbsent(keyOf(m), () => m);
      }
      return map.values.toList();
    }

    final mergedSettings = <String, Map<String, dynamic>>{};
    for (final s in (remote['settings'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(s as Map);
      mergedSettings[m['key'] as String] = m;
    }
    for (final s in (local['settings'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(s as Map);
      final k = m['key'] as String;
      if (k == SettingKeys.memberSeq) {
        final rSeq = int.tryParse('${mergedSettings[k]?['value'] ?? 0}') ?? 0;
        final lSeq = int.tryParse('${m['value'] ?? 0}') ?? 0;
        if (lSeq > rSeq) mergedSettings[k] = m;
      } else {
        mergedSettings.putIfAbsent(k, () => m);
      }
    }

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'plans': mergeByKey(
        local['plans'] as List?,
        remote['plans'] as List?,
        (m) => '${m['id']}:${m['name']}',
      ),
      'addons': mergeByKey(
        local['addons'] as List?,
        remote['addons'] as List?,
        (m) => '${m['id']}:${m['name']}',
      ),
      'members': mergeByKey(
        local['members'] as List?,
        remote['members'] as List?,
        (m) => '${m['memberCode']}',
      ),
      'subscriptions': mergeByKey(
        local['subscriptions'] as List?,
        remote['subscriptions'] as List?,
        (m) => '${m['id']}:${m['createdAt']}',
      ),
      'subscriptionAddons': mergeByKey(
        local['subscriptionAddons'] as List?,
        remote['subscriptionAddons'] as List?,
        (m) => '${m['id']}:${m['subscriptionId']}:${m['addonId']}',
      ),
      'payments': mergeByKey(
        local['payments'] as List?,
        remote['payments'] as List?,
        (m) => '${m['id']}:${m['createdAt']}',
      ),
      'freezes': mergeByKey(
        local['freezes'] as List?,
        remote['freezes'] as List?,
        (m) => '${m['id']}:${m['createdAt']}',
      ),
      'templates': mergeByKey(
        local['templates'] as List?,
        remote['templates'] as List?,
        (m) => '${m['key']}:${m['language']}',
      ),
      'messageLog': mergeByKey(
        local['messageLog'] as List?,
        remote['messageLog'] as List?,
        (m) => '${m['id']}:${m['sentAt']}',
      ),
      'settings': mergedSettings.values.toList(),
    };
  }
}
