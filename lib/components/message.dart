part of "components.dart";

void showToast({
  required String message,
  required BuildContext context,
  Widget? icon,
  Widget? trailing,
  int? seconds,
}) {
  var newEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
            message: message,
            icon: icon,
            trailing: trailing,
          ));

  var state = context.findAncestorStateOfType<OverlayWidgetState>();

  state?.addOverlay(newEntry);

  Timer(Duration(seconds: seconds ?? 2), () => state?.remove(newEntry));
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.message, this.icon, this.trailing});

  final String message;

  final Widget? icon;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24 + math.max(
        MediaQuery.viewInsetsOf(context).bottom,
        MediaQuery.paddingOf(context).bottom,
      ),
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Material(
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(VeneraDesignTokens.of(context).cardRadius),
          elevation: 2,
          textStyle:
              ts.withColor(Theme.of(context).colorScheme.onInverseSurface),
          child: IconTheme(
            data: IconThemeData(
                color: Theme.of(context).colorScheme.onInverseSurface),
            child: IntrinsicWidth(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                constraints: BoxConstraints(
                  maxWidth: math.min(560, context.width - 32),
                  maxHeight: math.max(48, MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).top - 64),
                ),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) icon!.paddingRight(8),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (trailing != null)
                      // The toast surface is inverseSurface; a default
                      // TextButton keeps the theme's primary foreground which
                      // is near-invisible on it (issue #136). Force the
                      // inverse-scheme accent for any trailing action.
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButtonTheme(
                        data: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.inversePrimary,
                          ),
                        ),
                        child: trailing!,
                        ),
                      )
                  ],
                ),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget(this.child, {super.key});

  final Widget child;

  @override
  State<OverlayWidget> createState() => OverlayWidgetState();
}

class OverlayWidgetState extends State<OverlayWidget> {
  final overlayKey = GlobalKey<OverlayState>();

  var entries = <OverlayEntry>[];

  void addOverlay(OverlayEntry entry) {
    if (overlayKey.currentState != null) {
      overlayKey.currentState!.insert(entry);
      entries.add(entry);
    }
  }

  void remove(OverlayEntry entry) {
    if (entries.remove(entry)) {
      entry.remove();
    }
  }

  void removeAll() {
    for (var entry in entries) {
      entry.remove();
    }
    entries.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: overlayKey,
      initialEntries: [OverlayEntry(builder: (context) => widget.child)],
    );
  }
}

void showDialogMessage(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: title,
      content: Text(message).paddingHorizontal(16),
      actions: [
        FilledButton(
          onPressed: context.pop,
          child: Text("OK".tl),
        )
      ],
    ),
  );
}

Future<void> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  required void Function() onConfirm,
  String confirmText = "Confirm",
  Color? btnColor,
}) {
  return showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: title,
      content: Text(content).paddingHorizontal(16).paddingVertical(8),
      actions: [
        FilledButton(
          onPressed: () {
            context.pop();
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: btnColor,
          ),
          child: Text(confirmText.tl),
        ),
      ],
    ),
  );
}

class LoadingDialogController {
  double? _progress;

  String? _message;

  void Function()? _closeDialog;

  void Function(double? value)? _serProgress;

  void Function(String message)? _setMessage;

  bool closed = false;

  void close() {
    if (closed) {
      return;
    }
    closed = true;
    if (_closeDialog != null) {
      _closeDialog!();
    }
  }

  void setProgress(double? value) {
    if (closed) {
      return;
    }
    _serProgress?.call(value);
  }

  void setMessage(String message) {
    if (closed) {
      return;
    }
    _setMessage?.call(message);
  }
}

