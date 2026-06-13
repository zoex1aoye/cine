import 'dart:io' show Platform;

bool get isDesktopPlatform => !(Platform.isAndroid || Platform.isIOS);
