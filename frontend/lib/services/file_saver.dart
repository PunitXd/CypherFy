// Cross-platform "save these bytes as a file" entry point.
//
// On web this triggers a browser download; on other platforms it delegates to
// the stub (not wired in this build). The conditional import keeps the app
// compiling everywhere while only pulling in dart:html on web.
export 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart';
