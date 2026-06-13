class ImageOptimizer {
  static const _baseUrl = 'https://ik.imagekit.io/GigsKourt';

  static String thumbnail(String url, {int width = 200, int height = 200}) {
    return _transform(url, width, height);
  }

  static String medium(String url, {int width = 600, int height = 800}) {
    return _transform(url, width, height);
  }

  static String original(String url) {
    return url;
  }

  static String _transform(String url, int width, int height) {
    if (!url.contains(_baseUrl)) return url;
    return url.replaceAll(
      _baseUrl,
      '$_baseUrl/tr:w-$width,h-$height,fo-face',
    );
  }
}