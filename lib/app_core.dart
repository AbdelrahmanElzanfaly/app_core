/// Platform core shared by the app and its packages.
library;

export 'src/bloc/base_bloc.dart';
export 'src/bloc/single_effect.dart';
export 'src/bloc/state_view.dart';
export 'src/config/app_config.dart';
export 'src/di/app_core_package_module.dart';
export 'src/error/app_failure.dart';
export 'src/error/app_failure_converter.dart';
export 'src/l10n/core_localizations.dart';
export 'src/result/result.dart';
export 'src/result/use_case.dart';
export 'src/session/auth_session.dart';
export 'src/session/session_service.dart';
export 'src/session/token_refresher.dart';
export 'src/settings/app_settings_cubit.dart';
export 'src/settings/app_settings_state.dart';
