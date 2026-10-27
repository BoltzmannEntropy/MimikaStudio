import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mimika_studio/screens/audiobook_screen.dart';

const _voices = <Map<String, String>>[
  {'code': 'bf_emma', 'name': 'Emma'},
  {'code': 'bf_alice', 'name': 'Alice'},
  {'code': 'bf_isabella', 'name': 'Isabella'},
  {'code': 'bf_lily', 'name': 'Lily'},
  {'code': 'bm_daniel', 'name': 'Daniel'},
  {'code': 'bm_fable', 'name': 'Fable'},
  {'code': 'bm_george', 'name': 'George'},
  {'code': 'bm_lewis', 'name': 'Lewis'},
  // New backend entries must appear without another frontend catalog change.
  {'code': 'bf_catalog_added', 'name': 'Catalog voice'},
];

http.Response _json(Object body, [int statusCode = 200]) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: {'content-type': 'application/json'},
);

MockClient _backend({
  required FutureOr<http.Response> Function() loadVoices,
  bool includeDocument = false,
  List<http.Request>? requests,
}) => MockClient((request) async {
  requests?.add(request);
  switch (request.url.path) {
    case '/api/kokoro/voices':
      return loadVoices();
    case '/api/pdf/list':
      return _json({
        'documents': [
          if (includeDocument)
            {'name': 'chapter.txt', 'url': '/pdf/chapter.txt'},
        ],
      });
    case '/pdf/chapter.txt':
      return http.Response('A short chapter for the audiobook.', 200);
    case '/api/pdf/extract-text':
      return _json({'text': 'A short chapter for the audiobook.'});
    case '/api/audiobook/list':
      return _json({'audiobooks': []});
    case '/api/qwen3/voices':
      return _json({
        'voices': [
          {'name': 'Yelena'},
        ],
      });
    case '/api/audiobook/generate-from-file':
      return _json({'job_id': 'test-job', 'status': 'queued'});
    case '/api/audiobook/status/test-job':
      return _json({'status': 'queued'});
    default:
      throw StateError('Unexpected request: ${request.method} ${request.url}');
  }
});

Finder get _voiceField => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.key.toString().contains('kokoro-'),
);

Finder get _generateButton => find.ancestor(
  of: find.text('Generate Audiobook'),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

String? _selectedVoice(WidgetTester tester) =>
    tester.state<FormFieldState<String>>(_voiceField).value;

Future<void> _showScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: AudiobookScreen())),
  );
  await tester.pump();
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          null,
        );
  });

  testWidgets('all API voices are selectable and selected code is submitted', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = _backend(
      loadVoices: () => _json({'voices': _voices, 'default': 'bm_george'}),
      includeDocument: true,
      requests: requests,
    );

    await http.runWithClient(() async {
      await _showScreen(tester);
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: _voiceField,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        dropdown.items!.map((item) => item.value),
        _voices.map((voice) => voice['code']),
      );
      expect(_selectedVoice(tester), 'bf_emma');

      await tester.tap(_voiceField);
      await tester.pumpAndSettle();
      expect(find.text('Isabella').last, findsOneWidget);
      expect(find.text('Daniel').last, findsOneWidget);
      expect(find.text('Fable').last, findsOneWidget);
      expect(find.text('Catalog voice').last, findsOneWidget);
      await tester.tap(find.text('Isabella').last);
      await tester.pumpAndSettle();
      expect(_selectedVoice(tester), 'bf_isabella');

      await tester.tap(_generateButton);
      await tester.pump();
      await tester.pump();

      final upload = requests.singleWhere(
        (request) => request.url.path == '/api/audiobook/generate-from-file',
      );
      expect(upload.method, 'POST');
      expect(upload.body, contains('name="voice"\r\n\r\nbf_isabella\r\n'));
      expect(upload.body, contains('name="engine"\r\n\r\nkokoro\r\n'));
      await _disposeScreen(tester);
    }, () => client);
  });

  testWidgets('uses the backend default if the previous voice is unavailable', (
    tester,
  ) async {
    final client = _backend(
      loadVoices: () => _json({
        'voices': _voices.where((voice) => voice['code'] != 'bf_emma').toList(),
        'default': 'bm_daniel',
      }),
    );
    await http.runWithClient(() async {
      await _showScreen(tester);
      await tester.pumpAndSettle();
      expect(_selectedVoice(tester), 'bm_daniel');
      await _disposeScreen(tester);
    }, () => client);
  });

  testWidgets('uses the first voice if both selection and default are absent', (
    tester,
  ) async {
    final client = _backend(
      loadVoices: () => _json({
        'voices': [
          {'code': 'bm_fable', 'name': 'Fable'},
          {'code': 'bm_daniel', 'name': 'Daniel'},
        ],
        'default': 'missing-voice',
      }),
    );
    await http.runWithClient(() async {
      await _showScreen(tester);
      await tester.pumpAndSettle();
      expect(_selectedVoice(tester), 'bm_fable');
      await _disposeScreen(tester);
    }, () => client);
  });

  testWidgets('empty catalog disables Kokoro generation and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    final client = _backend(
      loadVoices: () => ++attempts == 1
          ? _json({'voices': [], 'default': 'bf_emma'})
          : _json({'voices': _voices, 'default': 'bm_george'}),
    );
    await http.runWithClient(() async {
      await _showScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('No Kokoro voices available'), findsOneWidget);
      expect(_selectedVoice(tester), isNull);
      expect(tester.widget<FilledButton>(_generateButton).onPressed, isNull);
      expect(
        tester.widget<DropdownButtonFormField<String>>(_voiceField).onChanged,
        isNull,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(_selectedVoice(tester), 'bm_george');
      expect(tester.widget<FilledButton>(_generateButton).onPressed, isNotNull);
      expect(find.text('No Kokoro voices available'), findsNothing);
      await _disposeScreen(tester);
    }, () => client);
  });

  testWidgets('failed catalog load displays an error and retry recovers', (
    tester,
  ) async {
    var attempts = 0;
    final client = _backend(
      loadVoices: () => ++attempts == 1
          ? _json({'detail': 'temporarily unavailable'}, 503)
          : _json({'voices': _voices, 'default': 'bm_george'}),
    );
    await http.runWithClient(() async {
      await _showScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('Failed to load Kokoro voices'), findsOneWidget);
      expect(tester.widget<FilledButton>(_generateButton).onPressed, isNull);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(_selectedVoice(tester), 'bm_george');
      expect(find.text('Failed to load Kokoro voices'), findsNothing);
      expect(tester.widget<FilledButton>(_generateButton).onPressed, isNotNull);
      await _disposeScreen(tester);
    }, () => client);
  });

  testWidgets(
    'loading disables generation and late response after disposal is safe',
    (tester) async {
      final response = Completer<http.Response>();
      final client = _backend(loadVoices: () => response.future);
      await http.runWithClient(() async {
        await _showScreen(tester);
        expect(find.text('Loading Kokoro voices...'), findsOneWidget);
        expect(tester.widget<FilledButton>(_generateButton).onPressed, isNull);
        expect(
          tester.widget<DropdownButtonFormField<String>>(_voiceField).onChanged,
          isNull,
        );
        await _disposeScreen(tester);
        response.complete(_json({'voices': _voices, 'default': 'bm_george'}));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
}
