import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';

/// Seed data inserted on first database creation (spec 4 + 7).
///
/// Plans get placeholder prices that the owner edits during onboarding.
/// Templates ship in English and Telugu.

const List<SeedPlan> defaultPlans = [
  SeedPlan(name: 'Monthly', durationMonths: 1, price: 1000, sortOrder: 0),
  SeedPlan(name: 'Quarterly', durationMonths: 3, price: 2700, sortOrder: 1),
  SeedPlan(name: 'Half-yearly', durationMonths: 6, price: 5000, sortOrder: 2),
  SeedPlan(name: 'Yearly', durationMonths: 12, price: 9000, sortOrder: 3),
];

const List<SeedAddon> defaultAddons = [
  SeedAddon(name: 'Personal Training', price: 2000, billing: 'one_time'),
  SeedAddon(name: 'Diet Plan', price: 1000, billing: 'one_time'),
];

class SeedPlan {
  const SeedPlan({
    required this.name,
    required this.durationMonths,
    required this.price,
    required this.sortOrder,
  });

  final String name;
  final int durationMonths;
  final int price;
  final int sortOrder;
}

class SeedAddon {
  const SeedAddon({
    required this.name,
    required this.price,
    required this.billing,
  });

  final String name;
  final int price;
  final String billing;
}

class SeedTemplate {
  const SeedTemplate({
    required this.key,
    required this.language,
    required this.body,
    this.title,
  });

  final String key;
  final String language;
  final String body;
  final String? title;
}

