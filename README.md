# app_core

What every feature of an app needs, in one package:

| | |
|---|---|
| `AppConfig`, `Environment` | per-flavor configuration, set once in `main()` |
| `AppFailure`, `Result`, `FutureUseCase` | one error type; repositories return `Result`, never throw |
| `BaseBloc`, `StateView`, `SingleEffect` | loading overlay and error snack bars for free; one-shot effects |
| `AppMessenger`, `AppMessageTheme` | `context.showSuccess/showError/showWarning/showInfo`, styled from the theme |
| `SessionService` | the signed-in session: secure storage, router refresh, token renewal |
| `NetworkMonitor`, `NetworkScope`, `ReconnectListener` | whether the servers can be reached, and whether they can serve; reload a page when they can again |
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
outcome to the `NetworkMonitor`: whether the server was reached, and whether
it could serve.

## Errors

`BaseBloc.handleError(error)` publishes the failure on `errors`, and
`StateView` shows it as a snack bar. Pass `showMessage: false` for a failure
the page already presents itself, inline or in a dialog; nothing is
published, and the feature's own state handling is unchanged:

```dart
emit(state.copyWith(hasFailed: true));
handleError(result.error!, showMessage: false); // the page shows RoxRetryView
```

The default is `true`, so existing calls keep showing their message.

## Messages

Short messages go through one API, from any context below a
`ScaffoldMessenger`:

```dart
context.showSuccess(l10n.saved);
context.showWarning(l10n.outOfStock(name));
context.showError(message, actionLabel: l10n.retry, onAction: retry);
context.showInfo(message);
```

By default each `AppMessageType` has this icon and duration:

| Type | Icon | Duration |
|---|---|---|
| success | `check_circle_rounded` | 3 s |
| warning | `warning_amber_rounded` | 5 s |
| error | `error_rounded` | 6 s |
| info | `info_rounded` | 4 s |

A new message replaces the one on screen. `StateView` shows its failures
with `showError`, so every screen's errors look the same.

The whole look comes from the theme: each type's colours, icon and
duration, and the gap between the icon and the text. Set it once in the
app's `ThemeData`:

```dart
ThemeData(
  colorScheme: scheme,
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  extensions: [
    AppMessageTheme.seeded(
      scheme,
      success: brandGreen,
      warning: brandAmber,
      iconSpacing: 8, // the app's spacing token
    ),
  ],
);
```

`seeded` derives success and warning from their seeds for the scheme's
brightness, so the text keeps its contrast in light and dark. Error uses the
scheme's error container, and info Material's own snack bar colours. Change
one type's icon or duration with `copyWith` on its style:

```dart
final messages = AppMessageTheme.seeded(scheme, success: ..., warning: ...);
messages.copyWith(
  info: messages.info.copyWith(duration: const Duration(seconds: 5)),
);
```

A theme without the extension gets `AppMessageTheme.fallback`.

Call these from a page, typically its `BlocConsumer` listener for a
`SingleEffect`; a bloc never shows messages itself. A snack bar goes away by
itself, so a result the user must not miss (a transfer, a payment) belongs
in a dialog or a result screen.

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

**Service unavailable.** `NetworkMonitor.isServiceUnavailable` is true while
the server's last answer was a 5xx (as a request's final answer, after its
retries): reached, but unable to serve. Its next answer of any other status
clears it. Read it with `NetworkScope.isServiceUnavailableOf(context)`, false
when there is no scope, for a banner next to the connection one. Nothing looks
for a failing service by itself. A banner's Retry calls
`NetworkScope.maybeOf(context)?.retry()`: it forgets the flag (the next answer
says whether it still holds) and fires `reconnected`, so every page showing a
failure reloads.

**Looking for itself.** The platform says nothing when Wi-Fi stays connected
and its internet comes back, and may drop an event while the app is in the
background. Give the monitor a probe, once the app's client exists and before
`start()`, and it looks for itself while it is not online and the app is in the
foreground: after 5, 10 and 20 s, then every 30 s, starting again from 5 s
after each recovery.

```dart
getIt<NetworkMonitor>().probe = () => dio.get<void>(
  '/api/app/config', // cheap, public
  options: Options(
    extra: {
      ConnectivityInterceptor.skipKey: true, // sent whatever the OS says
      RetryInterceptor.disableKey: true,
    },
  ),
).then((_) {}, onError: (_) {});
```

Each look reads the interface again, then sends the probe. The monitor does
not read its result: the client reports the outcome like any request's, so an
answer means online and a `reconnected`. Without a probe (the default) the
monitor never looks, and waits for the platform, a return from the background
or a request.

**Reload on reconnect.** `NetworkMonitor.reconnected` fires, at most once per
3 s, when a network appears (after a 1 s settle), when the app returns from the
background while not online, or when a request (a probe included) gets through
after a failure. One that falls inside those 3 s is held back until they end,
and dropped only if the network is lost again by then. A drop shorter than the
2 s grace announces nothing, unless the gate refused a request during it. A
device page wraps its own `Scaffold`:

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

## Language

`AppSettingsCubit` is the client's `LocaleProvider`: it names the language of
every request in `accept-language`. Declare the app's languages once and give
the same list to `MaterialApp`, so the request names the language on screen
even while the app follows the device:

```dart
AppConfig(
  // ...
  supportedLocales: const [Locale('ar'), Locale('en')],
);

MaterialApp.router(
  locale: settings.locale,
  supportedLocales: AppConfig.instance.supportedLocales,
);
```

The device's languages are resolved against the list the way the framework
resolves the app's own locale. With no list declared, a language is sent only
once the user has chosen one.
