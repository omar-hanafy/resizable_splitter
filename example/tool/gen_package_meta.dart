import 'dart:io';

/// Generates `lib/src/package_meta.dart` from the parent `resizable_splitter`
/// package's `pubspec.yaml` and `LICENSE`, so the showcase's displayed version,
/// name, links, install command, and license track the package with zero manual
/// edits. Bump the package version (or change a link) and the whole UI follows.
///
/// Run before building or deploying (the deploy script does this for you):
///
///   dart run tool/gen_package_meta.dart
void main() {
  final scriptFile = File.fromUri(Platform.script);
  // <package>/example/tool/gen_package_meta.dart -> <package>/example
  final exampleDir = scriptFile.parent.parent;
  final packageRoot = exampleDir.parent;

  final pubspec = File('${packageRoot.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('Cannot find package pubspec at ${pubspec.path}');
    exit(1);
  }
  final lines = pubspec.readAsLinesSync();

  String require(String key) {
    final re = RegExp('^$key:[ \\t]*(.+?)[ \\t]*\$');
    for (final line in lines) {
      final match = re.firstMatch(line);
      if (match != null) {
        return match.group(1)!.replaceAll('"', '').replaceAll("'", '').trim();
      }
    }
    throw StateError('Missing top-level "$key:" in ${pubspec.path}');
  }

  String? optional(String key) {
    try {
      return require(key);
    } on StateError {
      return null;
    }
  }

  final name = require('name');
  final version = require('version');
  final repository =
      optional('repository') ??
      optional('homepage') ??
      'https://pub.dev/packages/$name';
  final license = _detectLicense(File('${packageRoot.path}/LICENSE'));

  final out = File('${exampleDir.path}/lib/src/package_meta.dart');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('''
// GENERATED FILE - do not edit by hand.
//
// Source of truth: the resizable_splitter package's pubspec.yaml + LICENSE.
// Regenerate with: dart run tool/gen_package_meta.dart
//
// Centralizing the showcase's metadata here means a package version bump or a
// link change needs no edits in the UI - just rerun the generator (the deploy
// script does this automatically before every build).

/// Metadata about the package the showcase demonstrates, generated from its
/// pubspec and license so the displayed version, name, links, and license never
/// drift from what is actually published.
abstract final class PackageMeta {
  /// Package name, e.g. `resizable_splitter`.
  static const String name = '$name';

  /// Published version, e.g. `2.0.0`.
  static const String version = '$version';

  /// Caret constraint to drop into a dependent's pubspec, e.g. `^2.0.0`.
  static const String versionConstraint = '^$version';

  /// Version label for badges, e.g. `v2.0.0`.
  static const String versionLabel = 'v$version';

  /// One-line install command, e.g. `flutter pub add resizable_splitter`.
  static const String installCommand = 'flutter pub add $name';

  /// Source repository URL.
  static const String repositoryUrl = '$repository';

  /// pub.dev package page.
  static const String pubDevUrl = 'https://pub.dev/packages/$name';

  /// License identifier detected from the LICENSE file, e.g. `MIT`.
  static const String license = '$license';
}
''');

  stdout.writeln(
    'Generated ${out.path}\n  name=$name  version=$version  license=$license',
  );
}

/// Best-effort detection of the license from the LICENSE file body, so the
/// footer label follows the actual license. Defaults to `MIT` (the current
/// license) when the file is missing or unrecognized.
String _detectLicense(File license) {
  if (!license.existsSync()) return 'MIT';
  final text = license.readAsStringSync();
  if (text.contains('Permission is hereby granted, free of charge') &&
      text.contains('sublicense')) {
    return 'MIT';
  }
  if (text.contains('Apache License')) return 'Apache-2.0';
  if (text.contains('GNU GENERAL PUBLIC LICENSE')) return 'GPL';
  if (text.contains('Redistribution and use in source and binary forms')) {
    return 'BSD';
  }
  return 'MIT';
}
