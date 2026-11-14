import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/text_field.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Asks for the code emailed at sign-up. Shown by the auth gate while the
/// account is waiting to be confirmed; a correct code signs the person in and
/// the gate moves on by itself.
class EmailCodeScreen extends ConsumerStatefulWidget {
  const EmailCodeScreen({super.key});

  /// Shortest code Supabase sends (its default is six digits; the project can
  /// raise it up to ten).
  static const minLength = 6;
  static const maxLength = 10;

  /// How long before another code can be asked for.
  static const resendWait = Duration(seconds: 45);

  @override
  ConsumerState<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends ConsumerState<EmailCodeScreen> {
  final _code = TextEditingController();
  Timer? _ticker;
  int _wait = EmailCodeScreen.resendWait.inSeconds;
  String? _error;
  String? _info;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_wait > 0 && mounted) setState(() => _wait--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  bool get _ready => _code.text.length >= EmailCodeScreen.minLength;

  Future<void> _verify() async {
    if (!_ready || ref.read(authViewModelProvider).isBusy) return;
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await ref
          .read(authViewModelProvider.notifier)
          .verifyEmailCode(_code.text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _codeError(error));
    }
  }

  Future<void> _resend() async {
    if (_wait > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authViewModelProvider.notifier).resendEmailCode();
      if (!mounted) return;
      setState(() {
        _info = 'A new code is on its way.';
        _wait = EmailCodeScreen.resendWait.inSeconds;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanError(error));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// A wrong or old code gets plain wording of its own.
  String _codeError(Object error) {
    final message = humanError(error);
    final lower = message.toLowerCase();
    if (lower.contains('expired') || lower.contains('invalid')) {
      return 'That code is wrong or has expired. Check it, or ask for a new '
          'one.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authViewModelProvider);
    final email = auth.pendingEmail;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppTopBar(
        onBack: auth.isBusy
            ? null
            : ref.read(authViewModelProvider.notifier).cancelEmailConfirmation,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Check your email', style: AppTextStyles.displayHeading),
              const SizedBox(height: 8),
              Text(
                email == null
                    ? 'We sent you a code. Enter it below.'
                    : 'We sent a code to $email. Enter it below.',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 24),
              SerafimTextField(
                key: const ValueKey('email-code'),
                label: 'Code',
                controller: _code,
                hintText: '123456',
                keyboardType: TextInputType.number,
                errorText: _error,
                enabled: !auth.isBusy,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(EmailCodeScreen.maxLength),
                ],
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_info != null) ...[
                const SizedBox(height: 6),
                Text(_info!, style: AppTextStyles.body),
              ],
              const SizedBox(height: 20),
              SerafimButton(
                label: auth.isBusy ? 'Checking…' : 'Verify',
                onPressed: _ready && !auth.isBusy ? _verify : null,
              ),
              const SizedBox(height: 12),
              SerafimButton(
                label: _wait > 0
                    ? 'Send a new code in ${_wait}s'
                    : 'Send a new code',
                isPrimary: false,
                onPressed: _wait > 0 || _resending ? null : _resend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
