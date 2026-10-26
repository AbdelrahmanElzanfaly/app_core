import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:app_core/app_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void setUpCore() {
  FlutterSecureStorage.setMockInitialValues({});
  AppConfig.initialize(
    (environment) => AppConfig(
      environment: environment,
      appName: 'test',
      baseUrl: 'https://api.test',
      applicationId: 'test',
      storageKey: 'test',
    ),
  );
}

AuthSession session(String access, [String refresh = 'refresh-1']) =>
    AuthSession(accessToken: access, refreshToken: refresh);

AppFailure get offline => const AppFailure(FailureType.network);

AppFailure get rejected => const AppFailure(
  FailureType.badRequest,
  code: 'invalid_grant',
  statusCode: 400,
);

/// Answers each renewal with the next queued outcome: an [AuthSession] to
/// return, or anything else to throw. An optional [gate] holds every answer
/// until it completes.
class FakeRefresher implements TokenRefresher {
  FakeRefresher(this.outcomes, {this.gate});

  final List<Object> outcomes;
  final Future<void>? gate;
  int calls = 0;

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    calls++;
    if (gate != null) await gate;
    final outcome = outcomes.removeAt(0);
    if (outcome is AuthSession) return outcome;
    throw outcome;
  }
}

/// A server that accepts exactly one access token.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.validToken);

  String validToken;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final ok = options.headers['Authorization'] == 'Bearer $validToken';
    return ResponseBody.fromString(
      jsonEncode({'items': ok ? 42 : null}),
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Completer<void> gate() => Completer<void>();
