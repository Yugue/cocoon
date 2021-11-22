// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:conductor_core/conductor_core.dart' show Checkouts, EngineRepository, FrameworkRepository, StartContext;
import 'local_conductor.dart';

/// Service class for using a test conductor in a local environment.
///
/// This is not the production version of the conductor, only intended for test.
/// This service creates fake local upstream repos to simulate the production repos.
class DevLocalConductorService extends LocalConductorService {
  @override
  Future<void> createRelease({
    required String candidateBranch,
    required String? dartRevision,
    required List<String> engineCherrypickRevisions,
    required String engineMirror,
    required List<String> frameworkCherrypickRevisions,
    required String frameworkMirror,
    required String incrementLetter,
    required String releaseChannel,
  }) async {
    final Checkouts checkouts = Checkouts(
      parentDirectory: rootDirectory,
      processManager: processManager,
      fileSystem: fs,
      platform: platform,
      stdio: stdio,
    );

    final FrameworkRepository localFrameworkUpstream = FrameworkRepository(checkouts, localUpstream: true);

    final EngineRepository localEngineUpstream = EngineRepository(checkouts, localUpstream: true);

    final StartContext startContext = StartContext(
      candidateBranch: candidateBranch,
      checkouts: checkouts,
      // TODO(yugue): Read conductor version. https://github.com/flutter/flutter/issues/92842
      conductorVersion: 'ui_0.1',
      dartRevision: dartRevision,
      engineCherrypickRevisions: engineCherrypickRevisions,
      engineMirror: engineMirror,
      engineUpstream: (await localFrameworkUpstream.checkoutDirectory).path,
      frameworkCherrypickRevisions: frameworkCherrypickRevisions,
      frameworkMirror: frameworkMirror,
      frameworkUpstream: (await localEngineUpstream.checkoutDirectory).path,
      incrementLetter: incrementLetter,
      processManager: processManager,
      releaseChannel: releaseChannel,
      stateFile: stateFile,
    );
    return startContext.run();
  }
}
