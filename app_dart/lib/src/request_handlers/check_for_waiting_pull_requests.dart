// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:github/github.dart';
import 'package:graphql/client.dart';
import 'package:meta/meta.dart';

import '../request_handling/api_request_handler.dart';
import '../request_handling/authentication.dart';
import '../request_handling/body.dart';
import '../request_handling/exceptions.dart';
import '../service/config.dart';
import '../service/logging.dart';
import 'check_for_waiting_pull_requests_queries.dart';
import 'refresh_cirrus_status.dart';

/// Maximum number of pull requests to merge on each check.
/// This should be kept reasonably low to avoid flooding infra when the tree
/// goes green.
const int _kMergeCountPerCycle = 2;

/// Injected latency per repository. Engine and Flutter use an injected latency of 1h meaning
/// that the bot skips any commits younger than 1h. However 1h is too long for some repositories
/// whose builds are faster. Use this constant to override the default 1h latency for a given repository.
const Map<String, Duration> _kInjectedLatencies = <String, Duration>{
  'cocoon': Duration(minutes: 10),
  'packages': Duration(minutes: 10)
};

@immutable
class CheckForWaitingPullRequests extends ApiRequestHandler<Body> {
  const CheckForWaitingPullRequests(
    Config config,
    AuthenticationProvider authenticationProvider,
  ) : super(config: config, authenticationProvider: authenticationProvider);

  @override
  Future<Body> get() async {
    final GraphQLClient client = await config.createGitHubGraphQLClient();

    for (RepositorySlug slug in Config.supportedRepos) {
      try {
        log.info('Checking PRs for $slug');
        await _checkPRs(slug, client);
      } catch (e) {
        log.warning('_checkPRs error in $slug: $e');
      }
    }
    return Body.empty;
  }

  Future<void> _checkPRs(
    RepositorySlug slug,
    GraphQLClient client,
  ) async {
    if (_kMergeCountPerCycle == 0) {
      log.info('_kMergeCountPerCycle is set to 0, skipping PR check.');
      return;
    }
    int mergeCount = 0;
    final Map<String, dynamic> data = await _queryGraphQL(
      slug,
      client,
    );
    final List<_AutoMergeQueryResult> queryResults = await _parseQueryData(data, slug.name);
    for (_AutoMergeQueryResult queryResult in queryResults) {
      if (mergeCount < _kMergeCountPerCycle && queryResult.shouldMerge) {
        final bool merged = await _mergePullRequest(
          queryResult.graphQLId,
          queryResult.sha,
          queryResult.number,
          queryResult.title,
          client,
        );
        if (merged) {
          mergeCount++;
        }
      } else if (queryResult.shouldRemoveLabel) {
        log.info('Removing label: ${queryResult.labelId} for commit: ${queryResult.sha}');
        await _removeLabel(
          queryResult.graphQLId,
          queryResult.removalMessage,
          queryResult.labelId,
          client,
        );
      }
    }
  }

  Future<Map<String, dynamic>> _queryGraphQL(
    RepositorySlug slug,
    GraphQLClient client,
  ) async {
    final String labelName = config.waitingForTreeToGoGreenLabelName;

    final QueryResult result = await client.query(
      QueryOptions(
        document: labeledPullRequestsWithReviewsQuery,
        fetchPolicy: FetchPolicy.noCache,
        variables: <String, dynamic>{
          'sOwner': slug.owner,
          'sName': slug.name,
          'sLabelName': labelName,
        },
      ),
    );

    if (result.hasException) {
      log.severe(result.exception.toString());
      throw const BadRequestException('GraphQL query failed');
    }
    return result.data!;
  }

  Future<bool> _removeLabel(
    String id,
    String message,
    String labelId,
    GraphQLClient client,
  ) async {
    final QueryResult result = await client.mutate(MutationOptions(
      document: removeLabelMutation,
      variables: <String, dynamic>{
        'id': id,
        'sBody': message,
        'labelId': labelId,
      },
    ));
    if (result.hasException) {
      log.severe(result.exception.toString());
      return false;
    }
    return true;
  }

  Future<bool> _mergePullRequest(
    String id,
    String sha,
    int number,
    String title,
    GraphQLClient client,
  ) async {
    final QueryResult result = await client.mutate(MutationOptions(
      document: mergePullRequestMutation,
      variables: <String, dynamic>{
        'id': id,
        'oid': sha,
        'title': '$title (#$number)',
      },
    ));

    if (result.hasException) {
      log.severe(result.exception.toString());
      return false;
    }
    return true;
  }

