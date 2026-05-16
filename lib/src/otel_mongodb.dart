// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:mongo_dart/mongo_dart.dart' as m;

import 'otel_mongodb_suppression.dart';

const _tracerName = 'otel_mongodb';
const _dbSystem = 'mongodb';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

Attributes _attrs({
  required String operation,
  String? collection,
  String? namespace,
  String? serverAddress,
  int? serverPort,
}) =>
    OTel.attributesFromMap(<String, Object>{
      Database.dbSystem.key: _dbSystem,
      Database.dbSystemName.key: _dbSystem,
      Database.dbOperation.key: operation,
      Database.dbOperationName.key: operation,
      if (collection != null) Database.dbCollectionName.key: collection,
      if (namespace != null) Database.dbNamespace.key: namespace,
      if (serverAddress != null)
        ServerResource.serverAddress.key: serverAddress,
      if (serverPort != null) ServerResource.serverPort.key: serverPort,
    });

/// Runs [invoke] inside a CLIENT-kind span named `<operation> <collection>`
/// (or just `<operation>` when no collection applies), with
/// `db.system.name=mongodb` and the standard OTel db attributes.
///
/// [operation] is the MongoDB operation name — typical values: `find`,
/// `findOne`, `insertOne`, `insertMany`, `updateOne`, `updateMany`,
/// `deleteOne`, `deleteMany`, `aggregate`, `count`, `distinct`,
/// `runCommand`.
///
/// [collection] becomes `db.collection.name`. [namespace] becomes
/// `db.namespace` (the database name in MongoDB terminology).
///
/// Exceptions are recorded with `error.type` + `recordException`, span
/// status is set to `Error`, and the exception is rethrown.
Future<R> tracedMongodbCall<R>({
  required String operation,
  required Future<R> Function() invoke,
  String? collection,
  String? namespace,
  String? serverAddress,
  int? serverPort,
}) async {
  if (mongodbInstrumentationSuppressed()) return invoke();
  // OTel stable semconv: span name is `{operation} {target}` with NO
  // system prefix. `db.system.name=mongodb` already carries the system.
  final spanName = collection != null ? '$operation $collection' : operation;
  final span = _tracer().startSpan(
    spanName,
    kind: SpanKind.client,
    attributes: _attrs(
      operation: operation,
      collection: collection,
      namespace: namespace,
      serverAddress: serverAddress,
      serverPort: serverPort,
    ),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorResource.errorType.key,
          e.runtimeType.toString(),
        ),
      ]),
    );
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Traced versions of the common `DbCollection` operations. Thin
/// wrappers — drop in by appending `Traced` to the method name.
///
/// `find` (which returns a `Stream`) is intentionally not exposed as
/// an extension because closing the span on stream completion crosses
/// zone boundaries (stream-listener-zone-trap). Wrap stream-based reads
/// with `tracedMongodbCall` and consume the stream inside the callback.
extension OTelDbCollection on m.DbCollection {
  /// Traced `findOne`.
  Future<Map<String, dynamic>?> findOneTraced([m.SelectorBuilder? selector]) =>
      tracedMongodbCall<Map<String, dynamic>?>(
        operation: 'findOne',
        collection: collectionName,
        namespace: db.databaseName,
        invoke: () => findOne(selector),
      );

  /// Traced `insertOne`.
  Future<m.WriteResult> insertOneTraced(
    Map<String, dynamic> document, {
    m.WriteConcern? writeConcern,
  }) =>
      tracedMongodbCall<m.WriteResult>(
        operation: 'insertOne',
        collection: collectionName,
        namespace: db.databaseName,
        invoke: () => insertOne(document, writeConcern: writeConcern),
      );

  /// Traced `updateOne`.
  Future<m.WriteResult> updateOneTraced(
    m.SelectorBuilder selector,
    Object update, {
    bool upsert = false,
    m.WriteConcern? writeConcern,
  }) =>
      tracedMongodbCall<m.WriteResult>(
        operation: 'updateOne',
        collection: collectionName,
        namespace: db.databaseName,
        invoke: () => updateOne(
          selector,
          update,
          upsert: upsert,
          writeConcern: writeConcern,
        ),
      );

  /// Traced `deleteOne`.
  Future<m.WriteResult> deleteOneTraced(
    Object selector, {
    m.WriteConcern? writeConcern,
  }) =>
      tracedMongodbCall<m.WriteResult>(
        operation: 'deleteOne',
        collection: collectionName,
        namespace: db.databaseName,
        invoke: () => deleteOne(selector, writeConcern: writeConcern),
      );
}
