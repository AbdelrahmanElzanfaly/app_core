import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../error/app_failure.dart';

/// The platform's own copy: how a failure reads to the user.
///
/// Hand-written rather than generated: it is a handful of strings, and keeping
/// the package free of code generation keeps it free of a build step.
class CoreLocalizations {
  const CoreLocalizations._(this._strings);

  final Map<FailureType, String> _strings;

  static const LocalizationsDelegate<CoreLocalizations> delegate =
      _CoreLocalizationsDelegate();

  static CoreLocalizations of(BuildContext context) =>
      Localizations.of<CoreLocalizations>(context, CoreLocalizations) ??
      _en;

  /// The message to show for [failure]: the server's own when it sent one,
  /// this package's copy for the failure type otherwise.
  String describe(AppFailure failure) {
    final fromServer = failure.message;
    if (fromServer != null &&
        fromServer.isNotEmpty &&
        failure.type != FailureType.unknown) {
      return fromServer;
    }
    return _strings[failure.type]!;
  }

  static const _en = CoreLocalizations._({
    FailureType.network: 'No connection. Check the network and try again.',
    FailureType.timeout: 'The server took too long to respond.',
    FailureType.unauthorized: 'Your session has ended. Please sign in again.',
    FailureType.forbidden: 'You do not have access to this.',
    FailureType.notFound: 'What you asked for was not found.',
    FailureType.badRequest: 'The request was not accepted.',
    FailureType.server: 'Something went wrong on the server.',
    FailureType.unknown: 'Something went wrong.',
  });

  static const _ar = CoreLocalizations._({
    FailureType.network: 'لا يوجد اتصال. تحقّق من الشبكة وحاول مرة أخرى.',
    FailureType.timeout: 'استغرق الخادم وقتًا طويلًا في الرد.',
    FailureType.unauthorized: 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
    FailureType.forbidden: 'ليست لديك صلاحية لهذا.',
    FailureType.notFound: 'العنصر المطلوب غير موجود.',
    FailureType.badRequest: 'لم يتم قبول الطلب.',
    FailureType.server: 'حدث خطأ في الخادم.',
    FailureType.unknown: 'حدث خطأ ما.',
  });
}

class _CoreLocalizationsDelegate
    extends LocalizationsDelegate<CoreLocalizations> {
  const _CoreLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<CoreLocalizations> load(Locale locale) => SynchronousFuture(
    locale.languageCode == 'ar' ? CoreLocalizations._ar : CoreLocalizations._en,
  );

  @override
  bool shouldReload(_CoreLocalizationsDelegate old) => false;
}
