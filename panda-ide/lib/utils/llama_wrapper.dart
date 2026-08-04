// Conditional export — native Android/iOS get the real llama implementation,
// web gets a no-op stub so dart:ffi is never pulled into dart2js.
export 'llama_wrapper_native.dart'
    if (dart.library.html) 'llama_wrapper_stub.dart';
