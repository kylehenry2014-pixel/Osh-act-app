import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Network availability is not the same as internet reachability.
/// This service performs bounded, shared HTTPS checks.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance =
      ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  Future<bool>? _activeCheck;

  bool? _lastResult;
  final Stopwatch _cacheAge = Stopwatch();

  static const _cacheDuration = Duration(seconds: 5);

  static final _endpoints = <Uri>[
    Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
    Uri.parse('https://www.google.com/generate_204'),
  ];

  void invalidateCache() {
    _lastResult = null;
    _cacheAge
      ..stop()
      ..reset();
  }

  Future<bool> isOnline() {
    final active = _activeCheck;

    if (active != null) return active;

    final cached = _lastResult;

    if (cached != null &&
        _cacheAge.elapsed < _cacheDuration) {
      return Future.value(cached);
    }

    late final Future<bool> operation;

    operation = _checkInternet().then((online) {
      _lastResult = online;

      _cacheAge
        ..reset()
        ..start();

      return online;
    }).whenComplete(() {
      if (identical(_activeCheck, operation)) {
        _activeCheck = null;
      }
    });

    _activeCheck = operation;

    return operation;
  }

  Future<bool> _checkInternet() async {
    try {
      final networks = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));

      final hasNetwork = networks.any(
        (network) => network != ConnectivityResult.none,
      );

      if (!hasNetwork) return false;
    } catch (_) {
      // A platform connectivity error is not proof of
      // internet loss. Continue with the HTTPS probes.
    }

    final result = Completer<bool>();
    var remaining = _endpoints.length;

    for (final endpoint in _endpoints) {
      unawaited(_probe(endpoint).then((reachable) {
        remaining--;

        if (result.isCompleted) return;

        if (reachable) {
          result.complete(true);
        } else if (remaining == 0) {
          result.complete(false);
        }
      }));
    }

    return result.future;
  }

  Future<bool> _probe(Uri endpoint) async {
    final client = http.Client();

    try {
      final request = http.Request('GET', endpoint)
        ..followRedirects = false
        ..headers['Cache-Control'] = 'no-cache';

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Rechecks internet reachability when the network changes.
  /// The application itself is never removed from the widget tree.
  Stream<bool> get onStatusChanged {
    return _connectivity.onConnectivityChanged
        .asyncMap((_) async {
          invalidateCache();

          final pending = _activeCheck;

          if (pending != null) {
            await pending;
            invalidateCache();
          }

          return isOnline();
        })
        .distinct();
  }
}