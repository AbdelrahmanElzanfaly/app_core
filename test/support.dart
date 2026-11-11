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

/// The OS interface list, scripted: [isUp] answers [up] (after [delay], or
/// by throwing [error]), and [emit] reports a change.
class FakeNetworkInterfaces implements NetworkInterfaces {
  FakeNetworkInterfaces({this.up = true});

  bool up;
  Object? error;
  Duration? delay;
  int reads = 0;

  final StreamController<bool> _changes = StreamController.broadcast();

  bool get hasListener => _changes.hasListener;

  @override
  Future<bool> isUp() async {
    reads++;
    final delay = this.delay;
    if (delay != null) await Future<void>.delayed(delay);
    final error = this.error;
    if (error != null) throw error;
    return up;
  }

  @override
  Stream<bool> get changes => _changes.stream;

  void emit(bool value) {
    up = value;
    _changes.add(value);
  }
}

/// A server that cannot be reached: every attempt fails to connect. Throws
/// the [DioException] itself, as dio's own adapter does; anything else a
/// custom adapter throws becomes `unknown`.
class UnreachableServer implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'Connection refused',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Records what a [SessionService] tells a session-scoped store into [log],
/// shared so it interleaves with other events. [onEnd] runs inside
/// [onSessionEnded], and may throw.
class RecordingScoped implements SessionScoped {
  RecordingScoped(this.log, {this.name = '', this.onEnd});

  final List<String> log;
  final String name;
  final Future<void> Function()? onEnd;

  @override
  void onSessionStarted() => log.add('${name}started');

  @override
  Future<void> onSessionEnded() async {
    log.add('${name}ended');
    await onEnd?.call();
  }
}
