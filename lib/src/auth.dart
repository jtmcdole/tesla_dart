import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_fetcher.dart';

class Auth {
  static const String clientId =
      '81527cff06843c8634fdc09e8ac0abefb46ac849f38fe1e431c2ef2106796384';
  static const String clientSecret =
      'c7257eb71a564034f9419ee651c7d0e5f7aa6bfbd18bafb5c5c033b093bb2fa3';

  Map<String, dynamic> _json = {};

  Auth(this._json);

  String get accessToken => _json['access_token'];

  String get refreshToken => _json['refresh_token'];

  DateTime get created => _json.containsKey('created_at')
      ? new DateTime.fromMillisecondsSinceEpoch(_json['created_at'])
      : null;

  DateTime get expires =>
      _json.containsKey('created_at') && _json.containsKey('expires_in')
          ? new DateTime.fromMillisecondsSinceEpoch(
              (_json['created_at'] + _json['expires_in']) * 1000)
          : null;

  bool get isExpired => new DateTime.now().isAfter(expires);

  static Future<Auth> createFromCache(File cacheFile) async {
    if (!await cacheFile.exists()) {
      print("Authentication cache missing.");
      return null;
    }

    var cache = await cacheFile.readAsString();
    if (cache == null) {
      print("Authentication cache empty or corrupt.");
      return null;
    }

    var json = JSON.decode(cache);
    if (json == null || json.isEmpty) {
      print("Authentication cache empty or corrupt.");
      return null;
    }

    var auth = new Auth(json);

    // Validate the credentials, and return null if any are invalid.
    if (auth.accessToken == null ||
        auth.refreshToken == null ||
        auth.created == null ||
        auth.expires == null) {
      print("Authentication cache incomplete or invalid.");
      return null;
    }

    // Check for imminent expiration.
    print("Token expires at: ${auth.expires}");
    var fiveMinutes = const Duration(minutes: 5);
    var checkTime = new DateTime.now().add(fiveMinutes);
    if (checkTime.isAfter(auth.expires)) {
      var refreshed = auth.refresh();
      if (refreshed != null) {
        auth = refreshed;
      }
      print("Failed to refresh stale credentials");
      return null;
    }

    return auth;
  }

  static Future<Auth> createFromCreds(String email, String password) async {
    var data = {
      "grant_type": "password",
      "client_id": clientId,
      "client_secret": clientSecret,
      "email": email,
      "password": password
    };
    var response = await http
        .post('${ApiFetcher.apiUrl}/${ApiFetcher.authPath}', body: data);
    var body = response.body;
    var auth;
    if (body != null && body.isNotEmpty) {
      var responseData = JSON.decode(body);
      if (responseData is Map && responseData.containsKey('access_token')) {
        auth = new Auth(responseData);
      }
    }

    return auth;
  }

  Future refresh() async {
    if (refreshToken == null) {
      return null;
    }

    var data = {
      "grant_type": "refresh_token",
      "client_id": clientId,
      "client_secret": clientSecret,
      "refresh_token": refreshToken,
    };
    var response = await http
        .post('${ApiFetcher.apiUrl}/${ApiFetcher.authPath}', body: data);
    var body = response.body;
    if (response.statusCode != 200) {
      return null;
    }
    if (body != null && body.isNotEmpty) {
      var responseData = JSON.decode(body);
      if (responseData is Map && responseData.containsKey('access_token')) {
        _json = responseData;
        return this;
      }
    }
    return null;
  }

  Future writeToCache(File cacheFile) async {
    return cacheFile.writeAsString(JSON.encode(_json));
  }
}
