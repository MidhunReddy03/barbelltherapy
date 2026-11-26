import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/domain/enums.dart';
import 'package:gymdesk/domain/reminder_engine.dart';

void main() {
  const allOffsets = [7, 3, 1, 0, -3, -7];

  ReminderSelection? select({
    required int daysLeft,
    bool frozen = false,
    bool upcoming = false,
    bool alreadyRenewed = false,
    Set<MessageType> sent = const {},
    List<int> offsets = allOffsets,
    int lookback = 3,
  }) {
    return ReminderEngine.select(
      daysLeft: daysLeft,
      frozen: frozen,
      upcoming: upcoming,
      alreadyRenewed: alreadyRenewed,
      sentTypes: sent,
      enabledOffsets: offsets,
      lookbackDays: lookback,
    );
  }

  test('exact day matches its rule', () {
    expect(select(daysLeft: 7)!.type, MessageType.expiry_7);
    expect(select(daysLeft: 3)!.type, MessageType.expiry_3);
    expect(select(daysLeft: 1)!.type, MessageType.expiry_1);
    expect(select(daysLeft: 0)!.type, MessageType.expiry_0);
    expect(select(daysLeft: -3)!.type, MessageType.expired_3);
    expect(select(daysLeft: -7)!.type, MessageType.expired_7);
  });

  test('no reminder far outside the offsets and lookback window', () {
    expect(select(daysLeft: 20), isNull);
    expect(select(daysLeft: 8), isNull); // 7-day rule not reached yet
    expect(select(daysLeft: -20), isNull);
  });

  test('missed 7-day rule is picked up up to 3 days late', () {
    // Owner didn't open the app on days 7/6/5; on day 4 the nearest missed
    // rule (expiry_7, 3 days back) still shows so nothing is skipped.
    final r = select(daysLeft: 4);
    expect(r!.type, MessageType.expiry_7);
    expect(r.offset, 7);
  });

  test('missed day is picked up within the lookback window', () {
    // Owner didn't open the app on the 3-day day; 2 days later (daysLeft=1)
    // the nearest missed rule is expiry_3.
    final r = select(daysLeft: 1, sent: {MessageType.expiry_1});
    expect(r!.type, MessageType.expiry_3);
    expect(r.offset, 3);
  });

  test('expired lookback: daysLeft=-5 shows expired_3 (missed by 2 days)', () {
    expect(select(daysLeft: -5, sent: {})!.type, MessageType.expired_3);
  });

  test('only the most relevant rule is returned per member', () {
    final r = select(daysLeft: 3, sent: {});
    expect(r!.type, MessageType.expiry_3);
  });

  test('expiry_3 already sent -> nothing until the 1-day rule fires', () {
    // At day 3 the next rule (expiry_1) hasn't been reached yet; the member
    // already got the 3-day message.
    expect(select(daysLeft: 3, sent: {MessageType.expiry_3}), isNull);
  });

  test('all expiry rules sent -> no reminder', () {
    expect(
      select(daysLeft: 2, sent: {
        MessageType.expiry_7,
        MessageType.expiry_3,
        MessageType.expiry_1,
        MessageType.expiry_0,
      }),
      isNull,
    );
  });

  test('renewed members never get expiry reminders', () {
    expect(select(daysLeft: 2, alreadyRenewed: true), isNull);
  });

  test('frozen members get no reminders', () {
    expect(select(daysLeft: 3, frozen: true), isNull);
  });

  test('upcoming members get no reminders', () {
    expect(select(daysLeft: 30, upcoming: true), isNull);
  });

  test('disabled offsets are ignored', () {
    expect(select(daysLeft: 3, offsets: [7, 1]), isNull);
    expect(select(daysLeft: 3, offsets: [3])!.type, MessageType.expiry_3);
  });

  test('nearest rule wins over earlier offsets', () {
    // daysLeft = 0 with expiry_0 sent: expiry_1 (missed by 1) is nearer than
    // expiry_3 (missed by 3).
    final r = select(daysLeft: 0, sent: {MessageType.expiry_0});
    expect(r!.type, MessageType.expiry_1);
  });

  test('MessageType.fromOffset round-trips', () {
    for (final t in MessageType.values) {
      final offset = t.expiryOffset;
      if (offset != null) {
        expect(MessageType.fromOffset(offset), t);
      }
    }
  });
}
