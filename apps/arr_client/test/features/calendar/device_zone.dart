/// Changes the time zone of the running process, as travelling changes the
/// device's while the app is open. Only for Linux and macOS, where tests run.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

final _process = DynamicLibrary.process();

final _malloc = _process
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');

final _free = _process
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');

final _setenv = _process
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32),
      int Function(Pointer<Uint8>, Pointer<Uint8>, int)
    >('setenv');

final _unsetenv = _process
    .lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)
    >('unsetenv');

final _tzset = _process.lookupFunction<Void Function(), void Function()>(
  'tzset',
);

Pointer<Uint8> _text(String value) {
  final bytes = utf8.encode(value);
  final pointer = _malloc(bytes.length + 1);
  pointer.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return pointer;
}

/// Sets the zone to the one named [zone], or back to the system's if null.
void setDeviceZone(String? zone) {
  final name = _text('TZ');
  if (zone == null) {
    _unsetenv(name);
  } else {
    final value = _text(zone);
    _setenv(name, value, 1);
    _free(value);
  }
  _free(name);
  _tzset();
}

/// The zone the process was started in, for [setDeviceZone].
final String? startZone = Platform.environment['TZ'];
