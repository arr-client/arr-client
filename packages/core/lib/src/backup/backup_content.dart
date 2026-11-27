/// The payload of a setup export, read and checked in itself. What depends on
/// what is saved on the device is checked when an import is planned.
///
/// The file is not trusted, and nothing here quotes it in an error or a log.
library;

import 'dart:convert';

import '../instances/auth_kind.dart';
import '../instances/credential.dart';
import '../instances/instance_link.dart';
import '../instances/instance_link_type.dart';
import '../instances/instance_rules.dart';
import '../models/add_choices.dart';
import '../models/media_kind.dart';
import '../module/module_category.dart';
import '../module/module_descriptor.dart';
import '../module/result.dart';
import '../network/certificate_authority.dart';
import '../preferences/app_theme_mode.dart';
import '../preferences/library_layout.dart';
import '../preferences/library_view.dart';
import '../preferences/preferences_json.dart';

/// The event types of data-model.md NotificationSubscription.
const subscriptionEventTypes = {
  'imported',
  'downloadProblem',
  'healthIssue',
  'pendingRequest',
  'ownRequestUpdate',
};

/// The libraries a view is saved for, each named by the kind of its top-level
/// items.
const viewLibraries = {
  MediaKind.movie,
  MediaKind.series,
  MediaKind.artist,
  MediaKind.author,
};

/// A profile of a file.
typedef BackupProfile = ({String id, String name, int sortOrder});

/// An instance of a file. [credential] is null if the file gives none, also if
/// it gives an empty one.
typedef BackupInstance = ({
  String id,
  String profileId,
  String name,
  String serviceType,
  Uri url,
  AuthKind authKind,
  String? certPin,
  String? customCa,
  bool enabled,
  int sortOrder,
  List<InstanceLink> links,
  DateTime createdAt,
  Credential? credential,
});

/// The preferences of a file. A null setting is one the file does not name.
typedef BackupPreferences = ({
  AppThemeMode? themeMode,
  bool? trueBlack,
  bool? dynamicColor,
  bool? loadThirdPartyArtwork,
});

/// A subscription of a file.
typedef BackupSubscription = ({
  String instanceId,
  String eventType,
  bool enabled,
});

/// A payload that keeps the rules.
final class BackupContent {
  BackupContent._({
    required this.profiles,
    required this.instances,
    required this.preferences,
    required this.views,
    required this.addChoices,
    required this.subscriptions,
  });

  /// In the order of the file.
  final List<BackupProfile> profiles;

  /// In the order of the file.
  final List<BackupInstance> instances;

  /// The app-wide settings.
  final BackupPreferences preferences;

  /// The saved library views.
  final Map<(String profileId, MediaKind library), LibraryView> views;

  /// The last add choices, by instance id.
  final Map<String, AddChoices> addChoices;

  /// The notification subscriptions.
  final List<BackupSubscription> subscriptions;
}

/// Reads [json] as a payload, or returns null if any of it breaks the schema or
/// a rule of manual entry. [withCredentials] says that the file was encrypted;
/// no other may carry a credential.
BackupContent? readBackupContent(
  Object? json, {
  required bool withCredentials,
  required Map<String, ModuleDescriptor> modules,
}) {
  try {
    return _Reader(modules, withCredentials).content(json);
  } on _Invalid {
    return null;
  }
}

/// Reads a date as the format writes it, or null.
DateTime? readBackupDate(Object? value) {
  if (value is! String) return null;
  final date = DateTime.tryParse(value)?.toUtc();
  // Others cannot be stored and read back.
  return date == null || date.year < 1 || date.year > 9999 ? null : date;
}

final class _Invalid implements Exception {
  const _Invalid();
}

Never _refuse() => throw const _Invalid();

T _as<T>(Object? value) => value is T ? value : _refuse();

Map<String, Object?> _object(Object? value) => _as<Map<String, Object?>>(value);

List<Object?> _list(Object? value) => _as<List<Object?>>(value);

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

// As the app stores the SHA-256 of a certificate.
final _fingerprint = RegExp(r'^[0-9a-f]{64}$');

final class _Reader {
  _Reader(this._modules, this._withCredentials);

  final Map<String, ModuleDescriptor> _modules;
  final bool _withCredentials;

