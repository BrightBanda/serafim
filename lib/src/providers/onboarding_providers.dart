import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/viewmodel/onboarding_view_model.dart';

/// Profile setup progress.
///
/// Not auto-disposed: the flow spans two screens and the answers from step 2
/// must survive being replaced by step 3.
final onboardingViewModelProvider =
    NotifierProvider<OnboardingViewModel, OnboardingState>(
      OnboardingViewModel.new,
    );
