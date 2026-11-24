import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'interface_translations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.language = 'english',
    this.textDirection = TextDirection.ltr,
  });
  final String language;
  final TextDirection textDirection;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLogin = true;
  bool isSubmitting = false;
  String? error;
  LocalizedUiLabels get _labels =>
      LocalizedUiLabels.forLanguage(widget.language);

  Future<void> handleAuth() async {
    if (isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      isSubmitting = true;
      error = null;
    });
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      } else {
        // The authenticated profile gate creates an incomplete users/{uid}
        // document before showing the resumable profile setup step.
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => error = _messageForAuthError(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = _labels.text('auth.failed'));
      }
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  String _messageForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return _labels.text('auth.invalidCredential');
      case 'email-already-in-use':
        return _labels.text('auth.emailInUse');
      case 'invalid-email':
        return _labels.text('auth.invalidEmail');
      case 'weak-password':
        return _labels.text('auth.weakPassword');
      case 'too-many-requests':
        return _labels.text('auth.tooManyAttempts');
      default:
        return error.message ?? _labels.text('auth.failed');
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _labels.text(isLogin ? 'home.signIn' : 'auth.create');
    return Directionality(
      textDirection: widget.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_labels.text('home.brand')),
          leading:
              !Navigator.canPop(context) &&
                  ModalRoute.of(context)?.settings.name != '/'
              ? IconButton(
                  tooltip: _labels.text('home.home'),
                  icon: const Icon(Icons.home_outlined),
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/'),
                )
              : null,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Icon(
                                Icons.menu_book_outlined,
                                size: 36,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineMedium,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (error != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: emailController,
                              enabled: !isSubmitting,
                              decoration: InputDecoration(
                                labelText: _labels.text('profile.email'),
                                prefixIcon: const Icon(Icons.alternate_email),
                              ),
                              textDirection: TextDirection.ltr,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (value) =>
                                  value == null ||
                                      value.trim().isEmpty ||
                                      !value.contains('@')
                                  ? _labels.text('auth.invalidEmail')
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: passwordController,
                              enabled: !isSubmitting,
                              decoration: InputDecoration(
                                labelText: _labels.text('auth.password'),
                                prefixIcon: const Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                              textInputAction: isLogin
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              onFieldSubmitted: isLogin
                                  ? (_) => handleAuth()
                                  : null,
                              autofillHints: isLogin
                                  ? const [AutofillHints.password]
                                  : const [AutofillHints.newPassword],
                              validator: (value) =>
                                  value == null || value.length < 6
                                  ? _labels.text('auth.shortPassword')
                                  : null,
                            ),
                            if (!isLogin) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: confirmPasswordController,
                                enabled: !isSubmitting,
                                decoration: InputDecoration(
                                  labelText: _labels.text(
                                    'auth.confirmPassword',
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => handleAuth(),
                                validator: (value) =>
                                    value != passwordController.text
                                    ? _labels.text('auth.passwordMismatch')
                                    : null,
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: isSubmitting ? null : handleAuth,
                              child: isSubmitting
                                  ? SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: title,
                                      ),
                                    )
                                  : Text(title),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => setState(() {
                                      isLogin = !isLogin;
                                      error = null;
                                    }),
                              child: Text(
                                _labels.text(
                                  isLogin
                                      ? 'auth.registerInstead'
                                      : 'auth.signInInstead',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
