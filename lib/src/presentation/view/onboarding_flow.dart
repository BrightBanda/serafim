import 'package:flutter/material.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/profile_interests_page.dart';
import 'package:serafim/src/presentation/view/profile_photo_name_page.dart';
import 'package:serafim/src/presentation/viewmodel/onboarding_view_model.dart';
import 'package:serafim/src/providers/onboarding_providers.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// Profile setup, shown once the user is signed in but has no profile yet.
///
/// Swaps between the two steps from [OnboardingState.step] rather than using
/// a Navigator: the step is app state the view model already owns, and going
/// "back" has to preserve what was typed. A pushed route would put that
/// lifecycle in the widget tree instead, where the view model cannot reach it.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  // Lives here, not in the page: the page is rebuilt out of existence when
  // step 3 replaces it, and the typed name has to survive going back.
  late final TextEditingController _nameController = TextEditingController(
    text: ref.read(onboardingViewModelProvider).displayName,
  );
  late final TextEditingController _usernameController = TextEditingController(
    text: ref.read(onboardingViewModelProvider).username,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  bool _preparingPhoto = false;

  Future<void> _pickPhoto(OnboardingViewModel viewModel) async {
    if (_preparingPhoto) return;
    try {
      final bytes = await pickShrunkImage(
        context,
        maxSide: 512,
        quality: 80,
        onPicked: () {
          if (mounted) setState(() => _preparingPhoto = true);
        },
      );
      if (bytes != null) viewModel.setAvatar(bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanError(error, fallback: "Couldn't use that photo."),
          ),
          backgroundColor: AppColors.rust,
        ),
      );
    } finally {
      if (mounted) setState(() => _preparingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingViewModelProvider);
    final viewModel = ref.read(onboardingViewModelProvider.notifier);

    // A failed create is transient — surface it and let them retry, rather
    // than replacing the form with an error screen.
    ref.listen(onboardingViewModelProvider.select((s) => s.errorMessage), (
      _,
      message,
    ) {
      if (message == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.rust,
            behavior: SnackBarBehavior.floating,
          ),
        );
      viewModel.dismissError();
    });

    final page = switch (state.step) {
      OnboardingStep.photoName => ProfilePhotoNamePage(
        nameController: _nameController,
        usernameController: _usernameController,
        usernameError: state.usernameError,
        onUsernameChanged: viewModel.usernameChanged,
        avatarBytes: state.avatarBytes,
        avatarBusy: _preparingPhoto,
        onEditPhoto: () => _pickPhoto(viewModel),
        onUploadPhoto: () => _pickPhoto(viewModel),
        onContinue: () => viewModel.continueToInterests(
          _nameController.text,
          username: _usernameController.text,
        ),
        // Skipping is allowed; finish() derives missing profile fields from
        // the signed-in account details.
        onSkip: () => viewModel.continueToInterests(''),
      ),
      OnboardingStep.interests => ProfileInterestsPage(
        onBack: viewModel.backToPhotoName,
        onFinish: viewModel.finish,
        onSkip: viewModel.finish,
      ),
    };

    return Stack(
      children: [
        page,
        // Blocks input as well as dimming, so a double tap on "Finish setup"
        // cannot fire a second create while the first is in flight.
        if (state.isSubmitting)
          Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }
}
