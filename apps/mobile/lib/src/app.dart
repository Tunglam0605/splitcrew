import 'package:flutter/material.dart';

import 'app_state.dart';
import 'home_page.dart';
import 'payment_ui.dart';

final class SplitCrewApp extends StatelessWidget {
  const SplitCrewApp({super.key, required this.controller});

  final TripController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SplitCrew',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.hasTrip) {
            return CreateTripPage(controller: controller, loadError: controller.loadError);
          }
          return TripWorkspace(controller: controller);
        },
      ),
    );
  }
}
