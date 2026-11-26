/// What one query parameter, form field or JSON field may hold.
final class ParamRule {
  /// Any value. A query parameter may repeat.
  const ParamRule.any({this.required = false})
    : values = null,
      nonEmpty = false;

  /// Only one of [values], given once. It must be present unless [required] is
  /// false: leaving it out can select another operation.
  const ParamRule.only(Set<String> this.values, {this.required = true})
    : nonEmpty = false;

  /// Any value but an empty one, and always present. For what narrows an
  /// operation to its target, which a server may otherwise apply to everything.
  ///
  /// Refused are a blank string and, in a JSON body, null, an empty list or
  /// object, and a list holding null or a blank string.
  const ParamRule.nonEmpty() : values = null, required = true, nonEmpty = true;

  /// The values permitted, or null for any.
  final Set<String>? values;

  /// Whether the request must carry it.
  final bool required;

  /// Whether what is given must hold something.
  final bool nonEmpty;

  /// Whether the values given under one name are permitted. An empty list means
  /// the name is absent.
  bool permits(List<String> given) {
    if (given.isEmpty) return !required;
    if (nonEmpty && given.any((value) => value.trim().isEmpty)) return false;
    final allowed = values;
    return allowed == null ||
        (given.length == 1 && allowed.contains(given.single));
  }

  /// Whether [given] has no name outside [rules] and satisfies each of them.
  static bool permitsAll(
    Map<String, ParamRule> rules,
    Map<String, List<String>> given,
  ) =>
      given.keys.every(rules.containsKey) &&
      rules.entries.every(
        (rule) => rule.value.permits(given[rule.key] ?? const []),
      );
}
