// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: always_specify_types, implicit_dynamic_parameter

part of 'push_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushMessageEnvelope _$PushMessageEnvelopeFromJson(Map<String, dynamic> json) => PushMessageEnvelope(
      message: json['message'] == null ? null : PushMessage.fromJson(json['message'] as Map<String, dynamic>),
      subscription: json['subscription'] as String?,
    );

Map<String, dynamic> _$PushMessageEnvelopeToJson(PushMessageEnvelope instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message', instance.message);
  writeNotNull('subscription', instance.subscription);
  return val;
}

PushMessage _$PushMessageFromJson(Map<String, dynamic> json) => PushMessage(
      attributes: (json['attributes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      data: json['data'] as String?,
      messageId: json['messageId'] as String?,
    );

Map<String, dynamic> _$PushMessageToJson(PushMessage instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('attributes', instance.attributes);
  writeNotNull('data', instance.data);
  writeNotNull('messageId', instance.messageId);
  return val;
}

BuildPushMessage _$BuildPushMessageFromJson(Map<String, dynamic> json) => BuildPushMessage(
      build: json['build'] == null ? null : Build.fromJson(json['build'] as Map<String, dynamic>),
      hostname: json['hostname'] as String?,
      userData: json['user_data'] as String?,
    );

Map<String, dynamic> _$BuildPushMessageToJson(BuildPushMessage instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('build', instance.build);
  writeNotNull('hostname', instance.hostname);
  writeNotNull('user_data', instance.userData);
  return val;
}

Build _$BuildFromJson(Map<String, dynamic> json) => Build(
      bucket: json['bucket'] as String?,
      canary: json['canary'] as bool?,
      canaryPreference: $enumDecodeNullable(_$CanaryPreferenceEnumMap, json['canary_preference']),
      cancelationReason: $enumDecodeNullable(_$CancelationReasonEnumMap, json['cancelation_reason']),
      completedTimestamp: const MillisecondsSinceEpochConverter().fromJson(json['completed_ts'] as String?),
      createdBy: json['created_by'] as String?,
      createdTimestamp: const MillisecondsSinceEpochConverter().fromJson(json['created_ts'] as String?),
      failureReason: $enumDecodeNullable(_$FailureReasonEnumMap, json['failure_reason']),
      experimental: json['experimental'] as bool?,
      id: json['id'] as String?,
      buildParameters: const NestedJsonConverter().fromJson(json['parameters_json'] as String?),
      project: json['project'] as String?,
      result: $enumDecodeNullable(_$ResultEnumMap, json['result']),
      resultDetails: const NestedJsonConverter().fromJson(json['result_details_json'] as String?),
      serviceAccount: json['service_account'] as String?,
      startedTimestamp: const MillisecondsSinceEpochConverter().fromJson(json['started_ts'] as String?),
      status: $enumDecodeNullable(_$StatusEnumMap, json['status']),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      updatedTimestamp: const MillisecondsSinceEpochConverter().fromJson(json['updated_ts'] as String?),
      utcNowTimestamp: const MillisecondsSinceEpochConverter().fromJson(json['utcnow_ts'] as String?),
      url: json['url'] as String?,
    );

Map<String, dynamic> _$BuildToJson(Build instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('bucket', instance.bucket);
  writeNotNull('canary', instance.canary);
  writeNotNull('canary_preference', _$CanaryPreferenceEnumMap[instance.canaryPreference]);
  writeNotNull('cancelation_reason', _$CancelationReasonEnumMap[instance.cancelationReason]);
  writeNotNull('completed_ts', const MillisecondsSinceEpochConverter().toJson(instance.completedTimestamp));
  writeNotNull('created_by', instance.createdBy);
  writeNotNull('created_ts', const MillisecondsSinceEpochConverter().toJson(instance.createdTimestamp));
  writeNotNull('experimental', instance.experimental);
  writeNotNull('failure_reason', _$FailureReasonEnumMap[instance.failureReason]);
  writeNotNull('id', instance.id);
  writeNotNull('parameters_json', const NestedJsonConverter().toJson(instance.buildParameters));
  writeNotNull('project', instance.project);
  writeNotNull('result', _$ResultEnumMap[instance.result]);
  writeNotNull('result_details_json', const NestedJsonConverter().toJson(instance.resultDetails));
  writeNotNull('service_account', instance.serviceAccount);
  writeNotNull('started_ts', const MillisecondsSinceEpochConverter().toJson(instance.startedTimestamp));
  writeNotNull('status', _$StatusEnumMap[instance.status]);
  writeNotNull('tags', instance.tags);
  writeNotNull('updated_ts', const MillisecondsSinceEpochConverter().toJson(instance.updatedTimestamp));
  writeNotNull('url', instance.url);
  writeNotNull('utcnow_ts', const MillisecondsSinceEpochConverter().toJson(instance.utcNowTimestamp));
  return val;
}

const _$CanaryPreferenceEnumMap = {
  CanaryPreference.auto: 'AUTO',
  CanaryPreference.canary: 'CANARY',
  CanaryPreference.prod: 'PROD',
};

const _$CancelationReasonEnumMap = {
  CancelationReason.canceledExplicitly: 'CANCELED_EXPLICITLY',
  CancelationReason.timeout: 'TIMEOUT',
};

const _$FailureReasonEnumMap = {
  FailureReason.buildbucketFailure: 'BUILDBUCKET_FAILURE',
  FailureReason.buildFailure: 'BUILD_FAILURE',
  FailureReason.infraFailure: 'INFRA_FAILURE',
  FailureReason.invalidBuildDefinition: 'INVALID_BUILD_DEFINITION',
};

const _$ResultEnumMap = {
  Result.canceled: 'CANCELED',
  Result.failure: 'FAILURE',
  Result.success: 'SUCCESS',
};

const _$StatusEnumMap = {
  Status.completed: 'COMPLETED',
  Status.scheduled: 'SCHEDULED',
  Status.started: 'STARTED',
};
