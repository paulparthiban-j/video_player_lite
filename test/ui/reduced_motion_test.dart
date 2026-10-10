import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/ui/responsive.dart';
import 'package:next_gen_video_player/screens/launch_screen.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe>
    with SingleTickerProviderStateMixin, ReducedMotion {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  List<AnimationController> get motionControllers => [controller];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget _app(Widget child, {required bool reduce}) => MaterialApp(
  builder: (context, w) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: w!,
  ),
  routes: {'/main': (_) => const Text('main screen')},
  home: child,
);

void main() {
  testWidgets('controllers run instantly when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Probe(), reduce: true));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    expect(state.controller.duration, Duration.zero);
  });

  testWidgets('controllers keep their duration otherwise', (tester) async {
    await tester.pumpWidget(_app(const _Probe(), reduce: false));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    expect(state.controller.duration, const Duration(milliseconds: 400));
  });

  testWidgets('duration is restored when the setting is turned off', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Probe(), reduce: true));
    await tester.pumpWidget(_app(const _Probe(), reduce: false));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    expect(state.controller.duration, const Duration(milliseconds: 400));
  });

  testWidgets('launch screen skips the wait when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LaunchScreen(), reduce: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('main screen'), findsOneWidget);
  });

  testWidgets('launch screen hands over within a second normally', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LaunchScreen(), reduce: false));
    await tester.pump();
    expect(find.text('main screen'), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('main screen'), findsOneWidget);
  });
}
