import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uber_maids_watch/app.dart';
import 'package:uber_maids_watch/core/connectivity.dart';
import 'package:uber_maids_watch/core/session_store.dart';
import 'package:uber_maids_watch/state/app_state.dart';

void main() {
  testWidgets('signed-out app shows the login screen', (tester) async {
    final state = AppState(
      sessionStore: SessionStore(MemorySessionStorage()),
      connectivity: AlwaysOnlineConnectivity(),
    );

    await tester.pumpWidget(UberMaidsApp(state: state));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
