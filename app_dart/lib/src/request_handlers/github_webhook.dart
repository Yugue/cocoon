// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:github/github.dart';
import 'package:github/hooks.dart';
import 'package:meta/meta.dart';

import '../model/github/checks.dart' as cocoon_checks;
import '../request_handling/body.dart';
import '../request_handling/exceptions.dart';
import '../request_handling/request_handler.dart';
import '../service/config.dart';
import '../service/github_checks_service.dart';
import '../service/logging.dart';
import '../service/scheduler.dart';

/// List of repos that require check for labels and tests.
const Set<String> kNeedsCheckLabelsAndTests = <String>{
  'flutter/engine',
  'flutter/flutter',
  'flutter/packages',
  'flutter/plugins',
};

final RegExp kEngineTestRegExp = RegExp(r'(tests?|benchmarks?)\.(dart|java|mm|m|cc)$');
final List<String> kNeedsTestsLabels = <String>['needs tests'];

@immutable
class GithubWebhook extends RequestHandler<Body> {
  const GithubWebhook(
    Config config, {
    required this.scheduler,
    this.githubChecksService,
  }) : super(config: config);

  /// Cocoon scheduler to trigger tasks against changes from GitHub.
  final Scheduler scheduler;

  /// Github checks service. Used to provide build status to github.
  final GithubChecksService? githubChecksService;

  @override
  Future<Body> post() async {
    final String? gitHubEvent = request!.headers.value('X-GitHub-Event');

    if (gitHubEvent == null || request!.headers.value('X-Hub-Signature') == null) {
      throw const BadRequestException('Missing required headers.');
    }
    final List<int> requestBytes = await request!.expand((_) => _).toList();
    final String? hmacSignature = request!.headers.value('X-Hub-Signature');
    if (!await _validateRequest(hmacSignature, requestBytes)) {
      throw const Forbidden();
    }

    try {
      final String stringRequest = utf8.decode(requestBytes);
      log.fine('Processing $gitHubEvent');
      log.finest(stringRequest);
      switch (gitHubEvent) {
        case 'pull_request':
          await _handlePullRequest(stringRequest);
          break;
        case 'check_run':
          final Map<String, dynamic> event = jsonDecode(stringRequest) as Map<String, dynamic>;
          final cocoon_checks.CheckRunEvent checkRunEvent = cocoon_checks.CheckRunEvent.fromJson(event);
          await scheduler.processCheckRun(checkRunEvent);
      }

      return Body.empty;
    } on FormatException {
      throw const BadRequestException('Could not process input data.');
    } on InternalServerError {
      rethrow;
    }
  }

  Future<void> _handlePullRequest(
    String rawRequest,
  ) async {
    final PullRequestEvent? pullRequestEvent = await _getPullRequestEvent(rawRequest);
    if (pullRequestEvent == null) {
      throw const BadRequestException('Expected pull request event.');
    }
    final String? eventAction = pullRequestEvent.action;
    final PullRequest pr = pullRequestEvent.pullRequest!;

    // See the API reference:
    // https://developer.github.com/v3/activity/events/types/#pullrequestevent
    // which unfortunately is a bit light on explanations.
    log.fine('Processing $eventAction for ${pr.htmlUrl}');
    switch (eventAction) {
      case 'closed':
        // If it was closed without merging, cancel any outstanding tryjobs.
        // We'll leave unfinished jobs if it was merged since we care about those
        // results.
        if (!pr.merged!) {
          await scheduler.cancelPreSubmitTargets(pullRequest: pr, reason: 'Pull request closed');
        } else {
          // Merged pull requests can be added to CI.
          await scheduler.addPullRequest(pr);
        }
        break;
      case 'edited':
        // Editing a PR should not trigger new jobs, but may update whether
        // it has tests.
        await _checkForLabelsAndTests(pullRequestEvent);
        break;
      case 'opened':
      case 'ready_for_review':
      case 'reopened':
        // These cases should trigger LUCI jobs.
        await _checkForLabelsAndTests(pullRequestEvent);
        await _scheduleIfMergeable(pullRequestEvent);
        break;
      case 'labeled':
        break;
      case 'synchronize':
        // This indicates the PR has new commits. We need to cancel old jobs
        // and schedule new ones.
        await _scheduleIfMergeable(pullRequestEvent);
        break;
      // Ignore the rest of the events.
      case 'unlabeled':
      case 'assigned':
      case 'locked':
      case 'review_request_removed':
      case 'review_requested':
      case 'unassigned':
      case 'unlocked':
        break;
    }
  }