  /// Authorities already read, as instances often share one.
  final _authorities = <String, String>{};

  BackupContent content(Object? json) {
    final payload = _object(json);

    final profiles = <String, BackupProfile>{};
    for (final entry in _list(payload['profiles'])) {
      final profile = _profile(_object(entry));
      if (profiles.containsKey(profile.id)) _refuse();
      profiles[profile.id] = profile;
    }

    final instances = <String, BackupInstance>{};
    for (final entry in _list(payload['instances'])) {
      final instance = _instance(_object(entry));
      if (instances.containsKey(instance.id) ||
          !profiles.containsKey(instance.profileId)) {
        _refuse();
      }
      instances[instance.id] = instance;
    }
    for (final instance in instances.values) {
      _checkLinks(instance, instances);
    }

    final preferences = _object(payload['preferences']);
    final subscriptions = <(String, String), BackupSubscription>{};
    for (final entry in _list(payload['subscriptions'])) {
      final subscription = _subscription(_object(entry));
      final key = (subscription.instanceId, subscription.eventType);
      if (subscriptions.containsKey(key) ||
          !instances.containsKey(subscription.instanceId)) {
        _refuse();
      }
      subscriptions[key] = subscription;
    }

    return BackupContent._(
      profiles: [...profiles.values],
      instances: [...instances.values],
      preferences: _preferences(preferences),
      views: _views(preferences['view'], profiles, instances),
      addChoices: _addChoices(preferences['lastAddChoices'], instances),
      subscriptions: [...subscriptions.values],
    );
  }

  BackupProfile _profile(Map<String, Object?> json) => (
    id: _id(json['id']),
    name: _name(json['name']),
    sortOrder: _position(json['sortOrder']),
  );

  BackupInstance _instance(Map<String, Object?> json) {
    final serviceType = _as<String>(json['serviceType']);
    final module = _modules[serviceType] ?? _refuse();
    final url = Uri.tryParse(_as<String>(json['url'])) ?? _refuse();
    if (!isValidInstanceUrl(url)) _refuse();
    // The form offers no others.
    final authKind =
        AuthKind.values.asNameMap()[_as<String>(json['authKind'])] ?? _refuse();
    if (!module.authKinds.contains(authKind)) _refuse();

    final certPin = _as<String?>(json['certPin']);
    if (certPin != null && !_fingerprint.hasMatch(certPin)) _refuse();

    return (
      id: _id(json['id']),
      profileId: _id(json['profileId']),
      name: _name(json['name']),
      serviceType: serviceType,
      url: url,
      authKind: authKind,
      certPin: certPin,
      customCa: _authority(_as<String?>(json['customCa'])),
      enabled: _as<bool>(json['enabled']),
      sortOrder: _position(json['sortOrder']),
      links: [for (final link in _list(json['links'])) _link(_object(link))],
      createdAt: _date(json['createdAt']),
      credential: _credential(json['credential'], module, authKind),
    );
  }

  String _id(Object? value) {
    final id = _as<String>(value);
    return _uuid.hasMatch(id) ? id : _refuse();
  }

  String _name(Object? value) {
    final name = _as<String>(value);
    return hasValidNameLength(name) ? name : _refuse();
  }

  int _position(Object? value) {
    final position = _as<int>(value);
    // Bounded, so that there is always a position after it.
    return position >= 0 && position <= 0x7fffffff ? position : _refuse();
  }

  DateTime _date(Object? value) => readBackupDate(value) ?? _refuse();

  /// The certificates alone, as the app stores an authority that is imported
  /// by hand.
  String? _authority(String? given) {
    if (given == null) return null;
    if (!fitsCustomCa(given)) _refuse();
    return _authorities[given] ??= switch (readCertificateAuthority(
      utf8.encode(given),
    )) {
      Ok(:final value) => value.pem,
      Err() => _refuse(),
    };
  }

  InstanceLink _link(Map<String, Object?> json) => InstanceLink(
    type:
        InstanceLinkType.values.asNameMap()[_as<String>(json['type'])] ??
        _refuse(),
    instanceId: _id(json['instanceId']),
  );

