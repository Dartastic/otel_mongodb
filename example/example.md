# otel_mongodb example

```dart
// example/main.dart

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:otel_mongodb/otel_mongodb.dart';

Future<void> main() async {
  // 1. Bring up OTel before touching the database so trace context
  //    is already flowing when the first operation runs.
  await OTel.initialize(
    serviceName: 'mongodb-demo',
  );

  final db = await Db.create('mongodb://localhost:27017/shop');
  await db.open();
  final users = db.collection('users');

  // 2. Drop-in traced variants: append `Traced` to the method name.
  //
  // ✨ Span: `insertOne users` (CLIENT)
  //    db.system.name=mongodb, db.operation.name=insertOne,
  //    db.collection.name=users, db.namespace=shop
  await users.insertOneTraced({'name': 'Ada', 'plan': 'pro'});

  // ✨ Span: `findOne users`
  final ada = await users.findOneTraced(where.eq('name', 'Ada'));
  print(ada);

  // ✨ Span: `updateOne users`
  await users.updateOneTraced(
    where.eq('name', 'Ada'),
    modify.set('plan', 'enterprise'),
  );

  // 3. Stream-based reads (`find`) and anything without a Traced
  //    wrapper: wrap the whole operation with `tracedMongodbCall`
  //    and consume the stream inside the callback.
  //
  // ✨ Span: `find users`
  final pros = await tracedMongodbCall<List<Map<String, dynamic>>>(
    operation: 'find',
    collection: 'users',
    namespace: 'shop',
    serverAddress: 'localhost',
    serverPort: 27017,
    invoke: () => users.find(where.eq('plan', 'enterprise')).toList(),
  );
  print(pros.length);

  // 4. Suppress instrumentation for noisy internals (health checks,
  //    migrations) — no spans are created inside the zone.
  await runWithoutMongodbInstrumentationAsync(() async {
    await users.findOneTraced(where.eq('name', 'Ada'));
  });

  // ✨ Span: `deleteOne users`
  await users.deleteOneTraced(where.eq('name', 'Ada'));

  await db.close();
  await OTel.shutdown();
}
```

## Trace shape

```
insertOne users   (CLIENT, db.system.name=mongodb)
findOne users
updateOne users
find users        (server.address=localhost, server.port=27017)
deleteOne users

(nothing emitted inside runWithoutMongodbInstrumentationAsync)
```

Errors are recorded on the span (`error.type`, `recordException`,
status `Error`) and rethrown, so your existing error handling is
untouched.
