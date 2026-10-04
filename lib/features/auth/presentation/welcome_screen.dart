import 'package:flutter/material.dart';

import '../../../core/theme/trekit_theme.dart';
import 'email_auth_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          return isWide
              ? const Row(
                  children: [
                    Expanded(flex: 6, child: _StoryPanel()),
                    Expanded(flex: 4, child: _SignInPanel()),
                  ],
                )
              : const Stack(
                  fit: StackFit.expand,
                  children: [
                    _StoryPanel(compact: true),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _SignInPanel(compact: true),
                    ),
                  ],
                );
        },
      ),
    );
  }
}

class _StoryPanel extends StatelessWidget {
  const _StoryPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('trekit-hero.png', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0xCC073E47)],
              stops: [0.25, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 24 : 48,
              compact ? 24 : 40,
              compact ? 24 : 48,
              compact ? 330 : 48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'trekit-family.png',
                    width: compact ? 60 : 92,
                    height: compact ? 60 : 92,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your adventures.\nYour people.\nYour memories.',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontSize: compact ? 32 : 54),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 18),
                        Text(
                          'A private place to capture the journey and share it with the people you trust.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 19,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SignInPanel extends StatelessWidget {
  const _SignInPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: compact ? 315 : double.infinity),
      decoration: BoxDecoration(
        color: TrekItColors.cream,
        borderRadius: compact
            ? const BorderRadius.vertical(top: Radius.circular(32))
            : BorderRadius.zero,
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 56,
              vertical: compact ? 26 : 48,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome to TrekIt',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue your story.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _openAuth(context, AuthMode.signIn),
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _openAuth(context, AuthMode.createAccount),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      side: const BorderSide(color: TrekItColors.deepTeal),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Create an account'),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Private by design. Nothing is public.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
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

  void _openAuth(BuildContext context, AuthMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EmailAuthScreen(mode: mode)),
    );
  }
}
