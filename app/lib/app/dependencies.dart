/// Dependency injection root for the app (§4, §6).
///
/// The rest of the app consumes `EngineService` — never raw FFI. Swapping
/// [FakeEngineService] for `RustEngineService` at M9 only requires changing
/// this single provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_service.dart';
import '../engine/fake_engine.dart';

/// The engine facade the whole app talks to (§6).
final engineServiceProvider = Provider<EngineService>((_) {
  return FakeEngineService();
});