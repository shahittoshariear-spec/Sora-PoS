import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'paths.dart';

/// The soft water-drop ring the counter hears when a sale lands. Windows'
/// own PlaySoundW is used directly, so there is no audio plugin in the build.
class Chime {
  static String? _wav;
  static _PlaySoundDart? _play;

  static Future<void> play() async {
    if (!Platform.isWindows) return;
    try {
      _play ??= DynamicLibrary.open('winmm.dll').lookupFunction<_PlaySoundNative, _PlaySoundDart>(
        'PlaySoundW',
      );
      final path = await _ensureWav();
      final ptr = path.toNativeUtf16();
      _play!(ptr, 0, 0x00020001 | 0x0002);
      // PlaySound reads the path immediately, but keeping the buffer alive
      // briefly is cheap insurance.
      Timer(const Duration(seconds: 3), () => calloc.free(ptr));
    } catch (_) {
      // A missing sound is never a reason to interrupt a sale.
    }
  }

  static Future<String> _ensureWav() async {
    if (_wav != null) return _wav!;
    final dest = File(joinPath(joinPath(soraDataDirectory().path, 'sounds'), 'sale-complete.wav'));
    if (!await dest.exists()) {
      final data = await rootBundle.load('assets/sounds/sale-complete.wav');
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    _wav = dest.path;
    return dest.path;
  }
}

typedef _PlaySoundNative = Int32 Function(Pointer<Utf16> sound, IntPtr module, Uint32 flags);
typedef _PlaySoundDart = int Function(Pointer<Utf16> sound, int module, int flags);
