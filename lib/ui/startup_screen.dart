import 'package:flutter/material.dart';
import 'emville_theme.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Stack(fit: StackFit.expand, children: [
        Image.asset(Emville.veranda, fit: BoxFit.cover),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [
              0,
              .3,
              1
            ],
                    colors: [
              Color(0x3008271D),
              Color(0x0A08271D),
              Color(0xD908271D)
            ]))),
        SafeArea(
            child: LayoutBuilder(
                builder: (context, constraints) => Stack(children: [
                      Positioned(
                          top: constraints.maxHeight * .085,
                          left: 0,
                          right: 0,
                          child: Center(
                              child: Container(
                                  width: 205,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color:
                                          Emville.ivory.withValues(alpha: .93),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Image.asset(Emville.logo)))),
                      Positioned(
                          bottom: 70,
                          left: 28,
                          right: 28,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('EMVILLE PROPERTY MANAGEMENT',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        color: Colors.white,
                                        fontSize: 10,
                                        letterSpacing: 2)),
                                const SizedBox(height: 16),
                                Text('Every stay.\nThoughtfully managed.',
                                    style: Emville.heading(39).copyWith(
                                        color: Colors.white, height: 1.12)),
                                const SizedBox(height: 16),
                                const Text(
                                    'A little more ease in your day.\nA little more care in every stay.',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        color: Color(0xFFE0E6DC),
                                        height: 1.7,
                                        fontSize: 14)),
                                const SizedBox(height: 28),
                                const Row(children: [
                                  SizedBox(
                                      width: 52,
                                      child: LinearProgressIndicator(
                                          minHeight: 2,
                                          color: Color(0xFFD4B478),
                                          backgroundColor: Color(0x66D4B478))),
                                  SizedBox(width: 12),
                                  Expanded(
                                      child: Text('PREPARING YOUR WORKSPACE',
                                          style: TextStyle(
                                              fontFamily: 'Roboto',
                                              color: Colors.white,
                                              fontSize: 10,
                                              letterSpacing: 1)))
                                ]),
                              ])),
                      const Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Text('LUXURY RIVERSIDE POOL VILLA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  color: Colors.white,
                                  fontSize: 9,
                                  letterSpacing: 2))),
                    ]))),
      ]));
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.child});
  final Widget child;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const StartupScreen();
}
