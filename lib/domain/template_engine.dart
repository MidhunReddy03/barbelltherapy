/// Template placeholder rendering (spec 7).
///
/// Placeholders look like `{name}`, `{plan}`, `{end_date}`. When a value is
/// missing, the whole sentence containing the placeholder is removed rather
/// than showing an empty `{}`.
class TemplateEngine {
  TemplateEngine._();

  static final RegExp _placeholder = RegExp(r'\{(\w+)\}');

  /// Sentence enders include the Telugu danda so Telugu templates split
  /// correctly.
  static final RegExp _sentenceSplit =
      RegExp(r'[^.!?।\n]+[.!?।]*\n?');

  /// Renders [body] with [values]. Missing values cause their whole sentence
  /// to be dropped. Returns '' when nothing renderable remains.
  static String render(String body, Map<String, String?> values) {
    final missing = <String>{};
    for (final m in _placeholder.allMatches(body)) {
      final key = m.group(1)!;
      final v = values[key];
      if (v == null || v.isEmpty) missing.add(key);
    }
    if (missing.isEmpty) {
      return _replace(body, values);
    }

    final kept = <String>[];
    for (final match in _sentenceSplit.allMatches(body)) {
      final sentence = match.group(0)!;
      final hasMissing = missing.any(
        (key) => sentence.contains('{$key}'),
      );
      if (!hasMissing && sentence.trim().isNotEmpty) {
        kept.add(sentence);
      }
    }
    var out = kept.join();
    out = _replace(out, values);
    return out.trim();
  }

  static String _replace(String input, Map<String, String?> values) {
    return input.replaceAllMapped(_placeholder, (m) {
      final v = values[m.group(1)];
      return v ?? '';
    });
  }

  /// Lists the placeholder keys present in a template body (used by the
  /// template editor's chip bar).
  static List<String> placeholdersIn(String body) =>
      _placeholder
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet()
          .toList();
}
