class Secrets {
  static const String googleMapsApiKeyAndroid = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY_ANDROID',
    defaultValue: '',
  );

  static const String googleMapsApiKeyIos = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY_IOS',
    defaultValue: '',
  );

  static bool get isAndroidKeySet => googleMapsApiKeyAndroid.isNotEmpty;
  static bool get isIosKeySet => googleMapsApiKeyIos.isNotEmpty;
}