// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:cocoon_service/src/model/appengine/github_build_status_update.dart';
import 'package:cocoon_service/src/model/appengine/task.dart';
import 'package:cocoon_service/src/request_handlers/push_build_status_to_github.dart';
import 'package:cocoon_service/src/service/build_status_provider.dart';
import 'package:cocoon_service/src/service/config.dart';
import 'package:cocoon_service/src/service/datastore.dart';
import 'package:cocoon_service/src/service/luci.dart';
import 'package:gcloud/db.dart';
import 'package:github/github.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../src/bigquery/fake_tabledata_resource.dart';
import '../src/datastore/fake_config.dart';
import '../src/datastore/fake_datastore.dart';
import '../src/request_handling/api_request_handler_tester.dart';
import '../src/request_handling/fake_authentication.dart';
import '../src/service/fake_github_service.dart';
import '../src/service/fake_scheduler.dart';
import '../src/utilities/mocks.dart';

void main() {
  group('PushStatusToGithub', () {
    late FakeConfig config;
    late FakeDatastoreDB db;
    late ApiRequestHandlerTester tester;
    FakeClientContext clientContext;
    FakeAuthenticatedContext authContext;
    FakeTabledataResource tabledataResourceApi;
    late MockLuciService mockLuciService;
    late PushBuildStatusToGithub handler;
    MockGitHub github;
    MockPullRequestsService pullRequestsService;
    MockIssuesService issuesService;
    MockRepositoriesService repositoriesService;
    late List<PullRequest> prsFromGitHub;
    FakeGithubService githubService;
    late FakeScheduler scheduler;
    MockLuciBuildService mockLuciBuildService;

    late List<LuciBuilder> builders;

    PullRequest newPullRequest(int number, String sha, String baseRef, {bool draft = false}) {
      return PullRequest()
        ..number = 123
        ..head = (PullRequestHead()..sha = 'abc')
        ..base = (PullRequestHead()..ref = baseRef)
        ..draft = draft;
    }

    GithubBuildStatusUpdate newStatusUpdate(PullRequest pr, BuildStatus status) {
      return GithubBuildStatusUpdate(
        key: db.emptyKey.append(GithubBuildStatusUpdate, id: pr.number),
        repository: Config.flutterSlug.fullName,
        status: status.githubStatus,
        pr: pr.number!,
        head: pr.head!.sha,
        updates: 0,
      );
    }

    setUp(() async {
      clientContext = FakeClientContext();
      authContext = FakeAuthenticatedContext(clientContext: clientContext);
      clientContext.isDevelopmentEnvironment = false;
      githubService = FakeGithubService();
      tabledataResourceApi = FakeTabledataResource();
      db = FakeDatastoreDB();
      github = MockGitHub();
      pullRequestsService = MockPullRequestsService();
      issuesService = MockIssuesService();
      repositoriesService = MockRepositoriesService();
      mockLuciBuildService = MockLuciBuildService();
      config = FakeConfig(
        tabledataResource: tabledataResourceApi,
        githubService: githubService,
        dbValue: db,
        githubClient: github,
      );
      tester = ApiRequestHandlerTester(context: authContext);
      mockLuciService = MockLuciService();
      scheduler = FakeScheduler(config: config, ciYaml: exampleConfig);
      builders = await scheduler.getPostSubmitBuilders(exampleConfig);
      handler = PushBuildStatusToGithub(
        config,
        FakeAuthenticationProvider(clientContext: clientContext),
        mockLuciBuildService,
        luciServiceProvider: (_) => mockLuciService,
        datastoreProvider: (DatastoreDB db) => DatastoreService(config.db, 5),
        scheduler: scheduler,
      );

      when(github.pullRequests).thenReturn(pullRequestsService);
      when(github.issues).thenReturn(issuesService);
      when(github.repositories).thenReturn(repositoriesService);
      when(pullRequestsService.list(any, base: Config.defaultBranch(Config.flutterSlug))).thenAnswer((Invocation _) {
        return Stream<PullRequest>.fromIterable(prsFromGitHub);
      });
      when(repositoriesService.createStatus(any, any, any)).thenAnswer(
        (_) async => RepositoryStatus(),
      );
    });

    test('Update status in datastore - success to failure', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];

      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.success());
      config.db.values[status.key] = status;
      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
              commitSha: 'abc', ref: 'refs/heads/master', status: Task.statusFailed, buildNumber: 1, builderName: 'abc')
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });
      expect(status.status, 'success');
      await tester.get(handler);
      expect(status.status, 'failure');
      expect(status.updateTimeMillis, isNotNull);
    });

    test('update engine status in datastore for infra failure - success to failure', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];
      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.success());
      config.db.values[status.key] = status;
      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/master',
              status: Task.statusInfraFailure,
              buildNumber: 1,
              builderName: 'abc')
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });

      expect(status.status, 'success');
      await tester.get(handler);
      expect(status.status, 'failure');
      expect(status.updateTimeMillis, isNotNull);
    });

    test('update engine status in datastore with - failure to success', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];

      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.failure(const <String>['failed_test_1']));

      config.db.values[status.key] = status;

      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/master',
              status: Task.statusSucceeded,
              buildNumber: 1,
              builderName: 'abc')
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });

      expect(status.status, 'failure');
      await tester.get(handler);
      expect(status.status, 'success');
      expect(status.updateTimeMillis, isNotNull);
    });

    test('update engine status in datastore with - with several tasks', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];

      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.failure(const <String>['failed_test_1']));

      config.db.values[status.key] = status;
      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/master',
              status: Task.statusSucceeded,
              buildNumber: 1,
              builderName: 'abc'),
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/master',
              status: Task.statusFailed,
              buildNumber: 2,
              builderName: 'abc'),
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/master',
              status: Task.statusSucceeded,
              buildNumber: 3,
              builderName: 'efg'),
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });

      expect(status.status, 'failure');
      await tester.get(handler);
      // Last build is successful.
      expect(status.status, 'success');
      expect(status.updateTimeMillis, isNotNull);
    });

    test('update engine status ignoring failing flaky build', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];

      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.failure(const <String>['failed_test_1']));

      config.db.values[status.key] = status;
      builders.add(LuciBuilder(name: 'flaky', repo: Config.engineSlug.name, flaky: true));
      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
            commitSha: 'abc',
            ref: 'refs/heads/master',
            status: Task.statusSucceeded,
            buildNumber: 1,
            builderName: 'abc',
          ),
          const LuciTask(
            commitSha: 'abc',
            ref: 'refs/heads/master',
            status: Task.statusFailed,
            buildNumber: 1,
            builderName: 'flaky',
          ),
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });

      expect(status.status, 'failure');
      await tester.get(handler);
      // Last build is successful.
      expect(status.status, 'success');
      expect(status.updateTimeMillis, isNotNull);
    });

    test('non master tasks are ignored', () async {
      final PullRequest pr = newPullRequest(123, 'abc', 'master');
      prsFromGitHub = <PullRequest>[pr];
      config.supportedBranchesValue = <String>['master'];

      final GithubBuildStatusUpdate status = newStatusUpdate(pr, BuildStatus.success());

      config.db.values[status.key] = status;
      final Map<LuciBuilder, List<LuciTask>> luciTasks = Map<LuciBuilder, List<LuciTask>>.fromIterable(
        builders,
        key: (dynamic builder) => builder as LuciBuilder,
        value: (dynamic builder) => <LuciTask>[
          const LuciTask(
              commitSha: 'abc',
              ref: 'refs/heads/dev',
              status: Task.statusSucceeded,
              buildNumber: 1,
              builderName: 'abc'),
        ],
      );
      when(mockLuciService.getRecentTasks(builders: anyNamed('builders'))).thenAnswer((Invocation invocation) {
        return Future<Map<LuciBuilder, List<LuciTask>>>.value(luciTasks);
      });

      expect(status.status, 'success');
      await tester.get(handler);
      // Because the task was ignored and we didn't have an update report a failure status.
      expect(status.status, 'failure');
      expect(status.updateTimeMillis, isNotNull);
    });
  });
}
