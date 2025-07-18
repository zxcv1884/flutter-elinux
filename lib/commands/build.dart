// Copyright 2023 Sony Group Corporation. All rights reserved.
// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/android/build_validation.dart' as android;
import 'package:flutter_tools/src/base/analyze_size.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/commands/build_apk.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../elinux_builder.dart';
import '../elinux_cache.dart';
import '../elinux_plugins.dart';

class ELinuxBuildCommand extends BuildCommand {
  ELinuxBuildCommand({bool verboseHelp = false})
      : super(
          fileSystem: globals.fs,
          buildSystem: globals.buildSystem,
          osUtils: globals.os,
          verboseHelp: verboseHelp,
          androidSdk: globals.androidSdk,
          logger: globals.logger,
        ) {
    addSubcommand(BuildPackageCommand(verboseHelp: verboseHelp));
  }
}

class BuildPackageCommand extends BuildSubCommand with ELinuxExtension, ELinuxRequiredArtifacts {
  /// See: [BuildApkCommand] in `build_apk.dart`
  BuildPackageCommand({bool verboseHelp = false})
      : super(
          verboseHelp: verboseHelp,
          logger: globals.logger,
        ) {
    addCommonDesktopBuildOptions(verboseHelp: verboseHelp);
    argParser.addOption(
      'target-arch',
      defaultsTo: _getCurrentHostPlatformArchName(),
      allowed: <String>['x64', 'arm64'],
      help: 'Target architecture for which the app is compiled',
    );
    argParser.addOption(
      'target-backend-type',
      defaultsTo: 'wayland',
      allowed: <String>['wayland', 'gbm', 'eglstream', 'x11'],
      help: 'Target backend type that the app will run on devices.',
    );
    argParser.addOption(
      'target-compiler-triple',
      help: 'Target compiler triple for which the app is compiled. '
          'e.g. aarch64-linux-gnu',
    );
    argParser.addOption(
      'target-sysroot',
      defaultsTo: '/',
      help: 'The root filesystem path of target platform for which '
          'the app is compiled. This option is valid only '
          'if the current host and target architectures are different.',
    );
    argParser.addOption(
      'target-toolchain',
      help: 'The toolchain path for Clang.',
    );
    argParser.addOption(
      'system-include-directories',
      help: 'The additional system include paths to cross-compile for target platform. '
          'This option is valid only '
          'if the current host and target architectures are different.',
    );
    argParser.addOption(
      'target-compiler-flags',
      help: 'The extra compile flags to be applied to C and C++ compiler',
    );
  }

  @override
  final String name = 'elinux';

  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => <DevelopmentArtifact>{
        // Use gen_snapshot of the arm64 linux-desktop when self-building
        // on arm64 hosts. This is because elinux's artifacts for arm64
        // doesn't support self-build as of now.
        if (_getCurrentHostPlatformArchName() == 'arm64') DevelopmentArtifact.linux,
        ELinuxDevelopmentArtifact.elinux,
      };

  @override
  final String description = 'Build an eLinux package from your app.';

  /// See: [android.validateBuild] in `build_validation.dart`
  void validateBuild(ELinuxBuildInfo eLinuxBuildInfo) {
    if (eLinuxBuildInfo.buildInfo.mode.isPrecompiled && eLinuxBuildInfo.targetArch == 'x86') {
      throwToolExit('x86 ABI does not support AOT compilation.');
    }
  }

  /// See: [BuildApkCommand.runCommand] in `build_apk.dart`
  @override
  Future<FlutterCommandResult> runCommand() async {
    // Not supported cross-building for x64 on arm64.
    final String? targetArch = stringArg('target-arch');
    final String hostArch = _getCurrentHostPlatformArchName();
    if (hostArch != targetArch && hostArch == 'arm64') {
      globals.logger.printError('Not supported cross-building for x64 on arm64.');
      return FlutterCommandResult.fail();
    }

    final BuildInfo buildInfo = await getBuildInfo();
    final ELinuxBuildInfo eLinuxBuildInfo = ELinuxBuildInfo(
      buildInfo,
      targetArch: targetArch!,
      targetBackendType: stringArg('target-backend-type')!,
      targetCompilerTriple: stringArg('target-compiler-triple'),
      targetSysroot: stringArg('target-sysroot')!,
      targetCompilerFlags: stringArg('target-compiler-flags'),
      targetToolchain: stringArg('target-toolchain'),
      systemIncludeDirectories: stringArg('system-include-directories'),
    );
    validateBuild(eLinuxBuildInfo);

    await ELinuxBuilder.buildBundle(
      project: FlutterProject.current(),
      targetFile: targetFile,
      eLinuxBuildInfo: eLinuxBuildInfo,
      sizeAnalyzer: SizeAnalyzer(
        analytics: globals.analytics,
        fileSystem: globals.fs,
        logger: globals.logger,
      ),
    );
    return FlutterCommandResult.success();
  }

  String _getCurrentHostPlatformArchName() {
    final HostPlatform hostPlatform = getCurrentHostPlatform();
    return hostPlatform.platformName;
  }
}
