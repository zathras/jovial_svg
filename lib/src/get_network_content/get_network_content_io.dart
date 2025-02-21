import 'dart:convert';
import 'package:http/http.dart' as http;

Future<String> getNetworkContent(
  Uri url,
  Encoding defaultEncoding,
  Map<String, String>? httpHeaders,
  bool withCredentials,
) async {
  String? content;
  final client = http.Client();
  try {
    final response = await client.get(url, headers: httpHeaders);
    final ct = response.headers['content-type'];
    if (ct == null || !ct.toLowerCase().contains('charset')) {
      //  Use default if not specified in content-type header
      content = defaultEncoding.decode(response.bodyBytes);
    } else {
      content = response.body;
    }
  } finally {
    client.close();
  }
  return content;
}
