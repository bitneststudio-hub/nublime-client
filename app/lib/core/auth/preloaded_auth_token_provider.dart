// lib/core/auth/preloaded_auth_token_provider.dart
import 'package:nublime/core/auth/t59_auth_token_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'preloaded_auth_token_provider.g.dart';

typedef PreloadedToken = ({bool loaded, AuthToken? token});

@Riverpod(keepAlive: true)
class PreloadedAuthToken extends _$PreloadedAuthToken {
  @override
  PreloadedToken build() => (loaded: false, token: null);

  void set(AuthToken? token) => state = (loaded: true, token: token);
}