  void _checkLinks(
    BackupInstance instance,
    Map<String, BackupInstance> instances,
  ) {
    if (instance.links.isEmpty) return;
    if (_modules[instance.serviceType]!.category != ModuleCategory.subtitles) {
      _refuse();
    }
    // At most one of each category.
    final linked = <ModuleCategory>{};
    for (final link in instance.links) {
      final target = instances[link.instanceId] ?? _refuse();
      final category = _modules[target.serviceType]!.category;
      if (target.profileId != instance.profileId ||
          !isSubtitleTarget(category) ||
          !linked.add(category)) {
        _refuse();
      }
    }
  }

  /// Read strictly, unlike `decodeCredential`: what is not understood must not
  /// be dropped unnoticed. A session cookie, or anything else unknown, is
  /// ignored.
  Credential? _credential(
    Object? value,
    ModuleDescriptor module,
    AuthKind authKind,
  ) {
    if (value == null) return null;
    if (!_withCredentials) _refuse();
    final json = _object(value);
    String? text(String key) => _as<String?>(json[key]);

    final headers = <String, String>{};
    final given = _as<Map<String, Object?>?>(json['customHeaders']);
    for (final MapEntry(:key, :value) in (given ?? const {}).entries) {
      if (!isValidHeaderName(key)) _refuse();
      headers[key] = _as<String>(value);
    }
    final credential = Credential(
      apiKey: text('apiKey'),
      username: text('username'),
      password: text('password'),
      basicUser: text('basicUser'),
      basicPassword: text('basicPassword'),
      customHeaders: headers,
    );
    if (excludesBasicAuth(module, authKind) && hasBasicAuth(credential)) {
      _refuse();
    }
    final isEmpty =
        credential.apiKey == null &&
        credential.username == null &&
        credential.password == null &&
        !hasBasicAuth(credential) &&
        headers.isEmpty;
    return isEmpty ? null : credential;
  }

  BackupPreferences _preferences(Map<String, Object?> json) {
    final themeMode = _as<String?>(json['themeMode']);
    return (
      themeMode: themeMode == null
          ? null
          : AppThemeMode.values.asNameMap()[themeMode] ?? _refuse(),
      trueBlack: _as<bool?>(json['trueBlack']),
      dynamicColor: _as<bool?>(json['dynamicColor']),
      loadThirdPartyArtwork: _as<bool?>(json['loadThirdPartyArtwork']),
    );
  }

  Map<(String, MediaKind), LibraryView> _views(
    Object? value,
    Map<String, BackupProfile> profiles,
    Map<String, BackupInstance> instances,
  ) {
    final views = <(String, MediaKind), LibraryView>{};
    final byProfile = _as<Map<String, Object?>?>(value) ?? const {};
    for (final MapEntry(key: profileId, value: libraries)
        in byProfile.entries) {
      if (!profiles.containsKey(profileId)) _refuse();
      for (final MapEntry(key: name, value: entry) in _object(
        libraries,
      ).entries) {
        final library = MediaKind.values.asNameMap()[name] ?? _refuse();
        if (!viewLibraries.contains(library)) _refuse();
        final json = _object(entry);
        final view = LibraryView(
          layout:
              LibraryLayout.values.asNameMap()[_as<String>(json['layout'])] ??
              _refuse(),
          sort: sortFromJson(_object(json['sort'])),
          filters: filtersFromJson(_object(json['filters'])),
          instanceScope: _as<String?>(json['instanceScope']),
        );
        // As when a view is read: only instances of its profile resolve.
        views[(profileId, library)] = view.mapInstances(
          (id) => instances[id]?.profileId == profileId ? id : null,
        );
      }
    }
    return views;
  }

  Map<String, AddChoices> _addChoices(
    Object? value,
    Map<String, BackupInstance> instances,
  ) {
    final choices = <String, AddChoices>{};
    final given = _as<Map<String, Object?>?>(value) ?? const {};
    for (final MapEntry(key: id, value: entry) in given.entries) {
      if (!instances.containsKey(id)) _refuse();
      choices[id] = addChoicesFromJson(_object(entry)) ?? _refuse();
    }
    return choices;
  }

  BackupSubscription _subscription(Map<String, Object?> json) {
    final eventType = _as<String>(json['eventType']);
    if (!subscriptionEventTypes.contains(eventType)) _refuse();
    return (
      instanceId: _id(json['instanceId']),
      eventType: eventType,
      enabled: _as<bool>(json['enabled']),
    );
  }
}
