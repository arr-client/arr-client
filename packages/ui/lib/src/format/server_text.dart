/// Text that a server, or whoever named a release there, chose.
library;

// Line breaks and tabs, which only separate words here.
final _breaks = RegExp(r'[\t\n\v\f\r\u0085\u2028\u2029]+');

// Control, direction and other characters that could disguise what is said.
final _unprintable = RegExp(r'\p{C}', unicode: true);

const _longest = 500;

/// [text] as harmless text of one paragraph and at most 500 characters, or null
/// if nothing is left to show.
String? serverText(String? text) {
  final clean = (text ?? '')
      .replaceAll(_breaks, ' ')
      .replaceAll(_unprintable, '\u{fffd}')
      .trim();
  if (clean.isEmpty) return null;
  return clean.runes.length > _longest
      ? '${String.fromCharCodes(clean.runes.take(_longest))}…'
      : clean;
}
