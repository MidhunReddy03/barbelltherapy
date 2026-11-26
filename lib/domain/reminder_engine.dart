import 'enums.dart';

/// Reminder selection rules (spec 5.8).
///
/// A member appears on today's reminders for rule R when:
///  - their latest non-cancelled subscription is not frozen and not upcoming,
///  - `end_date - today` matches the rule's offset (exact day), or the rule's
///    day passed within the last [AppConstants.reminderLookbackDays] days
///    ("nearest missed rule" so nothing is skipped when the app wasn't
///    opened on the exact day),
///  - there is no message_log row for (subscription_id, R),
///  - only ONE reminder is produced per member (the most relevant rule).
class ReminderEngine {
  ReminderEngine._();

  /// Picks the reminder to show for one subscription, or null when nothing
  /// is pending.
  ///
  /// [daysLeft] = end_date - today. [sentTypes] are the message types already
  /// logged for this subscription. [enabledOffsets] are the configured
  /// reminder offsets (subset of {7, 3, 1, 0, -3, -7}).
  static ReminderSelection? select({
    required int daysLeft,
    required bool frozen,
    required bool upcoming,
    required bool alreadyRenewed,
    required Set<MessageType> sentTypes,
    required List<int> enabledOffsets,
    int lookbackDays = 3,
  }) {
    if (frozen || upcoming || alreadyRenewed) return null;

    // Consider only offsets whose rule day is today or was missed recently.
    final candidates = <_Candidate>[];
    for (final offset in enabledOffsets) {
      final type = MessageType.fromOffset(offset);
      if (type == null) continue;
      if (sentTypes.contains(type)) continue;

      final diff = (daysLeft - offset).abs();
      final bool ruleDayReached;
      // A rule fires on the day `daysLeft == offset`. Its day has been
      // reached once we've moved to or past it — for pre-expiry rules that
      // means daysLeft <= offset (days tick down), and the same comparison
      // holds for post-expiry rules (days tick further negative).
      ruleDayReached = daysLeft <= offset;
      if (!ruleDayReached) continue;
      if (diff > lookbackDays) continue;
      candidates.add(_Candidate(type: type, offset: offset, diff: diff));
    }
    if (candidates.isEmpty) return null;

    // Nearest rule wins; ties prefer the earlier (larger) offset so a member
    // who was missed on both 3-day and 1-day days gets the 3-day one first.
    candidates.sort((a, b) {
      final byDiff = a.diff.compareTo(b.diff);
      if (byDiff != 0) return byDiff;
      return b.offset.compareTo(a.offset);
    });
    final chosen = candidates.first;
    return ReminderSelection(type: chosen.type, offset: chosen.offset);
  }
}

class ReminderSelection {
  const ReminderSelection({required this.type, required this.offset});

  final MessageType type;
  final int offset;
}

class _Candidate {
  const _Candidate({
    required this.type,
    required this.offset,
    required this.diff,
  });

  final MessageType type;
  final int offset;
  final int diff;
}
