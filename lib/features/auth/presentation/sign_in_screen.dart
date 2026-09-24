import 'package:flutter/material.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';

const _minPasswordLength = 8;

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await widget.controller.register(_email.text, _password.text);
      } else {
        await widget.controller.login(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return 'اتصال به سرور برقرار نشد.';
    return switch (error.code) {
      'invalid_credentials' => 'ایمیل یا رمز عبور درست نیست.',
      'email_taken' => 'با این ایمیل قبلاً حساب ساخته شده است.',
      'invalid_email' => 'ایمیل معتبر نیست.',
      'invalid_password' => 'رمز عبور باید ۸ تا ۷۲ کاراکتر باشد.',
      _ => 'خطایی رخ داد. دوباره تلاش کن.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isRegistering ? 'ساخت حساب نفیر' : 'ورود به نفیر',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'ایمیل'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textDirection: TextDirection.ltr,
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? 'ایمیل معتبر وارد کن.'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'رمز عبور'),
                      obscureText: true,
                      autofillHints: [
                        _isRegistering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textDirection: TextDirection.ltr,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'رمز عبور را وارد کن.';
                        }
                        if (_isRegistering &&
                            value.length < _minPasswordLength) {
                          return 'رمز عبور باید حداقل ۸ کاراکتر باشد.';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isBusy ? null : _submit,
                      child: Text(_isRegistering ? 'ساخت حساب' : 'ورود'),
                    ),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => setState(() {
                                _isRegistering = !_isRegistering;
                                _error = null;
                              }),
                      child: Text(_isRegistering
                          ? 'حساب داری؟ وارد شو'
                          : 'حساب نداری؟ ثبت‌نام کن'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
