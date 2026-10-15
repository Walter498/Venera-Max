part of 'qingman_transport.dart';

class _Profile {
  final String deviceId;
  final Uint8List signSuffix;
  final Uint8List responseKey;
  final SecurityContext context;
  _Profile(this.deviceId, this.signSuffix, this.responseKey, this.context);

  static _Profile parse(List<int> bytes, String localDevice) {
    try {
      if (bytes.isEmpty || bytes.length > QingmanTransport.maxProfileBytes) {
        throw const QingmanException('profile');
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map || data['version'] != 1) throw const QingmanException('profile');
      final device = data['deviceId'] ?? localDevice;
      if (device is! String || !RegExp(r'^[a-zA-Z0-9_-]{16,128}$').hasMatch(device)) {
        throw const QingmanException('profile');
      }
      final suffix = base64.decode(data['signSuffix'] as String);
      final key = base64.decode(data['responseKey'] as String);
      final ca = data['caPem'] as String;
      final client = data['clientPem'] as String;
      if (suffix.length != 33 || key.length != 32 ||
          !ca.contains('-----BEGIN CERTIFICATE-----') ||
          !client.contains('-----BEGIN CERTIFICATE-----') ||
          !RegExp(r'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----').hasMatch(client)) {
        throw const QingmanException('profile');
      }
      // Server chain uses public roots; the imported private CA supplements them.
      // Extract blocks to tolerate openssl Bag Attributes on Apple/BoringSSL.
      final certificates = RegExp(
        r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----');
      final caChain = certificates.allMatches(ca).map((m) => m[0]!).join('\n');
      final clientChain = certificates.allMatches(client).map((m) => m[0]!).join('\n');
      final privateKey = RegExp(
        r'-----BEGIN ((?:RSA |EC )?PRIVATE KEY)-----[\s\S]+?-----END \1-----')
        .firstMatch(client)?[0];
      if (caChain.isEmpty || clientChain.isEmpty || privateKey == null) {
        throw const QingmanException('profile');
      }
      final context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificatesBytes(utf8.encode(caChain))
        ..useCertificateChainBytes(utf8.encode(clientChain))
        ..usePrivateKeyBytes(utf8.encode(privateKey));
      return _Profile(device, suffix, key, context);
    } catch (_) {
      // TLS/PEM/JSON parser exceptions can contain input; never propagate them.
      throw const QingmanException('profile');
    }
  }
}

extension QingmanProfileManagement on QingmanTransport {
  /// No raw profile getter/export: JS receives status only.
  Future<void> importProfile(List<int> bytes) {
    // Copy so a picker/caller cannot mutate input while queued.
    if (bytes.length > QingmanTransport.maxProfileBytes) {
      return Future<void>.error(const QingmanException('profile'));
    }
    final copy = Uint8List.fromList(bytes);
    return _mutate(() async {
      try {
        await _directory.create(recursive: true);
        final device = await _localDevice();
        final candidate = _Profile.parse(copy, device);
        final target = File('${_directory.path}/profile.qmprofile');
        final staged = File('${_directory.path}/profile.pending');
        try {
          await staged.writeAsBytes(copy, flush: true);
          // Same private directory: rename commits a fully validated replacement.
          await staged.rename(target.path);
        } finally {
          if (await staged.exists()) await staged.delete();
        }
        _invalidate();
        _profile = candidate;
      } catch (_) {
        throw const QingmanException('profile');
      } finally {
        copy.fillRange(0, copy.length, 0);
      }
    });
  }

  Future<void> clearProfile() => _mutate(() async {
    _invalidate();
    try {
      for (final name in ['profile.qmprofile', 'profile.pending']) {
        final file = File('${_directory.path}/$name');
        if (await file.exists()) await file.delete();
      }
      // Local device identity intentionally survives clear/re-import.
    } catch (_) {
      throw const QingmanException('profile');
    }
  });

  Future<void> _mutate(Future<void> Function() action) {
    final next = _mutation.then((_) => action());
    // Keep the serialization chain usable after an invalid import.
    _mutation = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _invalidate() {
    _generation++;
    _session = null;
    _profile = null;
    _profileFlight = null;
    _bootstrapFlight = null;
  }

  Future<String> _localDevice() async {
    final file = File('${_directory.path}/device-id');
    if (await file.exists()) {
      if (await file.length() > 128) throw const QingmanException('profile');
      final device = await file.readAsString();
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(device)) throw const QingmanException('profile');
      return device;
    }
    final device = _randomHex(16);
    await file.writeAsString(device, flush: true);
    return device;
  }

  Future<_Profile> _loadProfile() async {
    if (_profile != null) return _profile!;
    if (_profileFlight != null) return _profileFlight!;
    final generation = _generation;
    final next = (() async {
      final file = File('${_directory.path}/profile.qmprofile');
      if (!await file.exists()) throw const QingmanException('missingProfile');
      try {
        if (await file.length() > QingmanTransport.maxProfileBytes) {
          throw const QingmanException('profile');
        }
        final device = await _localDevice();
        final bytes = await file.readAsBytes();
        try {
          final profile = _Profile.parse(bytes, device);
          _checkGeneration(generation);
          _profile = profile;
          return profile;
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } on QingmanException {
        rethrow;
      } catch (_) {
        throw const QingmanException('profile');
      }
    })();
    _profileFlight = next;
    try {
      return await next;
    } finally {
      if (identical(_profileFlight, next)) _profileFlight = null;
    }
  }
}
