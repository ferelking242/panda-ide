// Conditional export — native platforms get the real terminal implementation,
// web gets a no-op stub so dart:ffi / dart:io are never pulled into dart2js.
export 'terminal_native.dart' if (dart.library.html) 'terminal_stub.dart';
