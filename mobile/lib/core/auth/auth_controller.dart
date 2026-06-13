import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_engine.dart';
import 'auth_repository.dart';

class AuthState {
  const AuthState({this.user, this.busy = false});

  final AuthUser? user;
  final bool busy;

  bool get signedIn => user != null;

  AuthState copyWith({AuthUser? user, bool? busy, bool clearUser = false}) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        busy: busy ?? this.busy,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => AuthState(user: ref.read(authRepoProvider).user);

  /// Returns null on success, or a user-facing error message.
  Future<String?> register(String name, String email, String password) =>
      _run(() => ref.read(authRepoProvider).register(name, email, password));

  Future<String?> login(String email, String password) =>
      _run(() => ref.read(authRepoProvider).login(email, password));

  Future<String?> _run(Future<AuthUser> Function() action) async {
    state = state.copyWith(busy: true);
    try {
      final user = await action();
      state = AuthState(user: user);
      // First sync: push local data up, pull anything already on the server.
      ref.read(syncEngineProvider.notifier).syncNow(initial: true);
      return null;
    } on AuthException catch (e) {
      state = state.copyWith(busy: false);
      return e.message;
    } catch (e) {
      state = state.copyWith(busy: false);
      return 'Something went wrong. Please try again.';
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepoProvider).logout();
    await ref.read(syncEngineProvider.notifier).reset();
    state = const AuthState();
    // Local diary/profile stay on the device — signing out is not a wipe.
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
