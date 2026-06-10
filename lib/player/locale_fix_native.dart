// locale_fix_native.dart – native implementation using dart:ffi
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../api/jp_log.dart';

typedef SetLocaleC = Pointer<Utf8> Function(Int32 category, Pointer<Utf8> locale);
typedef SetLocaleDart = Pointer<Utf8> Function(int category, Pointer<Utf8> locale);

/// Sets the numeric locale to "C" on supported native platforms.
/// This function is a no‑op on web (provided by the stub implementation).
void setNumericLocaleToCImpl() {
  try {
    final dylib = DynamicLibrary.process();
    final setlocale = dylib
        .lookup<NativeFunction<SetLocaleC>>('setlocale')
        .asFunction<SetLocaleDart>();
    final cLocale = 'C'.toNativeUtf8();
    // LC_NUMERIC = 1 on most platforms
    final result = setlocale(1, cLocale);
    if (result != nullptr) {
      final resultStr = result.toDartString();
      jpLog('SYSTEM', 'setlocale succeeded: $resultStr');
    } else {
      jpLog('SYSTEM', 'setlocale returned NULL');
    }
    calloc.free(cLocale);
  } catch (e) {
    jpLog('SYSTEM', 'Failed to setlocale: $e');
  }
}
