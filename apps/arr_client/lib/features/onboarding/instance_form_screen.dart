/// The form that adds or edits a service: address and token, test, then save.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/composition.dart';
import '../../app/providers.dart';
import '../../app/screens/message_page.dart';
import '../../src/l10n/generated/app_localizations.dart';
import 'address.dart';
import 'certificate/authority_import_screen.dart';
import 'certificate/certificate_widgets.dart';
import 'certificate/form_trust.dart';
import 'certificate/trust_section.dart';
import 'certificate_review.dart';
import 'connection_tester.dart';
import 'form_fields.dart';
import 'instance_form_controller.dart';
import 'test_result.dart';

/// Adds an instance of [serviceType] to the active profile, or edits the
/// instance [instanceId] of any profile. Closes with the saved instance's id.
class InstanceFormScreen extends ConsumerWidget {
  const InstanceFormScreen.add({required String this.serviceType, super.key})
    : instanceId = null;

  const InstanceFormScreen.edit({required String this.instanceId, super.key})
    : serviceType = null;

  final String? serviceType;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final target = (serviceType: serviceType, instanceId: instanceId);
    return switch (ref.watch(formSeedProvider(target))) {
      AsyncData(value: final FormReady seed) => _InstanceForm(
        target: target,
        seed: seed,
      ),
      AsyncData(value: FormInstanceRemoved()) => MessagePage(
        message: strings.instanceRemoved,
      ),
      AsyncData(value: FormUnsupported(:final name)) => MessagePage(
        message: strings.instanceUnsupported(name),
      ),
      AsyncError() => MessagePage(message: strings.loadFailed),
      _ => const LoadingPage(),
    };
  }
}

class _InstanceForm extends ConsumerStatefulWidget {
  const _InstanceForm({required this.target, required this.seed});

  final FormTarget target;
  final FormReady seed;

  @override
  ConsumerState<_InstanceForm> createState() => _InstanceFormState();
}

/// The controllers of one custom header.
class _Header {
  _Header([String name = '', String value = ''])
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);

  final TextEditingController name;
  final TextEditingController value;

  bool get isEmpty => name.text.trim().isEmpty && value.text.isEmpty;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

// What `dart:io` will send: visible ASCII, spaces and tabs.
final _sendable = RegExp(r'^[\t\x20-\x7e]*$');

class _InstanceFormState extends ConsumerState<_InstanceForm> {
  final _form = GlobalKey<FormState>();
  final _result = GlobalKey();

  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _apiKey;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _basicUser;
  late final TextEditingController _basicPassword;
  late final List<_Header> _headers;

  late AuthKind _authKind;
  late bool _advanced;

  late final FormTrust _trust;

  var _submitted = false;

  /// The `https://` in the address field was put there by the app.
  var _httpsAdded = false;
  String? _nameError;

  ServiceModule get _module => widget.seed.module;
  Instance? get _instance => widget.seed.instance;

  InstanceFormController get _controller =>
      ref.read(instanceFormProvider(widget.target).notifier);

