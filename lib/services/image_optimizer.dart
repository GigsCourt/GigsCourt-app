class ImageOptimizer {
  static String thumbnail(String url, {int width = 200, int height = 200}) {
    return '$url?tr=w-$width,h-$height,fo-face';
  }

  static String medium(String url, {int width = 600, int height = 800}) {
    return '$url?tr=w-$width,h-$height,fo-face';
  }

  static String original(String url) {
    return url;
  }
}