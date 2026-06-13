import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client HTTP vers le backend de synchronisation BEJ (serveur Dart local).
class ApiClient {
  final String baseUrl;
  ApiClient(this.baseUrl);

  /// Pousse un lot d'opérations CRUD vers le serveur. Renvoie le nombre
  /// d'opérations appliquées côté PostgreSQL.
  Future<int> upload(List<Map<String, dynamic>> batch) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/upload'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'batch': batch}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Échec upload (${resp.statusCode}) : ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (j['applied'] as num).toInt();
  }

  /// Teste la disponibilité du backend (sert d'indicateur online/offline).
  Future<bool> health() async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
