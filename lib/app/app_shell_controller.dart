import 'package:flutter_riverpod/flutter_riverpod.dart';

final shellNavigationProvider = NotifierProvider.autoDispose<ShellNavigationController, int>(
  ShellNavigationController.new,
);

final class ShellNavigationController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}
