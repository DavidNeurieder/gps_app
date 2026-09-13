/// Dependency injection root for the app (§4, §6).
///
/// The rest of the app consumes `EngineService` — never raw FFI. Swapping
/// [FakeEngineService] for [RustEngineService] (M9) is a build-time switch:
/// build with `--dart-define=USE_RUST_ENGINE=true` (and, on host workloads,
/// `--dart-define=GPS_ENGINE_LIB=/path/to/libgps_engine.so`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_service.dart';
import '../engine/fake_engine.dart';
import '../engine/rust_engine_service.dart';

/// Whether the native Rust engine is used instead of the fake (§6).
const bool useRustEngine = bool.fromEnvironment('USE_RUST_ENGINE');

/// The engine facade the whole app talks to (§6).
final engineServiceProvider = Provider<EngineService>((_) {
  if (useRustEngine) {
    final libraryPath = const String.fromEnvironment('GPS_ENGINE_LIB');
    return RustEngineService.open(
      libraryPath.isEmpty ? 'libgps_engine.so' : libraryPath,
    );
  }
  return FakeEngineService();
});