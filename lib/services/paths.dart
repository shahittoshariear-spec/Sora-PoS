import 'dart:io';

const String kAppName = 'Sora PoS';
const String kAppVersion = '0.1.0';

String joinPath(String a, String b) {
  if (a.endsWith(Platform.pathSeparator) || a.endsWith('/')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}

Directory soraDataDirectory() {
  const override = String.fromEnvironment('SORA_DATA_DIR');
  if (override.isNotEmpty) return Directory(override);
  final appData = Platform.environment['APPDATA'];
  final base =
      appData ?? Platform.environment['HOME'] ?? Directory.current.path;
  return Directory(joinPath(base, kAppName));
}
