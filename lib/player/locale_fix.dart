// locale_fix.dart – platform-aware wrapper
import 'locale_fix_native.dart' if (dart.library.html) 'locale_fix_stub.dart'
    as impl;

/// Sets the numeric locale to "C" on supported native platforms.
/// No-op on web.
void setNumericLocaleToC() => impl.setNumericLocaleToCImpl();
