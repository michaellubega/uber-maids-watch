import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uber_maids_watch/core/api_client.dart';
import 'package:uber_maids_watch/core/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('defaults to the hosted Render service', () {
      expect(
        ApiConfig.defaultBaseUrl,
        'https://uber-maids-watch.onrender.com/api',
      );
      expect(ApiConfig.isHostedDefault, isTrue);
    });

    test('allows Render cold starts', () {
      expect(ApiConfig.requestTimeout.inSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('ApiClient.upload', () {
    test('sends an authenticated multipart document upload', () async {
      final directory = await Directory.systemTemp.createTemp('umw-upload-');
      final file = File('${directory.path}/national-id.pdf')
        ..writeAsBytesSync(utf8.encode('%PDF-1.4 test identity document'));

      late http.Request captured;
      final client = ApiClient(
        baseUrl: 'https://example.test/api',
        accessToken: () => 'test-token',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'id': 'doc-1', 'title': 'National ID - front'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.upload(
        '/worker-documents/',
        filePath: file.path,
        fields: {
          'worker': 'worker-1',
          'document_type': 'NATIONAL_ID',
          'title': 'National ID - front',
        },
      );

      expect(result['id'], 'doc-1');
      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://example.test/api/worker-documents/',
      );
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(
        captured.headers['Content-Type'],
        contains('multipart/form-data'),
      );
      final body = latin1.decode(captured.bodyBytes);
      expect(body, contains('NATIONAL_ID'));
      expect(body, contains('worker-1'));
      expect(body, contains('national-id.pdf'));
      expect(body, contains('%PDF-1.4 test identity document'));

      await directory.delete(recursive: true);
      client.close();
    });

    test('surfaces the server validation message', () async {
      final directory = await Directory.systemTemp.createTemp('umw-upload-');
      final file = File('${directory.path}/notes.exe')
        ..writeAsBytesSync(utf8.encode('not a document'));

      final client = ApiClient(
        baseUrl: 'https://example.test/api',
        accessToken: () => 'test-token',
        httpClient: MockClient((request) async => http.Response(
              jsonEncode({
                'file': ['Allowed file types: .pdf, .jpg, .jpeg, .png'],
              }),
              400,
              headers: {'content-type': 'application/json'},
            )),
      );

      await expectLater(
        client.upload('/worker-documents/', filePath: file.path),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Allowed file types'),
          ),
        ),
      );

      await directory.delete(recursive: true);
      client.close();
    });
  });
}
