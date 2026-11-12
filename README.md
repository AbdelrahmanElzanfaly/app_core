# app_core

What every feature of an app needs, in one package:

| | |
|---|---|
| `AppConfig`, `Environment` | per-flavor configuration, set once in `main()` |
| `AppFailure`, `Result`, `FutureUseCase` | one error type; repositories return `Result`, never throw |
| `BaseBloc`, `StateView`, `SingleEffect` | loading overlay and error snack bars for free; one-shot effects |
| `StateViewScope` | how every `StateView` presents its failures, set once by the app |
| `SessionService` | the signed-in session: secure storage, router refresh, token renewal |
| `NetworkMonitor`, `NetworkScope`, `ReconnectListener` | whether the servers can be reached; reload a page when they can again |
| `SessionCache` | small offline copies of read models, emptied when the session ends |
| `AppSettingsCubit` | theme and language, persisted |
| `CoreLocalizations` | Arabic and English copy for every failure type |
| `AppCorePackageModule` | registers all of the above with injectable |

Register it first in the app's composition root:

```dart
@InjectableInit(
  externalPackageModulesBefore: [ExternalModule(AppCorePackageModule)],
)
```

Depends on `app_network`.

The module's `Dio` is the app's client: it renews on 401, retries failed
GET/HEAD/OPTIONS requests (`RetryPolicy()`; writes are never resent), opens
connections with a 10 s timeout (`NetworkConfig.recommendedConnectTimeout`),
fails at once while the device has no network, and reports every request's
outcome to the `NetworkMonitor`.

## Error presentation

`StateView` shows each failure from `BaseBloc.errors` as a plain snack bar
with `CoreLocalizations`' copy. To give every screen the app's own style, put
a `StateViewScope` in `MaterialApp.builder`; each `StateView` below then
hands its failures to `onError` instead:

```dart
MaterialApp.router(
  builder: (context, child) => StateViewScope(
    onError: (context, failure) => showMyErrorSnackBar(
      context,
      CoreLocalizations.of(context).describe(failure),
    ),
    child: child!,
  ),
);
```

`onError` receives the `StateView`'s own context, which is below the theme,
the localizations and the `ScaffoldMessenger`. Without a scope nothing
changes.

## Pull to refresh

`BaseBloc.refresh(event)` dispatches a reload and returns a future that completes
when its handler finishes, so feature blocs do not need their own completer or
lifecycle overrides:

```dart
on<HomeRequested>(_onRequested, transformer: droppable());

// In the page:
RefreshIndicator(
  onRefresh: () => context.read<HomeBloc>().refresh(const HomeRequested()),
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [...],
  ),
);
```

Use a dedicated reload event with `droppable()` from `bloc_concurrency`.
Repeated refresh calls for the same concrete event type share a future; if a
normal load is already running, the refresh waits for it. Unrelated event types
complete independently. The handler must await its work. Errors continue through
the existing error channel and feature state, and the refresh future finishes
after either success or failure. Closing the bloc releases all pending refresh
callbacks and subsequent refresh calls do nothing.

This API coalesces reloads by concrete event type, not by event payload. It is not
intended for concurrent, sequential, or restartable parameterized operations and
does not cancel HTTP requests. Lifecycle overrides must call `super`.

## Offline

**Startup.** Start the monitor once in `main()`, after `SessionService.restore()`
and before `runApp`, so the connectivity gate and any banner are right from the
first frame. The first reading is bounded (500 ms); a slow or failing platform
counts as online.

```dart
await getIt<SessionService>().restore();
await getIt<NetworkMonitor>().start();
```

**Reachability.** `NetworkMonitor.reachability` is `online`, `offline` (the
device reports no interface, for longer than a 2 s grace) or `unreachable` (an
interface is up but the last request got no answer). Real traffic beats the OS
reading: any answer from the server means online. Put it in the tree with
`NetworkScope(monitor: ..., child: ...)`, usually in `MaterialApp.builder`;
`NetworkScope.reachabilityOf(context)` is online when there is no scope.

**Reload on reconnect.** `NetworkMonitor.reconnected` fires, at most once per
3 s, when a network appears (after a 1 s settle), when the app returns from the
background while not online, or when a request gets through after a failure. A
drop shorter than the 2 s grace announces nothing, unless the gate refused a
request during it. A device page wraps its own `Scaffold`:

```dart
ReconnectListener(
  // Only a failure or a saved copy has anything to recover.
  enabled: state.hasFailed || savedAt != null,
  busy: bloc.loading,
  onReconnect: () => bloc.add(const HomeRequested()), // a droppable load
  child: Scaffold(...),
)
```

A reconnect that arrives while `busy` is remembered and fired once, after the
frame in which the load ended, if the page still has something to recover. If
only a request getting through announced it, that request may have been the
load itself (a 503, say), so it fires only if the load then failed on the
transport, leaving the monitor no longer online. It never fires on its own for
a write: give it only an idempotent load.

**Offline copies.** A repository may keep the last answer of a read model
approved for offline display in `SessionCache`, and fall back to it when
`AppFailure.isTransient` (network, timeout, server); never for 401, 403 or
other rejections, and never for writes, payments or secrets. Take `generation`
before the request and pass it to `write`, so an answer that lands after
sign-out, or under the next session, is dropped. `read` returns the copy with
its `savedAt`, which the screen must show. Entries are versioned, capped at
64 KiB, and expire after `maxAge`.

By default copies live in memory for this run only (`MemorySessionCache`).
`AppConfig.persistOfflineCache: true` keeps them encrypted on disk, this
device only (`SecureSessionCache`, under its own Keychain service and Android
namespace); storing account data on the device is a security and compliance
decision.

**Session clearing.** `SessionService` empties the cache when the session
ends (sign-out, or a refresh token the server rejects) before the tokens are
deleted and before the router is notified, and sweeps it again at launch when
no session is stored. A clear that fails is retried before the cache's next
read or write; until one succeeds, the cache hands out and keeps nothing. Other
stores holding the user's data implement `SessionScoped` and are passed to
`SessionService(scoped: [...])`.
