import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';

/// What waits for a verified email, said once for the banner and the screen.
const _gatedFeatures =
    'آپلود، افزودن از لینک، اشتراک عمومی، درخواست فضای بیشتر و بات‌ها بعد از تأیید ایمیل باز می‌شوند.';

/// A quiet reminder at the top of the library while the account's email is
/// not verified. Listening works meanwhile.
class EmailVerificationBanner extends StatelessWidget {
  const EmailVerificationBanner({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassSurface(
        blur: 0,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        tint: scheme.primary,
        borderColor: scheme.primary.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(NafirIcons.envelopeSimple, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ایمیلت را تأیید کن',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        _gatedFeatures,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onOpen,
                child: const Text('تأیید ایمیل'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enters the emailed code, asks for another one, or corrects a mistyped
/// address. Closes itself once the address is verified.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.controller,
    this.resendCooldown = const Duration(seconds: 60),
  });

  final AuthController controller;

  /// How long «ارسال دوباره» waits after a code was sent.
  final Duration resendCooldown;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String get _email => widget.controller.user?.email ?? '';

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = widget.resendCooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    // The server reads Persian and Arabic digits too.
    final code = _code.text.replaceAll(RegExp(r'[^0-9۰-۹٠-٩]'), '');
    if (code.length != 6) {
      setState(() => _error = 'کد ۶ رقمی‌ای را که برایت ایمیل شد وارد کن.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _run(() async {
      await widget.controller.verifyEmail(code);
      messenger.showSnackBar(
          const SnackBar(content: Text('ایمیلت تأیید شد. همه‌چیز آماده است.')));
      if (navigator.canPop()) navigator.pop();
    });
  }

  Future<void> _resend() => _run(() async {
        await widget.controller.sendEmailCode();
        _code.clear();
        if (!mounted) return;
        setState(() => _notice = 'کد تازه‌ای به ایمیلت فرستاده شد.');
        _startCooldown();
      });

  Future<void> _editEmail() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => _EditEmailDialog(initial: _email),
    );
    if (email == null || email == _email || !mounted) return;
    await _run(() async {
      final sent = await widget.controller.changeEmail(email);
      _code.clear();
      if (!mounted) return;
      setState(() => _notice = sent
          ? 'ایمیل عوض شد و کد تازه به نشانی جدید فرستاده شد.'
          : 'ایمیل عوض شد، اما فرستادن کد ممکن نشد. «ارسال دوباره» را بزن.');
      if (sent) _startCooldown();
    });
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) {
      return 'اتصال به سرور برقرار نشد. اینترنت را بررسی کن و دوباره تلاش کن.';
    }
    return switch (error.code) {
      'wrong_code' => switch (error.details['attemptsLeft']) {
          final int left when left > 0 =>
            'کد درست نیست. ${persianDigits(left)} بار دیگر می‌توانی امتحان کنی.',
          _ => 'کد درست نیست. یک کد تازه بگیر.',
        },
      'invalid_code' => 'کد ۶ رقمی‌ای را که برایت ایمیل شد وارد کن.',
      'code_locked' => 'چند بار کد اشتباه وارد شد. یک کد تازه بگیر.',
      'code_expired' => 'این کد منقضی شده است. یک کد تازه بگیر.',
      'no_code' =>
        'کدی برای این ایمیل فرستاده نشده است. «ارسال دوباره» را بزن.',
      'email_already_verified' => 'ایمیلت قبلاً تأیید شده است.',
      'email_taken' => 'این ایمیل برای حساب دیگری ثبت شده است.',
      'invalid_email' => 'نشانی ایمیل درست نیست.',
      'email_send_failed' =>
        'فرستادن ایمیل ممکن نشد. چند دقیقه بعد دوباره تلاش کن.',
      'rate_limited' =>
        'چند بار پشت سر هم تلاش کردی. کمی بعد دوباره امتحان کن.',
      'unauthorized' => 'نشستت تمام شده است. یک بار خارج شو و دوباره وارد شو.',
      _ => 'کار انجام نشد. کمی بعد دوباره تلاش کن.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('تأیید ایمیل')),
      body: NafirBackdrop(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset),
                children: [
                  GlassSurface(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(NafirIcons.envelopeSimple,
                                color: scheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('کد را از ایمیلت وارد کن',
                                  style: theme.textTheme.titleMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'یک کد ۶ رقمی به '),
                            TextSpan(
                              text: '\u2068$_email\u2069',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(
                                text: ' فرستادیم. کد تا ۱۵ دقیقه معتبر است.'),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _gatedFeatures,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    maxLength: 7,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9۰-۹٠-٩ ]')),
                    ],
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 6),
                    onSubmitted: (_) => _verify(),
                    decoration: const InputDecoration(
                      labelText: 'کد تأیید',
                      counterText: '',
                    ),
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(error,
                        style: TextStyle(color: scheme.error),
                        semanticsLabel: error),
                  ],
                  if (_notice case final notice?) ...[
                    const SizedBox(height: 12),
                    Text(notice, semanticsLabel: notice),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: _busy ? null : _verify,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(NafirIcons.checkCircle),
                    label: const Text('تأیید'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: _busy || _cooldown > 0 ? null : _resend,
                        icon: const Icon(NafirIcons.arrowsClockwise),
                        label: Text(_cooldown > 0
                            ? 'ارسال دوباره (${persianDigits(_cooldown)})'
                            : 'ارسال دوباره'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: _busy ? null : _editEmail,
                        icon: const Icon(NafirIcons.pencilSimple),
                        label: const Text('ویرایش ایمیل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditEmailDialog extends StatefulWidget {
  const _EditEmailDialog({required this.initial});

  final String initial;

  @override
  State<_EditEmailDialog> createState() => _EditEmailDialogState();
}

class _EditEmailDialogState extends State<_EditEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_email.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ویرایش ایمیل'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'ایمیل',
            helperText: 'کد تازه به این نشانی فرستاده می‌شود.',
            helperMaxLines: 2,
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                ? null
                : 'نشانی ایمیل درست نیست.';
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(onPressed: _save, child: const Text('ذخیره و ارسال کد')),
      ],
    );
  }
}
