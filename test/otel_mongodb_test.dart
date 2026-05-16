// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// These tests exercise the span/attribute machinery of
// `tracedMongodbCall` using a fake `invoke` callback — no real
// MongoDB server is needed.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_mongodb/otel_mongodb.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;
  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrMap(Span span) => {
      for (final a in span.attributes.toList()) a.key: a.value,
    };

void main() {
  group('tracedMongodbCall', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'otel_mongodb-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('find names span "find <collection>" per OTel stable semconv',
        () async {
      await tracedMongodbCall<int>(
        operation: 'find',
        collection: 'users',
        namespace: 'shop',
        invoke: () async => 1,
      );
      expect(exporter.spans, hasLength(1));
      final span = exporter.spans.single;
      expect(span.name, 'find users');
      final attrs = _attrMap(span);
      expect(attrs['db.system.name'], 'mongodb');
      expect(attrs['db.operation.name'], 'find');
      expect(attrs['db.collection.name'], 'users');
      expect(attrs['db.namespace'], 'shop');
    });

    test('insertOne, updateOne, deleteOne, aggregate operations', () async {
      for (final op in ['insertOne', 'updateOne', 'deleteOne', 'aggregate']) {
        await tracedMongodbCall<int>(
          operation: op,
          collection: 'orders',
          invoke: () async => 1,
        );
      }
      expect(exporter.spans.map((s) => s.name), [
        'insertOne orders',
        'updateOne orders',
        'deleteOne orders',
        'aggregate orders',
      ]);
    });

    test('runCommand drops target when no collection applies', () async {
      await tracedMongodbCall<int>(
        operation: 'runCommand',
        invoke: () async => 1,
      );
      // Stable semconv: when target is unknown, span name is just
      // the operation — NO trailing system or namespace.
      expect(exporter.spans.single.name, 'runCommand');
    });

    test('server.address/port recorded when supplied', () async {
      await tracedMongodbCall<int>(
        operation: 'findOne',
        collection: 'sessions',
        serverAddress: 'mongo.internal',
        serverPort: 27017,
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['server.address'], 'mongo.internal');
      expect(attrs['server.port'], 27017);
    });

    test('records exception and sets error status on throw', () async {
      await expectLater(
        tracedMongodbCall<int>(
          operation: 'findOne',
          collection: 'users',
          invoke: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      final span = exporter.spans.single;
      expect(span.status, SpanStatusCode.Error);
      expect(_attrMap(span)['error.type'], 'StateError');
    });

    test('zone-scoped suppression skips span creation', () async {
      await runWithoutMongodbInstrumentationAsync(() async {
        await tracedMongodbCall<int>(
          operation: 'findOne',
          collection: 'users',
          invoke: () async => 1,
        );
      });
      expect(exporter.spans, isEmpty);
    });
  });
}
