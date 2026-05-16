# otel_mongodb

OpenTelemetry instrumentation for package:mongo_dart. Wraps MongoDB operations in CLIENT-kind spans following OTel stable semantic conventions (db.system.name=mongodb, db.operation.name, db.collection.name, db.namespace).

Span names follow OTel stable semantic conventions:
`{operation.name} {target}` with no system prefix (the system is
already in `db.system.name` / `messaging.system`).

Part of the [Dartastic](https://dartastic.io) OpenTelemetry family.
