import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';

/// The signed-in user's own profile. Rebuilds itself when auth status changes,
/// because [ProfileViewModel.build] watches it.
final profileViewModelProvider =
    AsyncNotifierProvider<ProfileViewModel, Profile?>(ProfileViewModel.new);
