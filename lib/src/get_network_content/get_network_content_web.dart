import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<String> getNetworkContent(
  Uri url,
  Encoding defaultEncoding,
  Map<String, String>? httpHeaders,
  bool withCredentials,
) async {
  final response = await html.HttpRequest.request(
    url.toString(),
    method: 'GET',
    requestHeaders: httpHeaders,
    withCredentials: withCredentials,
  );

  final ct = response.responseHeaders['content-type'];
  if (ct == null || !ct.toLowerCase().contains('charset')) {
    //  Use default if not specified in content-type header
    return defaultEncoding.decode(utf8.encode(response.responseText ?? ''));
  } else {
    return response.responseText ?? '';
  }
}
