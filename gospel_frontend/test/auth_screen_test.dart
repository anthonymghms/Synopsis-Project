import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/auth_screen.dart';
import 'package:gospel_frontend/study_theme.dart';

void main() {
  testWidgets(
    'Arabic mobile sign-in and registration validate before submitting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyTheme.theme,
          home: const AuthScreen(
            language: 'arabic',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      expect(
        Directionality.of(tester.element(find.byType(Form))),
        TextDirection.rtl,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
      await tester.pump();
      expect(find.text('أدخل عنوان بريد إلكتروني صالحًا.'), findsOneWidget);
      final createAccount = find.widgetWithText(TextButton, 'إنشاء حساب جديد');
      await tester.ensureVisible(createAccount);
      await tester.tap(createAccount);
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'reader@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'sample-password',
      );
      final submit = find.widgetWithText(FilledButton, 'إنشاء حساب');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('كلمتا المرور غير متطابقتين.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
