import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/enums.dart';
import 'seed_data.dart';

/// Date-only strings use `yyyy-MM-dd`; timestamps are stored as text by the
/// drift `store_date_time_values_as_text` build option (see build.yaml).

part 'database.g.dart';


@TableIndex(name: 'idx_members_phone', columns: {#phone})
@TableIndex(name: 'idx_members_name', columns: {#name})
class Members extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get memberCode => text().unique()(); // GYM-0001
  TextColumn get name => text()();
  TextColumn get phone => text()(); // normalized 10 digits
  IntColumn get age => integer().nullable()();
  TextColumn get gender => text().nullable()(); // Male / Female / Other
  TextColumn get photoPath => text().nullable()();
  TextColumn get joinedOn => text()(); // yyyy-MM-dd
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

class Plans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get durationMonths => integer()();
  IntColumn get price => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Addons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get price => integer()();
  TextColumn get billing => textEnum<AddonBilling>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// One row per membership period; renewals create new rows.
@TableIndex(name: 'idx_subscriptions_member', columns: {#memberId})
@TableIndex(name: 'idx_subscriptions_end_date', columns: {#endDate})
class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get planId => integer().references(Plans, #id)();
  TextColumn get planNameSnapshot => text()();
  IntColumn get planPriceSnapshot => integer()();
  TextColumn get startDate => text()(); // yyyy-MM-dd
  TextColumn get originalEndDate => text()(); // saved at creation
  TextColumn get endDate => text()(); // shifts with freezes
  IntColumn get admissionFee => integer().withDefault(const Constant(0))();
  TextColumn get discountType => textEnum<DiscountType>()();
  IntColumn get discountValue => integer().withDefault(const Constant(0))();
  IntColumn get totalAmount => integer()();
  TextColumn get statusOverride => text().nullable()(); // 'cancelled'
  TextColumn get cancelReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

class SubscriptionAddons extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get subscriptionId => integer().references(Subscriptions, #id)();
  IntColumn get addonId => integer().references(Addons, #id)();
  TextColumn get nameSnapshot => text()();
  IntColumn get priceSnapshot => integer()();
}

/// Payments are voided (soft-delete with reason), never edited silently.
@TableIndex(name: 'idx_payments_paid_on', columns: {#paidOn})
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get subscriptionId => integer().nullable().references(Subscriptions, #id)();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get amount => integer()();
  TextColumn get mode => textEnum<PaymentMode>()();
  TextColumn get paidOn => text()(); // yyyy-MM-dd
  TextColumn get note => text().nullable()();
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().nullable()();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

class Freezes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get subscriptionId => integer().references(Subscriptions, #id)();
  IntColumn get memberId => integer().references(Members, #id)();
  TextColumn get freezeStart => text()(); // yyyy-MM-dd
  TextColumn get freezeEnd => text()(); // yyyy-MM-dd
  IntColumn get days => integer()();
  TextColumn get reason => text().nullable()();
  TextColumn get endedEarlyOn => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@TableIndex(name: 'idx_checkins_time', columns: {#checkedInAt})
class Checkins extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  DateTimeColumn get checkedInAt => dateTime()();
  IntColumn get subscriptionId => integer().nullable().references(Subscriptions, #id)();
  BoolColumn get wasExpired => boolean().withDefault(const Constant(false))();
}

class MessageLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().nullable().references(Members, #id)();
  TextColumn get type => textEnum<MessageType>()();
  IntColumn get subscriptionId => integer().nullable().references(Subscriptions, #id)();
  DateTimeColumn get sentAt => dateTime()();
  IntColumn get templateId => integer().nullable()();
  TextColumn get channel => text().withDefault(const Constant('whatsapp'))();
  /// Announcement campaign title, used to track bulk-send progress.
  TextColumn get campaignTitle => text().nullable()();
}

class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text()(); // matches MessageType names
  TextColumn get language => text()(); // 'en' / 'te'
  TextColumn get title => text().nullable()(); // used by announcement starters
  TextColumn get body => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(true))();
}

/// Key-value settings store.
class SettingsEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Members,
    Plans,
    Addons,
    Subscriptions,
    SubscriptionAddons,
    Payments,
    Freezes,
    Checkins,
    MessageLog,
    Templates,
    SettingsEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Web runtime options; only used when compiled for the browser.
  static final _webOptions = DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  );

  /// Web: serves the WASM assets from the site root (must ship
  /// `web/sqlite3.wasm` and `web/drift_worker.js` with the deployment).
  /// Ignored on native platforms.
  AppDatabase() : super(driftDatabase(name: 'gymdesk', web: _webOptions));

  // Test-only constructor to inject a custom query executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaults(this);
        },
      );
}

