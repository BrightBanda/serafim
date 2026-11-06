import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' show PhotoManager;
import 'package:serafim/src/utils/serafim_loader.dart';

/// Popped when the person would rather use the phone's own camera app.
const usePhoneCamera = 'use-phone-camera';

/// Takes a photo inside Serafim, so the app is never in the background where
/// Android may close it. Pops the [XFile], or [usePhoneCamera]. The camera is
/// released whenever the app leaves the screen, and on the way out.
class InAppCameraPage extends StatefulWidget {
  const InAppCameraPage({super.key});

  @override
  State<InAppCameraPage> createState() => _InAppCameraPageState();
}

class _InAppCameraPageState extends State<InAppCameraPage>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  int _lens = 0;
  CameraController? _controller;
  String? _problem;
  bool _refused = false;
  bool _taking = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final old = _controller;
      _controller = null;
      old?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _problem = null;
      _refused = false;
    });
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('none', 'No camera');
      }
      final controller = CameraController(
        _cameras[_lens % _cameras.length],
        // Sent photos are shrunk well below this, and a bigger preview only
        // costs memory on the phones that have least of it.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flash).catchError((Object _) {});
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      final refused = e.code.contains('AccessDenied');
      setState(() {
        _refused = refused;
        _problem = refused
            ? 'Serafim needs permission to use the camera.'
            : "The camera couldn't start.";
      });
    } catch (_) {
      if (mounted) setState(() => _problem = "The camera couldn't start.");
    }
  }

  Future<void> _flip() async {
    final old = _controller;
    setState(() {
      _controller = null;
      _lens++;
    });
    await old?.dispose();
    await _start();
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.auto : FlashMode.off;
    setState(() => _flash = next);
    await _controller?.setFlashMode(next).catchError((Object _) {});
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(photo);
    } catch (_) {
      if (mounted) {
        setState(() => _taking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't take that photo. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (controller != null)
            IconButton(
              key: const ValueKey('camera-flash'),
              tooltip: 'Flash',
              icon: Icon(
                _flash == FlashMode.off ? Icons.flash_off : Icons.flash_auto,
              ),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: SafeArea(
        child: _problem != null
            ? _Problem(
                text: _problem!,
                refused: _refused,
                onSettings: PhotoManager.openSetting,
                onRetry: _start,
                onPhoneCamera: () => Navigator.of(context).pop(usePhoneCamera),
              )
            : Column(
                children: [
                  Expanded(
                    child: controller == null
                        ? const Center(child: SerafimLoader(onBlack: true))
                        : Center(child: CameraPreview(controller)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          key: const ValueKey('camera-phone'),
                          tooltip: "Use your phone's camera",
                          icon: const Icon(
                            Icons.open_in_new,
                            color: Colors.white70,
                          ),
                          onPressed: () =>
                              Navigator.of(context).pop(usePhoneCamera),
                        ),
                        GestureDetector(
                          key: const ValueKey('camera-shutter'),
                          onTap: _take,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _taking ? Colors.white54 : Colors.white,
                              border: Border.all(
                                color: Colors.white38,
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('camera-flip'),
                          tooltip: 'Switch camera',
                          icon: const Icon(
                            Icons.cameraswitch_outlined,
                            color: Colors.white,
                          ),
                          onPressed: _cameras.length > 1 ? _flip : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.text,
    required this.refused,
    required this.onSettings,
    required this.onRetry,
    required this.onPhoneCamera,
  });

  final String text;
  final bool refused;
  final Future<void> Function() onSettings;
  final VoidCallback onRetry;
  final VoidCallback onPhoneCamera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              key: const ValueKey('camera-problem'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            if (refused)
              FilledButton(
                key: const ValueKey('camera-settings'),
                onPressed: onSettings,
                child: const Text('OPEN SETTINGS'),
              )
            else
              FilledButton(
                key: const ValueKey('camera-retry'),
                onPressed: onRetry,
                child: const Text('TRY AGAIN'),
              ),
            TextButton(
              key: const ValueKey('camera-use-phone'),
              onPressed: onPhoneCamera,
              child: const Text(
                "Use your phone's camera",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
