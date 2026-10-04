import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/app/trekit_app.dart';
import 'package:trekit/features/auth/presentation/email_auth_screen.dart';
import 'package:trekit/features/auth/presentation/welcome_screen.dart';

void main() {
  testWidgets('welcome screen introduces TrekIt', (tester) async {
    await tester.pumpWidget(const TrekItApp(home: WelcomeScreen()));

    expect(find.text('Welcome to TrekIt'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('sign in opens the email authentication form', (tester) async {
    await tester.pumpWidget(const TrekItApp(home: WelcomeScreen()));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAuthScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('create account opens confirmation form', (tester) async {
    await tester.pumpWidget(const TrekItApp(home: WelcomeScreen()));

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAuthScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });
}
