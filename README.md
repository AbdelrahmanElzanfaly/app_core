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