const List<SeedTemplate> defaultTemplates = [
  // ── English ──────────────────────────────────────────────────────────────
  SeedTemplate(
    key: 'welcome',
    language: 'en',
    body: 'Hi {name}, welcome to {gym_name}! 💪 Your {plan} membership is '
        'active from {start_date} to {end_date}. Member ID: {member_code}. '
        'See you at the gym!',
  ),
  SeedTemplate(
    key: 'expiry_7',
    language: 'en',
    body: 'Hi {name}, your {gym_name} membership ends on {end_date} (in 7 '
        'days). Renew early to keep your routine going! 💪',
  ),
  SeedTemplate(
    key: 'expiry_3',
    language: 'en',
    body: 'Hi {name}, your {gym_name} membership is going to end in 3 days, '
        'on {end_date}. Please renew before the deadline to avoid any break.',
  ),
  SeedTemplate(
    key: 'expiry_1',
    language: 'en',
    body: 'Hi {name}, your membership ends tomorrow ({end_date}). Please '
        'renew today so you don\'t miss a workout. Thank you! – {gym_name}',
  ),
  SeedTemplate(
    key: 'expiry_0',
    language: 'en',
    body: 'Hi {name}, your {gym_name} membership expires today. Renew now to '
        'continue training without a break.',
  ),
  SeedTemplate(
    key: 'expired_3',
    language: 'en',
    body: 'Hi {name}, your membership expired on {end_date}. We\'d love to '
        'have you back! Renew this week to continue. – {gym_name}',
  ),
  SeedTemplate(
    key: 'expired_7',
    language: 'en',
    body: 'Hi {name}, we miss you at {gym_name}! Your membership ended on '
        '{end_date}. Come back and restart your journey. Call us: {gym_phone}',
  ),
  SeedTemplate(
    key: 'dues_weekly',
    language: 'en',
    body: 'Hi {name}, a gentle reminder: ₹{amount_due} is pending for your '
        '{gym_name} membership. Please pay at the desk or via our QR. '
        'Thank you!',
  ),
  SeedTemplate(
    key: 'receipt',
    language: 'en',
    body: 'Hi {name}, we received ₹{amount_paid} on {paid_on}. Balance due: '
        '₹{amount_due}. Thank you! – {gym_name}',
  ),
  SeedTemplate(
    key: 'inactivity',
    language: 'en',
    body: 'Hi {name}, we haven\'t seen you at {gym_name} in {days_away} '
        'days. Everything okay? Your membership runs till {end_date}, so '
        'come in and get a workout done! 💪',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'en',
    title: 'Holiday closure',
    body: 'Hi {name}, {gym_name} will be closed on {holiday_date} for the '
        'holiday. Regular timings resume the next day. Happy holidays! 🎉',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'en',
    title: 'Timing change',
    body: 'Hi {name}, from {new_start_date} our timings at {gym_name} change '
        'to {new_timings}. See you at your usual slot! 💪',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'en',
    title: 'New equipment',
    body: 'Hi {name}, new equipment has arrived at {gym_name}! Come try it '
        'out in your next session. 💪',
  ),

  // ── Telugu ───────────────────────────────────────────────────────────────
  SeedTemplate(
    key: 'welcome',
    language: 'te',
    body: 'నమస్కారం {name} గారు, {gym_name} కి స్వాగతం! 💪 మీ {plan} '
        'మెంబర్‌షిప్ {start_date} నుండి {end_date} వరకు చురుకుగా ఉంటుంది. '
        'మెంబర్ ID: {member_code}. జిమ్‌లో కలుద్దాం!',
  ),
  SeedTemplate(
    key: 'expiry_7',
    language: 'te',
    body: 'నమస్కారం {name} గారు, మీ {gym_name} మెంబర్‌షిప్ 7 రోజుల్లో, అంటే '
        '{end_date} న ముగుస్తుంది. మీ రొటీన్ తప్పకుండా ఉండాలంటే ముందస్తుగా '
        'రెన్యూ చేసుకోండి! 💪',
  ),
  SeedTemplate(
    key: 'expiry_3',
    language: 'te',
    body: 'నమస్కారం {name} గారు, మీ {gym_name} మెంబర్‌షిప్ 3 రోజుల్లో, అంటే '
        '{end_date} న ముగుస్తుంది. దయచేసి గడువులోపు రెన్యూ చేసుకోండి. '
        'ధన్యవాదాలు!',
  ),
  SeedTemplate(
    key: 'expiry_1',
    language: 'te',
    body: 'నమస్కారం {name} గారు, మీ మెంబర్‌షిప్ రేపే ({end_date}) ముగుస్తుంది. '
        'వర్కౌట్ మిస్ అయ్యేలా కాకుండా ఈరోజే రెన్యూ చేసుకోండి. ధన్యవాదాలు! '
        '– {gym_name}',
  ),
  SeedTemplate(
    key: 'expiry_0',
    language: 'te',
    body: 'నమస్కారం {name} గారు, మీ {gym_name} మెంబర్‌షిప్ ఈరోజే ముగుస్తుంది. '
        'బ్రేక్ లేకుండా ట్రైనింగ్ కొనసాగించడానికి ఇప్పుడే రెన్యూ చేసుకోండి.',
  ),
  SeedTemplate(
    key: 'expired_3',
    language: 'te',
    body: 'నమస్కారం {name} గారు, మీ మెంబర్‌షిప్ {end_date} న ముగిసింది. మళ్లీ '
        'మిమ్మల్ని చూడాలని ఉంది! ఈ వారంలో రెన్యూ చేసుకుని కొనసాగించండి. '
        '– {gym_name}',
  ),
  SeedTemplate(
    key: 'expired_7',
    language: 'te',
    body: 'నమస్కారం {name} గారు, {gym_name} లో మిమ్మల్ని చాలా రోజులుగా '
        'చూడడం లేదు! మీ మెంబర్‌షిప్ {end_date} న ముగిసింది. మళ్లీ వచ్చి మీ '
        'జర్నీ మొదలుపెట్టండి. కాల్ చేయండి: {gym_phone}',
  ),
  SeedTemplate(
    key: 'dues_weekly',
    language: 'te',
    body: 'నమస్కారం {name} గారు, ఒక చిన్న రిమైండర్: మీ {gym_name} '
        'మెంబర్‌షిప్ కు ₹{amount_due} బకాయి ఉంది. దయచేసి డెస్క్ దగ్గర లేదా '
        'మా QR ద్వారా చెల్లించండి. ధన్యవాదాలు!',
  ),
  SeedTemplate(
    key: 'receipt',
    language: 'te',
    body: 'నమస్కారం {name} గారు, {paid_on} న ₹{amount_paid} అందింది. బకాయి: '
        '₹{amount_due}. ధన్యవాదాలు! – {gym_name}',
  ),
  SeedTemplate(
    key: 'inactivity',
    language: 'te',
    body: 'నమస్కారం {name} గారు, {gym_name} కి మీరు {days_away} రోజులుగా రావడం '
        'లేదు. అంతా బాగానే ఉందా? మీ మెంబర్‌షిప్ {end_date} వరకు ఉంది, త్వరగా '
        'వచ్చి ఒక వర్కౌట్ చేయండి! 💪',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'te',
    title: 'Holiday closure',
    body: 'నమస్కారం {name} గారు, సెలవు కారణంగా {gym_name} {holiday_date} న '
        'మూసివేయబడుతుంది. మర్నాడు మామూలు టైమింగ్స్ ఉంటాయి. సెలవు శుభాకాంక్షలు! 🎉',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'te',
    title: 'Timing change',
    body: 'నమస్కారం {name} గారు, {new_start_date} నుండి {gym_name} టైమింగ్స్ '
        '{new_timings} కి మారుతాయి. మీ స్లాట్‌లో కలుద్దాం! 💪',
  ),
  SeedTemplate(
    key: 'announcement',
    language: 'te',
    title: 'New equipment',
    body: 'నమస్కారం {name} గారు, {gym_name} కి కొత్త ఎక్విప్‌మెంట్ వచ్చింది! '
        'త్వరలో వచ్చి ట్రై చేయండి. 💪',
  ),
];

/// Inserts seed rows when the tables are empty. Runs inside database creation.
Future<void> seedDefaults(AppDatabase db) async {
  if (await db.select(db.plans).get().then((rows) => rows.isEmpty)) {
    await db.batch((batch) {
      batch.insertAll(
        db.plans,
        defaultPlans
            .map((p) => PlansCompanion.insert(
                  name: p.name,
                  durationMonths: p.durationMonths,
                  price: p.price,
                  sortOrder: Value(p.sortOrder),
                ))
            .toList(),
      );
    });
  }

  if (await db.select(db.addons).get().then((rows) => rows.isEmpty)) {
    await db.batch((batch) {
      batch.insertAll(
        db.addons,
        defaultAddons
            .map((a) => AddonsCompanion.insert(
                  name: a.name,
                  price: a.price,
                  billing: a.billing == 'per_plan'
                      ? AddonBilling.per_plan
                      : AddonBilling.one_time,
                ))
            .toList(),
      );
    });
  }

  if (await db.select(db.templates).get().then((rows) => rows.isEmpty)) {
    await db.batch((batch) {
      batch.insertAll(
        db.templates,
        defaultTemplates
            .map((t) => TemplatesCompanion.insert(
                  key: t.key,
                  language: t.language,
                  body: t.body,
                  title: Value(t.title),
                ))
            .toList(),
      );
    });
  }
}
