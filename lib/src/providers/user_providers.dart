// lib/src/providers/user_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/providers/network_providers.dart';

/// Representation of a user item returned from the backend API.
class ApiUser {
  const ApiUser({required this.id, required this.email, this.displayName});

  final String id;
  final String email;
  final String? displayName;

  factory ApiUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return ApiUser(
      id: json['id'].toString(),
      email: json['email'] ?? '',
      displayName: profile?['display_name'] ?? profile?['username'],
    );
  }
}

/// Fetches all registered users from the FastAPI backend.
final registeredUsersProvider = FutureProvider<List<ApiUser>>((ref) async {
  final dio = ref.watch(apiDioProvider);
  final response = await dio.get<List<dynamic>>('/auth/users');

  final data = response.data ?? [];
  return data
      .map((json) => ApiUser.fromJson(json as Map<String, dynamic>))
      .toList();
});
