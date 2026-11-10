# app_core

What every feature of an app needs, in one package:

| | |
|---|---|
| `AppConfig`, `Environment` | per-flavor configuration, set once in `main()` |
| `AppFailure`, `Result`, `FutureUseCase` | one error type; repositories return `Result`, never throw |
| `BaseBloc`, `StateView`, `SingleEffect` | loading overlay and error snack bars for free; one-shot effects |
| `SessionService` | the signed-in session: secure storage, router refresh, token renewal |
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
