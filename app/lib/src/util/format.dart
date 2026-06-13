/// Formate un montant en francs CFA, avec séparateur de milliers (espace).
String fcfa(num v) {
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  final sign = v < 0 ? '-' : '';
  return '$sign${buf.toString()} FCFA';
}