  /// This method assumes that jobs should be cancelled if they are already
  /// runnning.
  Future<void> _scheduleIfMergeable(
    PullRequestEvent pullRequestEvent,
  ) async {
    final PullRequest pr = pullRequestEvent.pullRequest!;
    final RepositorySlug slug = pullRequestEvent.repository!.slug();

    log.info(
        'Scheduling tasks if mergeable(${pr.mergeable}): owner=${slug.owner} repo=${slug.name} and pr=${pr.number}');

    // The mergeable flag may be null. False indicates there's a merge conflict,
    // null indicates unknown. Err on the side of allowing the job to run.
    if (pr.mergeable == false) {
      final RepositorySlug slug = pullRequestEvent.repository!.slug();
      final GitHub gitHubClient = await config.createGitHubClient(pullRequest: pr);
      final String body = config.mergeConflictPullRequestMessage;
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.issues.createComment(slug, pr.number!, body);
      }

      return;
    }

    await scheduler.triggerPresubmitTargets(pullRequest: pr);
  }

  Future<void> _checkForLabelsAndTests(PullRequestEvent pullRequestEvent) async {
    final PullRequest pr = pullRequestEvent.pullRequest!;
    final String? eventAction = pullRequestEvent.action;
    final String repo = pr.base!.repo!.fullName.toLowerCase();
    if (kNeedsCheckLabelsAndTests.contains(repo)) {
      final GitHub gitHubClient = await config.createGitHubClient(pullRequest: pr);
      try {
        await _validateRefs(gitHubClient, pr);
        if (repo == 'flutter/flutter') {
          await _applyFrameworkRepoLabels(gitHubClient, eventAction, pr);
        } else if (repo == 'flutter/engine') {
          await _applyEngineRepoLabels(gitHubClient, eventAction, pr);
        } else if (repo == 'flutter/plugins' || repo == 'flutter/packages') {
          await _applyPackageTestChecks(gitHubClient, eventAction, pr);
        }
      } finally {
        gitHubClient.dispose();
      }
    }
  }

  Future<void> _applyFrameworkRepoLabels(GitHub gitHubClient, String? eventAction, PullRequest pr) async {
    if (pr.user!.login == 'engine-flutter-autoroll') {
      return;
    }

    final RepositorySlug slug = pr.base!.repo!.slug();
    log.info('Applying framework repo labels for: owner=${slug.owner} repo=${slug.name} and pr=${pr.number}');
    final Stream<PullRequestFile> files = gitHubClient.pullRequests.listFiles(slug, pr.number!);

    final Set<String> labels = <String>{};
    bool hasTests = false;
    bool needsTests = false;

    await for (PullRequestFile file in files) {
      // When null, do not assume 0 lines have been added.
      final int linesAdded = file.additionsCount ?? 1;
      final int linesDeleted = file.deletionsCount ?? 0;
      final int linesTotal = file.changesCount ?? linesDeleted + linesAdded;
      final bool addedCode = linesAdded > 0 || linesDeleted != linesTotal;

      if (addedCode &&
          !file.filename!.contains('AUTHORS') &&
          !file.filename!.contains('pubspec.yaml') &&
          !file.filename!.contains('.ci.yaml') &&
          !file.filename!.contains('.github') &&
          !file.filename!.endsWith('.md') &&
          !file.filename!.startsWith('dev/devicelab/bin/tasks') &&
          !file.filename!.startsWith('dev/devicelab/lib/tasks') &&
          !file.filename!.startsWith('dev/bots/')) {
        needsTests = true;
      }

      if (file.filename!.endsWith('_test.dart') ||
          file.filename!.endsWith('.expect') ||
          file.filename!.contains('test_fixes')) {
        hasTests = true;
      }
      labels.addAll(getLabelsForFrameworkPath(file.filename!));
    }

    if (pr.user!.login == 'fluttergithubbot') {
      needsTests = false;
      labels.addAll(<String>['team', 'tech-debt', 'team: flakes']);
    }

    if (labels.isNotEmpty) {
      await gitHubClient.issues.addLabelsToIssue(slug, pr.number!, labels.toList());
    }

    if (!hasTests && needsTests && !pr.draft!) {
      final String body = config.missingTestsPullRequestMessage;
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.issues.createComment(slug, pr.number!, body);
      }
    }
  }

  /// Returns the set of labels applicable to a file in the framework repo.
  static Set<String> getLabelsForFrameworkPath(String filepath) {
    final Set<String> labels = <String>{};
    if (filepath.endsWith('pubspec.yaml')) {
      // These get updated by a script, and are updated en masse.
      labels.add('team');
      return labels;
    }

    if (filepath.endsWith('fix_data.yaml') || filepath.endsWith('.expect') || filepath.contains('test_fixes')) {
      // Dart fixes
      labels.add('team');
      labels.add('tech-debt');
    }

    const Map<String, List<String>> pathPrefixLabels = <String, List<String>>{
      'bin/internal/engine.version': <String>['engine'],
      'dev/': <String>['team'],
      'examples/': <String>['d: examples', 'team'],
      'examples/api/': <String>['d: examples', 'team', 'd: api docs', 'documentation'],
      'examples/flutter_gallery/': <String>['d: examples', 'team', 'team: gallery'],
      'packages/flutter_tools/': <String>['tool'],
      'packages/flutter/': <String>['framework'],
      'packages/flutter_driver/': <String>['framework', 'a: tests'],
      'packages/flutter_localizations/': <String>['a: internationalization'],
      'packages/flutter_goldens/': <String>['framework', 'a: tests', 'team'],
      'packages/flutter_goldens_client/': <String>['framework', 'a: tests', 'team'],
      'packages/flutter_test/': <String>['framework', 'a: tests'],
      'packages/fuchsia_remote_debug_protocol/': <String>['tool'],
      'packages/integration_test/': <String>['integration_test'],
    };
    const Map<String, List<String>> pathContainsLabels = <String, List<String>>{
      'accessibility': <String>['a: accessibility'],
      'animation': <String>['a: animation'],
      'cupertino': <String>['f: cupertino'],
      'focus': <String>['f: focus'],
      'gestures': <String>['f: gestures'],
      'material': <String>['f: material design'],
      'navigator': <String>['f: routes'],
      'route': <String>['f: routes'],
      'scroll': <String>['f: scrolling'],
      'semantics': <String>['a: accessibility'],
      'sliver': <String>['f: scrolling'],
      'text': <String>['a: text input'],
      'viewport': <String>['f: scrolling'],
    };

    pathPrefixLabels.forEach((String path, List<String> pathLabels) {
      if (filepath.startsWith(path)) {
        labels.addAll(pathLabels);
      }
    });
    pathContainsLabels.forEach((String path, List<String> pathLabels) {
      if (filepath.contains(path)) {
        labels.addAll(pathLabels);
      }
    });
    return labels;
  }

  /// Returns the set of labels applicable to a file in the engine repo.
  static Set<String> getLabelsForEnginePath(String filepath) {
    const Map<String, List<String>> pathPrefixLabels = <String, List<String>>{
      'shell/platform/android': <String>['platform-android'],
      'shell/platform/embedder': <String>['embedder'],
      'shell/platform/darwin/common': <String>['platform-ios', 'platform-macos'],
      'shell/platform/darwin/ios': <String>['platform-ios'],
      'shell/platform/darwin/macos': <String>['platform-macos'],
      'shell/platform/fuchsia': <String>['platform-fuchsia'],
      'shell/platform/linux': <String>['platform-linux'],
      'shell/platform/windows': <String>['platform-windows'],
      'lib/web_ui': <String>['platform-web'],
      'web_sdk': <String>['platform-web'],
    };
    final Set<String> labels = <String>{};
    pathPrefixLabels.forEach((String path, List<String> pathLabels) {
      if (filepath.startsWith(path)) {
        labels.addAll(pathLabels);
      }
    });
    return labels;
  }

  Future<void> _applyEngineRepoLabels(GitHub gitHubClient, String? eventAction, PullRequest pr) async {
    if (pr.user!.login == 'skia-flutter-autoroll') {
      return;
    }
    final RepositorySlug slug = pr.base!.repo!.slug();
    final Stream<PullRequestFile> files = gitHubClient.pullRequests.listFiles(slug, pr.number!);
    final Set<String> labels = <String>{};
    bool hasTests = false;
    bool needsTests = false;

    await for (PullRequestFile file in files) {
      final String filename = file.filename!.toLowerCase();
      if (filename.endsWith('.dart') ||
          filename.endsWith('.mm') ||
          filename.endsWith('.m') ||
          filename.endsWith('.java') ||
          filename.endsWith('.cc')) {
        needsTests = true;
      }

      if (kEngineTestRegExp.hasMatch(filename)) {
        hasTests = true;
      }

      labels.addAll(getLabelsForEnginePath(filename));
    }

    if (labels.isNotEmpty) {
      await gitHubClient.issues.addLabelsToIssue(slug, pr.number!, labels.toList());
    }

    if (!hasTests && needsTests && !pr.draft!) {
      final String body = config.missingTestsPullRequestMessage;
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.issues.createComment(slug, pr.number!, body);
        await gitHubClient.issues.addLabelsToIssue(slug, pr.number!, kNeedsTestsLabels);
      }
    }
  }

  // Runs automated test checks for both flutter/packages and flutter/plugins.
  Future<void> _applyPackageTestChecks(GitHub gitHubClient, String? eventAction, PullRequest pr) async {
    final RepositorySlug slug = pr.base!.repo!.slug();
    final Stream<PullRequestFile> files = gitHubClient.pullRequests.listFiles(slug, pr.number!);
    bool hasTests = false;
    bool needsTests = false;

    await for (PullRequestFile file in files) {
      final String filename = file.filename!;

      // When null, do not assume 0 lines have been added.
      final int linesAdded = file.additionsCount ?? 1;
      final int linesDeleted = file.deletionsCount ?? 0;
      final int linesTotal = file.changesCount ?? linesDeleted + linesAdded;
      final bool addedCode = linesAdded > 0 || linesDeleted != linesTotal;

      if (addedCode &&
          !filename.endsWith('AUTHORS') &&
          !filename.endsWith('CODEOWNERS') &&
          !filename.endsWith('pubspec.yaml') &&
          !filename.endsWith('.ci.yaml') &&
          !filename.endsWith('.cirrus.yml') &&
          !filename.contains('.ci/') &&
          !filename.contains('.github/') &&
          !filename.endsWith('.md')) {
        needsTests = !_allChangesAreCodeComments(file);
      }

      // See https://github.com/flutter/flutter/wiki/Plugin-Tests for discussion
      // of various plugin test types and locations.
      if (filename.endsWith('_test.dart') ||
          // Native iOS/macOS tests.
          filename.contains('RunnerTests/') ||
          filename.contains('RunnerUITests/') ||
          // Native Android tests.
          filename.contains('android/src/test/') ||
          filename.contains('androidTest/') ||
          // Native Linux tests.
          filename.endsWith('_test.cc') ||
          // Native Windows tests.
          filename.endsWith('_test.cpp')) {
        hasTests = true;
      }
    }

    if (!hasTests && needsTests && !pr.draft!) {
      final String body = config.missingTestsPullRequestMessage;
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.issues.createComment(slug, pr.number!, body);
        await gitHubClient.issues.addLabelsToIssue(slug, pr.number!, kNeedsTestsLabels);
      }
    }
  }

  /// Validate the base and head refs of the PR.
  Future<void> _validateRefs(
    GitHub gitHubClient,
    PullRequest pr,
  ) async {
    final RepositorySlug slug = pr.base!.repo!.slug();
    String body;
    const List<String> releaseChannels = <String>[
      'stable',
      'beta',
      'dev',
    ];
    // Close PRs that use a release branch as a source.
    if (releaseChannels.contains(pr.head!.ref)) {
      body = config.wrongHeadBranchPullRequestMessage(pr.head!.ref!);
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.pullRequests.edit(
          slug,
          pr.number!,
          state: 'closed',
        );
        await gitHubClient.issues.createComment(slug, pr.number!, body);
      }
      return;
    }
    if (Config.defaultBranch(pr.base!.repo!.slug()) == pr.base!.ref!) {
      return;
    }
    final RegExp candidateTest = RegExp(r'flutter-\d+\.\d+-candidate\.\d+');
    if (candidateTest.hasMatch(pr.base!.ref!) && candidateTest.hasMatch(pr.head!.ref!)) {
      // This is most likely a release branch
      body = config.releaseBranchPullRequestMessage;
      if (!await _alreadyCommented(gitHubClient, pr, body)) {
        await gitHubClient.issues.createComment(slug, pr.number!, body);
      }
      return;
    }

    // Assume this PR should be based against config.defaultBranch.
    body = _getWrongBaseComment(pr.base!.ref!);
    if (!await _alreadyCommented(gitHubClient, pr, body)) {
      await gitHubClient.pullRequests.edit(
        slug,
        pr.number!,
        base: Config.defaultBranch(slug),
      );
      await gitHubClient.issues.createComment(slug, pr.number!, body);
    }
  }

  Future<bool> _alreadyCommented(
    GitHub gitHubClient,
    PullRequest pr,
    String message,
  ) async {
    final Stream<IssueComment> comments = gitHubClient.issues.listCommentsByIssue(pr.base!.repo!.slug(), pr.number!);
    await for (IssueComment comment in comments) {
      if (comment.body != null && comment.body!.contains(message)) {
        return true;
      }
    }
    return false;
  }

  String _getWrongBaseComment(String base) {
    final String messageTemplate = config.wrongBaseBranchPullRequestMessage;
    return messageTemplate.replaceAll('{{branch}}', base);
  }

  Future<bool> _validateRequest(
    String? signature,
    List<int> requestBody,
  ) async {
    final String rawKey = await config.webhookKey;
    final List<int> key = utf8.encode(rawKey);
    final Hmac hmac = Hmac(sha1, key);
    final Digest digest = hmac.convert(requestBody);
    final String bodySignature = 'sha1=$digest';
    return bodySignature == signature;
  }

  Future<PullRequestEvent?> _getPullRequestEvent(String request) async {
    try {
      return PullRequestEvent.fromJson(json.decode(request) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  /// Returns true if the changes to [file] are all code comments.
  ///
  /// If that cannot be determined with confidence, returns false. False
  /// negatives (e.g., for /* */-style multi-line comments) should be expected.
  bool _allChangesAreCodeComments(PullRequestFile file) {
    final int? linesAdded = file.additionsCount;
    final int? linesDeleted = file.deletionsCount;
    final String? patch = file.patch;
    // If information is missing, err or the side of assuming it's a non-comment
    // change.
    if (linesAdded == null || linesDeleted == null || patch == null) {
      return false;
    }

    // Ensure that the file is a language reconized by the check below.
    const Set<String> codeExtensions = <String>{
      'cc',
      'cpp',
      'dart',
      'java',
      'kt',
      'm',
      'mm',
      'swift',
    };
    final String filename = file.filename!;
    final String? extension = filename.contains('.') ? filename.split('.').last.toLowerCase() : null;
    if (extension == null || !codeExtensions.contains(extension)) {
      return false;
    }

    // Only handles single-line comments; identifying multi-line comments
    // would require the full file and non-trivial parsing. Also doesn't handle
    // end-of-line comments (e.g., "int x = 0; // Info about x").
    final RegExp commentRegex = RegExp(r'[+-]\s*//');
    for (String line in patch.split('\n')) {
      if (!line.startsWith('+') && !line.startsWith('-')) {
        continue;
      }
      if (!commentRegex.hasMatch(line)) {
        return false;
      }
    }
    return true;
  }
}