  /// Parses a GraphQL query to a list of [_AutoMergeQueryResult]s.
  ///
  /// This method will not return null, but may return an empty list.
  Future<List<_AutoMergeQueryResult>> _parseQueryData(Map<String, dynamic> data, String name) async {
    final Map<String, dynamic>? repository = data['repository'] as Map<String, dynamic>?;
    if (repository == null || repository.isEmpty) {
      throw StateError('Query did not return a repository.');
    }

    final Map<String, dynamic>? label = repository['labels']['nodes'].single as Map<String, dynamic>?;
    if (label == null || label.isEmpty) {
      throw StateError('Query did not find information about the waitingForTreeToGoGreen label.');
    }
    final String? labelId = label['id'] as String?;
    log.info('LabelId of returned PRs: $labelId');
    final List<_AutoMergeQueryResult> list = <_AutoMergeQueryResult>[];
    final Iterable<Map<String, dynamic>> pullRequests =
        (label['pullRequests']['nodes'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (Map<String, dynamic> pullRequest in pullRequests) {
      log.info('Is pull request #${pullRequest['number']} mergeable: ${pullRequest['mergeable']}');
      // This is used to remove the bot label as it requires manual intervention.
      final bool isConflicting = pullRequest['mergeable'] == 'CONFLICTING';
      // This is used to skip landing until we are sure the PR is mergeable.
      final bool unknownMergeableState = pullRequest['mergeable'] == 'UNKNOWN';

      // List of labels associated with the pull request.
      final List<String> labels = ((pullRequest['labels']['nodes'] as List<dynamic>).cast<Map<String, dynamic>>())
          .map<String>((Map<String, dynamic> labelMap) => labelMap['name'] as String)
          .toList();

      final Map<String, dynamic> commit = pullRequest['commits']['nodes'].single['commit'] as Map<String, dynamic>;
      final int number = pullRequest['number'] as int;
      // Skip commits that are less than an hour old.
      // Use the committedDate if pushedDate is null (commitedDate cannot be null).
      final DateTime utcDate =
          DateTime.parse(commit['pushedDate'] as String? ?? (commit['committedDate'] as String?)!).toUtc();
      final Duration injectedDuration = _kInjectedLatencies[name] ?? const Duration(hours: 1);
      if (utcDate.add(injectedDuration).isAfter(DateTime.now().toUtc())) {
        log.info(
            'Skipping PR#$number because it needs to land after ${utcDate.add(injectedDuration)} and current time is ${DateTime.now().toUtc()}');
        continue;
      }
      final String? author = pullRequest['author']['login'] as String?;
      final String id = pullRequest['id'] as String;
      final String repoFullName = pullRequest['baseRepository']['nameWithOwner'] as String;
      final RepositorySlug slug = RepositorySlug.full(repoFullName);
      final String title = pullRequest['title'] as String;

      final Set<String?> changeRequestAuthors = <String?>{};
      final bool hasApproval = config.rollerAccounts.contains(author) ||
          _checkApproval(
            author,
            pullRequest['authorAssociation'] as String,
            (pullRequest['reviews']['nodes'] as List<dynamic>).cast<Map<String, dynamic>>(),
            changeRequestAuthors,
          );

      final String sha = commit['oid'] as String;
      List<Map<String, dynamic>>? statuses;
      if (commit['status'] != null &&
          commit['status']['contexts'] != null &&
          (commit['status']['contexts'] as List<dynamic>).isNotEmpty) {
        statuses = (commit['status']['contexts'] as List<dynamic>).cast<Map<String, dynamic>>();
      }
      statuses ??= <Map<String, dynamic>>[];
      List<Map<String, dynamic>>? checkRuns;
      if (commit['checkSuites']['nodes'] != null && (commit['checkSuites']['nodes'] as List<dynamic>).isNotEmpty) {
        checkRuns =
            (commit['checkSuites']['nodes']?.first['checkRuns']['nodes'] as List<dynamic>).cast<Map<String, dynamic>>();
      }
      checkRuns ??= <Map<String, dynamic>>[];
      final Set<_FailureDetail> failures = <_FailureDetail>{};
      final bool ciSuccessful = await _checkStatuses(
        slug,
        sha,
        failures,
        statuses,
        checkRuns,
        name,
        'pull/$number',
        labels,
      );

      list.add(_AutoMergeQueryResult(
          graphQLId: id,
          ciSuccessful: ciSuccessful,
          failures: failures,
          hasApprovedReview: hasApproval,
          changeRequestAuthors: changeRequestAuthors,
          number: number,
          title: title,
          sha: sha,
          labelId: labelId!,
          emptyChecks: checkRuns.isEmpty,
          isConflicting: isConflicting,
          unknownMergeableState: unknownMergeableState,
          labels: labels));
    }
    return list;
  }

  /// Returns whether all statuses are successful.
  ///
  /// Also fills [failures] with the names of any status/check that has failed.
  Future<bool> _checkStatuses(
    RepositorySlug slug,
    String sha,
    Set<_FailureDetail> failures,
    List<Map<String, dynamic>> statuses,
    List<Map<String, dynamic>> checkRuns,
    String name,
    String branch,
    List<String> labels,
  ) async {
    assert(failures.isEmpty);
    bool allSuccess = true;

    // The status checks that are not related to changes in this PR.
    const Set<String> notInAuthorsControl = <String>{
      'luci-flutter', // flutter repo
      'luci-engine', // engine repo
      'submit-queue', // plugins repo
    };

    // Ensure repos with tree statuses have it set
    if (Config.reposWithTreeStatus.contains(slug)) {
      bool treeStatusExists = false;
      final String treeStatusName = 'luci-${slug.name}';

      // Scan list of statuses to see if the tree status exists (this list is expected to be <5 items)
      for (Map<String, dynamic> status in statuses) {
        if (status['context'] == treeStatusName) {
          treeStatusExists = true;
        }
      }

      if (!treeStatusExists) {
        failures.add(_FailureDetail('tree status $treeStatusName', 'https://flutter-dashboard.appspot.com/#/build'));
      }
    }

    log.info('Validating name: $name, branch: $branch, status: $statuses');
    for (Map<String, dynamic> status in statuses) {
      final String? name = status['context'] as String?;
      if (status['state'] != 'SUCCESS') {
        if (notInAuthorsControl.contains(name) && labels.contains(await config.overrideTreeStatusLabel)) {
          continue;
        }
        allSuccess = false;
        if (status['state'] == 'FAILURE' && !notInAuthorsControl.contains(name)) {
          failures.add(_FailureDetail(name!, status['targetUrl'] as String));
        }
      }
    }
    log.info('Validating name: $name, branch: $branch, checks: $checkRuns');
    for (Map<String, dynamic> checkRun in checkRuns) {
      final String? name = checkRun['name'] as String?;
      if (checkRun['conclusion'] == 'SUCCESS') {
        continue;
      } else if (checkRun['status'] == 'COMPLETED') {
        failures.add(_FailureDetail(name!, checkRun['detailsUrl'] as String));
      }
      allSuccess = false;
    }

    // Validate cirrus
    const List<String> _failedStates = <String>['FAILED', 'ABORTED'];
    const List<String> _succeededStates = <String>['COMPLETED', 'SKIPPED'];
    final GraphQLClient cirrusClient = await config.createCirrusGraphQLClient();
    final List<CirrusResult> cirrusResults = await queryCirrusGraphQL(sha, cirrusClient, name);
    if (!cirrusResults.any((CirrusResult cirrusResult) => cirrusResult.branch == branch)) {
      return allSuccess;
    }
    final List<Map<String, dynamic>>? cirrusStatuses =
        cirrusResults.firstWhere((CirrusResult cirrusResult) => cirrusResult.branch == branch).tasks;
    if (cirrusStatuses == null) {
      return allSuccess;
    }
    for (Map<String, dynamic> runStatus in cirrusStatuses) {
      final String? status = runStatus['status'] as String?;
      final String? name = runStatus['name'] as String?;
      final String? id = runStatus['id'] as String?;
      if (!_succeededStates.contains(status)) {
        allSuccess = false;
      }
      if (_failedStates.contains(status)) {
        failures.add(_FailureDetail(name!, 'https://cirrus-ci.com/task/$id'));
      }
    }

    return allSuccess;
  }
}

/// Parses the graphQL response reviews.
///
/// If author is a MEMBER or OWNER then it only requires a single review from
/// another MEMBER or OWNER. If the author is not a MEMBER or OWNER then it
/// requires two reviews from MEMBERs or OWNERS.
///
/// If there are any CHANGES_REQUESTED reviews, checks if the same author has
/// subsequently APPROVED.  From testing, dismissing a review means it won't
/// show up in this list since it will have a status of DISMISSED and we only
/// ask for CHANGES_REQUESTED or APPROVED - however, adding a new review does
/// not automatically dismiss the previous one (why, GitHub? Why?).
///
/// If the author has not subsequently approved or dismissed the review, the
/// name will be added to the changeRequestAuthors set.
///
/// Returns false if no approved reviews or any oustanding change request
/// reviews.
///
/// Returns true if at least one approved review and no outstanding change
/// request reviews.
bool _checkApproval(
  String? author,
  String authorAssociation,
  List<Map<String, dynamic>> reviewNodes,
  Set<String?> changeRequestAuthors,
) {
  assert(changeRequestAuthors.isEmpty);
  const Set<String> allowedReviewers = <String>{'MEMBER', 'OWNER'};
  final Set<String?> approvers = <String?>{};
  if (allowedReviewers.contains(authorAssociation)) {
    approvers.add(author);
  }
  for (Map<String, dynamic> review in reviewNodes) {
    // Ignore reviews from non-members/owners.
    if (!allowedReviewers.contains(review['authorAssociation'])) {
      continue;
    }

    // Reviews come back in order of creation.
    final String? state = review['state'] as String?;
    final String? authorLogin = review['author']['login'] as String?;
    if (state == 'APPROVED') {
      approvers.add(authorLogin);
      changeRequestAuthors.remove(authorLogin);
    } else if (state == 'CHANGES_REQUESTED') {
      changeRequestAuthors.add(authorLogin);
    }
  }
  return (approvers.length > 1) && changeRequestAuthors.isEmpty;
}

/// A model class describing the state of a pull request that has the "waiting
/// for tree to go green" label on it.
@immutable
class _AutoMergeQueryResult {
  const _AutoMergeQueryResult({
    required this.graphQLId,
    required this.hasApprovedReview,
    required this.changeRequestAuthors,
    required this.ciSuccessful,
    required this.failures,
    required this.number,
    required this.title,
    required this.sha,
    required this.labelId,
    required this.emptyChecks,
    required this.isConflicting,
    required this.unknownMergeableState,
    required this.labels,
  });

  /// The GitHub GraphQL ID of this pull request.
  final String graphQLId;

  /// Whether the pull request has at least one approved review.
  final bool hasApprovedReview;

  /// A set of login names that have at least one outstanding change request.
  final Set<String?> changeRequestAuthors;

  /// Whether CI has run successfully on the pull request.
  final bool ciSuccessful;

  /// A set of status/check names that have failed.
  final Set<_FailureDetail> failures;

  /// The pull request number.
  final int number;

  /// The pull request title.
  final String title;

  /// The git SHA to be merged.
  final String sha;

  /// The GitHub GraphQL ID of the waiting label.
  final String labelId;

  /// Whether the commit has checks or not.
  final bool emptyChecks;

  /// Whether the PR has conflicts or not.
  final bool isConflicting;

  /// Whether has an unknown mergeable state or not.
  final bool unknownMergeableState;

  /// List of labels associated with the PR.
  final List<String> labels;

  /// Whether it is sane to automatically merge this PR.
  bool get shouldMerge =>
      ciSuccessful &&
      failures.isEmpty &&
      hasApprovedReview &&
      changeRequestAuthors.isEmpty &&
      !emptyChecks &&
      !unknownMergeableState &&
      !isConflicting;

  /// Whether the auto-merge label should be removed from this PR.
  bool get shouldRemoveLabel =>
      !hasApprovedReview || changeRequestAuthors.isNotEmpty || failures.isNotEmpty || emptyChecks || isConflicting;

  String get removalMessage {
    if (!shouldRemoveLabel) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('This pull request is not suitable for automatic merging in its '
        'current state.');
    buffer.writeln();
    if (!hasApprovedReview && changeRequestAuthors.isEmpty) {
      buffer.writeln('- Please get at least one approved review if you are already '
          'a member or two member reviews if you are not a member before re-applying this '
          'label. __Reviewers__: If you left a comment approving, please use '
          'the "approve" review action instead.');
    }
    for (String? author in changeRequestAuthors) {
      buffer.writeln('- This pull request has changes requested by @$author. Please '
          'resolve those before re-applying the label.');
    }
    for (_FailureDetail detail in failures) {
      buffer.writeln('- The status or check suite ${detail.markdownLink} has failed. Please fix the '
          'issues identified (or deflake) before re-applying this label.');
    }
    if (emptyChecks) {
      buffer.writeln('- This commit has no checks. Please check that ci.yaml validation has started'
          ' and there are multiple checks. If not, try uploading an empty commit.');
    }
    if (isConflicting) {
      buffer.writeln('- This commit is not mergeable and has conflicts. Please'
          ' rebase your PR and fix all the conflicts.');
    }
    return buffer.toString();
  }

  @override
  String toString() {
    return '$runtimeType{PR#$number, '
        'id: $graphQLId, '
        'sha: $sha, '
        'ciSuccessful: $ciSuccessful, '
        'hasApprovedReview: $hasApprovedReview, '
        'changeRequestAuthors: $changeRequestAuthors, '
        'labelId: $labelId, '
        'emptyValidations: $emptyChecks, '
        'shouldMerge: $shouldMerge}';
  }
}

@override
class _FailureDetail {
  const _FailureDetail(this.name, this.url);

  final String name;
  final String url;

  String get markdownLink => '[$name]($url)';

  // TODO(dnfield): use Object.hash when it is available
  @override
  int get hashCode => 17 * 31 + name.hashCode * 31 + url.hashCode;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is _FailureDetail && other.name == name && other.url == url;
  }
}