  @override
  void initState() {
    super.initState();
    final instance = _instance;
    final credential = widget.seed.credential ?? const Credential();
    TextEditingController text([String? value]) =>
        TextEditingController(text: value);
    _name = text(widget.seed.suggestedName);
    _address = text(instance?.url.toString());
    _apiKey = text(credential.apiKey);
    _username = text(credential.username);
    _password = text(credential.password);
    _basicUser = text(credential.basicUser);
    _basicPassword = text(credential.basicPassword);
    _headers = [
      for (final MapEntry(:key, :value) in credential.customHeaders.entries)
        _Header(key, value),
    ];
    _authKind = instance?.authKind ?? _module.descriptor.authKinds.first;
    _advanced = _headers.isNotEmpty || _hasBasicAuth;
    _trust = FormTrust(instance);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _apiKey,
      _username,
      _password,
      _basicUser,
      _basicPassword,
    ]) {
      controller.dispose();
    }
    for (final header in _headers) {
      header.dispose();
    }
    super.dispose();
  }

  bool get _hasBasicAuth =>
      _basicUser.text.isNotEmpty || _basicPassword.text.isNotEmpty;

  /// What was tested is no longer what the form holds.
  void _changed([String? _]) {
    _controller.invalidate();
    // Notes depend on what is filled in.
    setState(() {});
  }

  /// What the form holds, or null after showing what is wrong with it.
  ConnectionInput? _read() {
    setState(() => _submitted = true);
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      // A field of the closed part must be seen.
      final hidden =
          !_advanced &&
          (_headers.any((header) => !header.isEmpty) || _hasBasicAuth);
      if (hidden) setState(() => _advanced = true);
      _reveal(() => invalid.first.context);
      return null;
    }
    final address = parseAddress(_address.text);
    if (address is! Ok<Uri, AddressProblem>) return null;
    final url = address.value;
    if (!namesScheme(_address.text)) _httpsAdded = true;
    // So that the user sees what is used, such as the added `https://`.
    _address.text = url.toString();

    final signsIn =
        _authKind == AuthKind.userPassword ||
        _authKind == AuthKind.mediaServerAccount;
    return ConnectionInput(
      url: url,
      authKind: _authKind,
      credential: Credential(
        apiKey: _authKind == AuthKind.apiKey ? _apiKey.text.trim() : null,
        username: signsIn ? _username.text.trim() : null,
        password: signsIn ? _password.text : null,
        basicUser: _hasBasicAuth ? _basicUser.text : null,
        basicPassword: _hasBasicAuth ? _basicPassword.text : null,
        customHeaders: {
          for (final header in _headers)
            if (!header.isEmpty)
              header.name.text.trim(): header.value.text.trim(),
        },
      ),
      certPin: _trust.pinFor(url),
      customCa: _trust.customCa,
      httpsAdded: _httpsAdded,
    );
  }

  /// Scrolls [target] into view once it is laid out.
  void _reveal(BuildContext? Function() target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = target();
      if (context == null || !context.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: 0.5,
        ),
      );
    });
  }

  Future<void> _test() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final input = _read();
    if (input == null) return;
    await _controller.test(widget.seed, input, _explainLocalNetwork);
  }

  Future<bool> _explainLocalNetwork() async {
    if (!mounted) return false;
    final strings = AppLocalizations.of(context);
    final goOn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(strings.localNetworkTitle),
        content: Text(strings.localNetworkExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UiLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.localNetworkContinue),
          ),
        ],
      ),
    );
    return goOn ?? false;
  }

  /// A certificate that nothing vouches for is a changed one, not a new one,
  /// while the accepted one it differs from is not yet let go of.
  TestStatus _asSeen(TestStatus status) {
    if (status case TestFailed(
      :final input,
      failure: CertificateUntrusted(:final certificate),
    )) {
      final accepted = _trust.unprovenPin(input.url);
      if (accepted != null && accepted != certificate.sha256) {
        return TestFailed(input, CertificateChanged(certificate));
      }
    }
    return status;
  }

  Future<void> _reviewCertificate(TestFailed failed) async {
    final input = failed.input;
    final trust = await ref.read(certificateReviewProvider)(
      context,
      url: input.url,
      failure: failed.failure,
      pinned: input.certPin ?? _trust.unprovenPin(input.url),
      // With a certificate pinned, the authority had no say.
      hasCustomCa: input.certPin == null && input.customCa != null,
    );
    if (trust == null || !mounted) return;
    if (trust.certPin case final pin?) {
      // Kept, and it is what was just tested with.
      if (pin == input.certPin) return;
      _trust.accept(input.url, pin);
    } else {
      _trust.useAuthority(input.url, trust.customCa!);
    }
    _changed();
    await _test();
  }

  /// The address typed, if it can be read.
  Uri? get _url => switch (parseAddress(_address.text)) {
    Ok(:final value) => value,
    Err() => null,
  };

  Future<void> _importAuthority() async {
    final url = _url;
    final pem = await importAuthority(
      context,
      url: url,
      replacesPin: _trust.pinShown(url) != null,
    );
    if (pem == null || !mounted) return;
    _trust.useAuthority(url, pem);
    _changed();
  }

  /// Whether to keep [pin], which an untried authority was to replace; null to
  /// not save.
  Future<bool?> _confirmKeeping(String pin) {
    final strings = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(strings.untriedTitle),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.untriedExplanation),
            const SizedBox(height: 16),
            Fingerprint(
              label: strings.certificateAcceptedFingerprint,
              sha256: pin,
              copy: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UiLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.untriedGiveUp),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.untriedKeep),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final input = _read();
    if (input == null) return;
    String? kept;
    if (input.certPin == null) {
      if (_trust.unprovenPin(input.url) case final pin?) {
        final keep = await _confirmKeeping(pin);
        if (keep == null || !mounted) return;
        if (keep) kept = pin;
      }
    }
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    final Result<Instance, RuleViolation> result;
    try {
      result = await _controller.save(
        widget.seed,
        name,
        input,
        keptCertPin: kept,
        removeCertPin:
            input.certPin == null &&
            kept == null &&
            _trust.gaveUpSavedPin(_instance),
      );
    } catch (error) {
      if (!mounted) return;
      final services = ref.read(appServicesProvider);
      services.log.log(
        LogLevel.warning,
        'A service could not be saved (${error.runtimeType})',
      );
      final removed = await _wasRemoved(services);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(removed ? strings.instanceRemoved : strings.saveFailed),
        ),
      );
      if (removed) _close();
      return;
    }
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _instance == null
                  ? strings.serviceAdded(value.name)
                  : strings.serviceSaved(value.name),
            ),
          ),
        );
        _close(value.id);
      case Err(error: RuleViolation.nameTaken):
        setState(() => _nameError = strings.formNameTaken);
      case Err(error: RuleViolation.nameLength):
        setState(() => _nameError = strings.formNameLength);
      // The fields are checked against the other rules before saving.
      case Err():
        messenger.showSnackBar(SnackBar(content: Text(strings.saveFailed)));
    }
  }

  void _close([String? savedId]) =>
      context.canPop() ? context.pop(savedId) : context.go('/');

  /// Whether the instance being edited has gone meanwhile.
  Future<bool> _wasRemoved(AppServices services) async {
    final id = _instance?.id;
    if (id == null) return false;
    try {
      return await services.profiles.instance(id) == null;
    } catch (_) {
      return false;
    }
  }

  String? _checkAddress(String? text) {
    final strings = AppLocalizations.of(context);
    return switch (parseAddress(text ?? '')) {
      Ok() => null,
      Err(error: AddressProblem.missing) => strings.formAddressMissing,
      Err(error: AddressProblem.invalid) => strings.formAddressInvalid,
      Err(error: AddressProblem.userInfo) => strings.formAddressUserInfo,
      Err(error: AddressProblem.queryOrFragment) => strings.formAddressQuery,
    };
  }

  /// For what has to be filled in and sent in a header.
  String? _checkRequired(String? text, String missing) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return missing;
    return null;
  }

  String? _checkSendable(String value) => _sendable.hasMatch(value.trim())
      ? null
      : AppLocalizations.of(context).formCharacters;

  String? _checkHeaderName(_Header header) {
    final strings = AppLocalizations.of(context);
    if (header.isEmpty) return null;
    final name = header.name.text.trim();
    if (!isValidHeaderName(name)) return strings.formHeaderNameInvalid;
    final lower = name.toLowerCase();
    final same = _headers.where(
      (other) => other.name.text.trim().toLowerCase() == lower,
    );
    return same.length > 1 ? strings.formHeaderNameTwice : null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = ref.watch(instanceFormProvider(widget.target));
    final descriptor = _module.descriptor;

    ref.listen(instanceFormProvider(widget.target), (before, after) {
      if (after.test case TestPassed(:final input)) {
        _trust.testPassed(
          input.url,
          certPin: input.certPin,
          authority: input.customCa,
        );
      }
      if (before?.test.runtimeType != after.test.runtimeType &&
          after.test is! NotTested) {
        _reveal(() => _result.currentContext);
      }
    });

    return PopScope(
      // The save under way reports to this screen.
      canPop: !state.isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _instance == null
                ? strings.formAddTitle(descriptor.displayName)
                : strings.formEditTitle(_instance!.name),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final margin = constraints.maxWidth < 600 ? 16.0 : 24.0;
              return SingleChildScrollView(
                padding: EdgeInsets.all(margin),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _form,
                      autovalidateMode: _submitted
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: AbsorbPointer(
                        absorbing: state.isSaving,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._connectionFields(strings, descriptor),
                            const SizedBox(height: 16),
                            ..._advancedFields(strings, descriptor),
                            const SizedBox(height: 16),
                            KeyedSubtree(
                              key: _result,
                              child: TestResult(
                                status: _asSeen(state.test),
                                service: descriptor.displayName,
                                onReviewCertificate: switch (_asSeen(
                                  state.test,
                                )) {
                                  final TestFailed failed => () => unawaited(
                                    _reviewCertificate(failed),
                                  ),
                                  _ => null,
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._buttons(strings, state),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _connectionFields(
    AppLocalizations strings,
    ModuleDescriptor descriptor,
  ) => [
    if (widget.seed.credentialUnreadable) ...[
      FormNote(strings.formCredentialUnreadable),
      const SizedBox(height: 16),
    ],
    EntryField(
      key: const ValueKey('address'),
      controller: _address,
      label: strings.formAddress,
      helper: strings.formAddressHelper('${descriptor.defaultPort}'),
      keyboardType: TextInputType.url,
      validator: _checkAddress,
      onChanged: (text) {
        // A scheme that the user changes or takes away is no longer the app's.
        if (!text.startsWith('https://')) _httpsAdded = false;
        _changed();
      },
    ),
    const SizedBox(height: 16),
    if (descriptor.authKinds.length > 1) ...[
      FormHeading(strings.formSignInWith),
      RadioGroup<AuthKind>(
        groupValue: _authKind,
        onChanged: (kind) {
          if (kind == null || kind == _authKind) return;
          _authKind = kind;
          _changed();
        },
        child: Column(
          children: [
            for (final kind in descriptor.authKinds)
              RadioListTile<AuthKind>(
                contentPadding: EdgeInsets.zero,
                value: kind,
                title: Text(switch (kind) {
                  AuthKind.apiKey => strings.formApiKey,
                  AuthKind.userPassword => strings.formUserPassword,
                  AuthKind.mediaServerAccount => strings.formMediaAccount,
                  AuthKind.none => strings.formNoSignIn,
                }),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ],
    ...switch (_authKind) {
      AuthKind.apiKey => [
        EntryField(
          key: const ValueKey('apiKey'),
          controller: _apiKey,
          label: strings.formApiKey,
          helper: strings.formApiKeyHelper(descriptor.displayName),
          secret: true,
          validator: (text) =>
              _checkRequired(text, strings.formApiKeyMissing) ??
              _checkSendable(text ?? ''),
          onChanged: _changed,
        ),
      ],
      AuthKind.userPassword || AuthKind.mediaServerAccount => [
        EntryField(
          key: const ValueKey('username'),
          controller: _username,
          label: strings.formUserName,
          validator: (text) =>
              _checkRequired(text, strings.formUserNameMissing),
          onChanged: _changed,
        ),
        const SizedBox(height: 16),
        EntryField(
          key: const ValueKey('password'),
          controller: _password,
          label: strings.formPassword,
          secret: true,
          validator: (text) =>
              (text ?? '').isEmpty ? strings.formPasswordMissing : null,
          onChanged: _changed,
        ),
      ],
      AuthKind.none => const <Widget>[],
    },
    ..._notes(descriptor, withBasicAuth: false),
    const SizedBox(height: 16),
    EntryField(
      key: const ValueKey('name'),
      controller: _name,
      label: strings.formName,
      helper: strings.formNameHelper,
      errorText: _nameError,
      validator: (text) {
        final length = (text ?? '').trim().runes.length;
        return length < 1 || length > 40 ? strings.formNameLength : null;
      },
      // The name is not part of what is tested.
      onChanged: (_) {
        if (_nameError != null) setState(() => _nameError = null);
      },
    ),
  ];

  List<Widget> _notes(
    ModuleDescriptor descriptor, {
    required bool withBasicAuth,
  }) => [
    for (final note in descriptor.authNotes)
      if (note.authKind == _authKind &&
          note.onlyWithBasicAuth == withBasicAuth &&
          (!withBasicAuth || _hasBasicAuth)) ...[
        const SizedBox(height: 12),
        FormNote(note.text(context)),
      ],
  ];

  List<Widget> _advancedFields(
    AppLocalizations strings,
    ModuleDescriptor descriptor,
  ) => [
    Semantics(
      expanded: _advanced,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(strings.formAdvanced),
        subtitle: Text(strings.formAdvancedSummary),
        trailing: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
        onTap: () => setState(() => _advanced = !_advanced),
      ),
    ),
    // Kept while closed, so that it is checked and sent all the same.
    Visibility(
      visible: _advanced,
      maintainState: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          CertificateTrustSection(
            pin: _trust.pinShown(_url),
            customCa: _trust.customCa,
            onImport: () => unawaited(_importAuthority()),
            onForgetPin: () {
              _trust.forgetPin(_url);
              _changed();
            },
            onRemoveAuthority: () {
              _trust.removeAuthority();
              _changed();
            },
          ),
          const SizedBox(height: 24),
          FormHeading(strings.formBasicAuth),
          const SizedBox(height: 12),
          EntryField(
            key: const ValueKey('basicUser'),
            controller: _basicUser,
            label: strings.formBasicUser,
            validator: (_) {
              if (_hasBasicAuth && excludesBasicAuth(descriptor, _authKind)) {
                return strings.formBasicAuthExcluded;
              }
              // The first colon ends the user name.
              return _basicUser.text.contains(':')
                  ? strings.formBasicUserColon
                  : null;
            },
            onChanged: _changed,
          ),
          const SizedBox(height: 16),
          EntryField(
            key: const ValueKey('basicPassword'),
            controller: _basicPassword,
            label: strings.formBasicPassword,
            secret: true,
            onChanged: _changed,
          ),
          ..._notes(descriptor, withBasicAuth: true),
          const SizedBox(height: 24),
          FormHeading(strings.formHeaders),
          for (final (index, header) in _headers.indexed)
            Padding(
              key: ObjectKey(header),
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EntryField(
                    key: ValueKey('headerName$index'),
                    controller: header.name,
                    label: strings.formHeaderName,
                    validator: (_) => _checkHeaderName(header),
                    onChanged: _changed,
                  ),
                  const SizedBox(height: 8),
                  EntryField(
                    key: ValueKey('headerValue$index'),
                    controller: header.value,
                    label: strings.formHeaderValue,
                    secret: true,
                    validator: (text) => _checkSendable(text ?? ''),
                    onChanged: _changed,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(strings.formRemoveHeader),
                      onPressed: () {
                        _headers.remove(header);
                        // After the fields that use them are gone.
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => header.dispose(),
                        );
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(strings.formAddHeader),
              onPressed: () => setState(() => _headers.add(_Header())),
            ),
          ),
        ],
      ),
    ),
  ];

  /// One primary button: test, then save. Saving without a passed test is
  /// offered after a failed one, and always when editing.
  List<Widget> _buttons(AppLocalizations strings, InstanceFormState state) {
    final save = state.isSaving ? null : () => unawaited(_save());
    final test = state.isSaving ? null : () => unawaited(_test());
    final adding = _instance == null;
    Widget? secondary(String label, VoidCallback? onPressed) =>
        OutlinedButton(onPressed: onPressed, child: Text(label));
    final (Widget primary, Widget? other) = switch (state.test) {
      NotTested() => (
        FilledButton(onPressed: test, child: Text(strings.formTest)),
        adding ? null : secondary(strings.formSaveUntested, save),
      ),
      Testing() => (
        FilledButton(onPressed: null, child: Text(strings.formTest)),
        secondary(strings.formStopTest, _controller.invalidate),
      ),
      TestPassed() => (
        FilledButton(
          onPressed: save,
          child: Text(adding ? strings.formAdd : strings.formSave),
        ),
        null,
      ),
      TestFailed() => (
        FilledButton(onPressed: test, child: Text(strings.formTestAgain)),
        secondary(strings.formSaveAnyway, save),
      ),
    };
    return [
      if (state.isSaving) ...[
        LinearProgressIndicator(semanticsLabel: strings.formSaving),
        const SizedBox(height: 8),
      ],
      primary,
      if (other != null) ...[const SizedBox(height: 8), other],
    ];
  }
}