LoadingDialogController showLoadingDialog(
  BuildContext context, {
  void Function()? onCancel,
  void Function()? onSecondary,
  bool barrierDismissible = true,
  bool allowCancel = true,
  String? message,
  String cancelButtonText = "Cancel",
  String? secondaryButtonText,
  bool withProgress = false,
}) {
  var controller = LoadingDialogController();
  controller._message = message;

  if (withProgress) {
    controller._progress = 0;
  }

  var loadingDialogRoute = DialogRoute(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          controller._serProgress = (value) {
            setState(() {
              controller._progress = value;
            });
          };
          controller._setMessage = (message) {
            setState(() {
              controller._message = message;
            });
          };
          return PopScope(
            // A caller that opted out of barrier dismissal is waiting on one of
            // the buttons below; the close icon and the system back gesture
            // would otherwise pop the route without running any callback.
            canPop: barrierDismissible,
            child: ContentDialog(
              title: controller._message ?? 'Loading',
              dismissible: barrierDismissible,
              content: LinearProgressIndicator(
                value: controller._progress ??
                    (VeneraMotion.reduce(context) ? 0.65 : null),
                semanticsLabel: controller._message ?? 'Loading'.tl,
                semanticsValue: controller._progress == null && VeneraMotion.reduce(context)
                    ? 'Loading'.tl : null,
                backgroundColor: context.colorScheme.surfaceContainer,
              ).paddingHorizontal(16).paddingVertical(16),
              actions: [
                if (secondaryButtonText != null && onSecondary != null)
                  TextButton(
                    onPressed: () {
                      controller.close();
                      onSecondary();
                    },
                    child: Text(secondaryButtonText.tl),
                  ),
                FilledButton(
                  onPressed: allowCancel
                      ? () {
                          controller.close();
                          onCancel?.call();
                        }
                      : null,
                  child: Text(cancelButtonText.tl),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  var navigator = Navigator.of(context, rootNavigator: true);

  navigator.push(loadingDialogRoute).then((value) => controller.closed = true);

  controller._closeDialog = () {
    navigator.removeRoute(loadingDialogRoute);
  };

  return controller;
}

class ContentDialog extends StatelessWidget {
  const ContentDialog({
    super.key,
    this.title, // 如果不传 title 将不会展示
    required this.content,
    this.dismissible = true,
    this.actions = const [],
  });

  final String? title;

  final Widget content;

  final List<Widget> actions;

  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    var content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: dismissible ? context.pop : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(title!, style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          this.content.paddingHorizontal(16),
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            overflowAlignment: OverflowBarAlignment.end,
            children: actions,
          ).paddingHorizontal(16),
          const SizedBox(height: 16),
        ],
      ),
    );
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VeneraDesignTokens.of(context).sectionRadius),
        side: context.brightness == Brightness.dark
            ? BorderSide(color: context.colorScheme.outlineVariant)
            : BorderSide.none,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 2,
      shadowColor: context.colorScheme.shadow,
      backgroundColor: context.colorScheme.surface,
      child: AnimatedSize(
        duration: VeneraMotion.duration(context, const Duration(milliseconds: 200)),
        curve: VeneraMotion.move,
        alignment: Alignment.topCenter,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              minWidth: math.min(400, context.width - 32),
            ),
            child: MediaQuery.removePadding(
              removeTop: true,
              removeBottom: true,
              context: context,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showInputDialog({
  required BuildContext context,
  required String title,
  String? hintText,
  required FutureOr<Object?> Function(String) onConfirm,
  String? initialValue,
  String confirmText = "Confirm",
  String cancelText = "Cancel",
  RegExp? inputValidator,
  String? image,
  Uint8List? imageData,
}) {
  var controller = TextEditingController(text: initialValue);
  bool isLoading = false;
  String? error;

  return showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: title,
            content: Column(
              children: [
                if (image != null)
                  SizedBox(
                    height: 108,
                    child: Image.network(image, fit: BoxFit.none),
                  ).paddingBottom(8),
                if (image == null && imageData != null)
                  SizedBox(
                    height: 108,
                    child: Image.memory(imageData, fit: BoxFit.none),
                  ).paddingBottom(8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ).paddingHorizontal(12),
              ],
            ),
            actions: [
              Button.filled(
                isLoading: isLoading,
                onPressed: () async {
                  if (inputValidator != null &&
                      !inputValidator.hasMatch(controller.text)) {
                    setState(() => error = "Invalid input");
                    return;
                  }
                  var futureOr = onConfirm(controller.text);
                  Object? result;
                  if (futureOr is Future) {
                    setState(() => isLoading = true);
                    result = await futureOr;
                    setState(() => isLoading = false);
                  } else {
                    result = futureOr;
                  }
                  if (result == null) {
                    context.pop();
                  } else {
                    setState(() => error = result.toString());
                  }
                },
                child: Text(confirmText.tl),
              ),
            ],
          );
        },
      );
    },
  );
}

void showInfoDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = "OK",
}) {
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: title,
        content: Text(content).paddingHorizontal(16).paddingVertical(8),
        actions: [
          Button.filled(
            onPressed: context.pop,
            child: Text(confirmText.tl),
          ),
        ],
      );
    },
  );
}

Future<int?> showSelectDialog({
  required String title,
  required List<String> options,
  int? initialIndex,
}) async {
  int? current = initialIndex;

  await showDialog(
    context: App.rootContext,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: title,
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Select(
                    current: current == null ? "" : options[current!],
                    values: options,
                    minWidth: 156,
                    onTap: (i) {
                      setState(() {
                        current = i;
                      });
                    },
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  current = null;
                  context.pop();
                },
                child: Text('Cancel'.tl),
              ),
              FilledButton(
                onPressed: current == null ? null : context.pop,
                child: Text('Confirm'.tl),
              ),
            ],
          );
        },
      );
    },
  );

  return current;
}
