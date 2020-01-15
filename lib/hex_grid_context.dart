class HexGridContext {
  ///Size of a individual hex widget (length of each border)
  final double size;

  ///Controls the speed of the flingAnimation. The larger the number the faster
  /// the fling animation will play
  final double velocityFactor;

  HexGridContext(this.size, this.velocityFactor);
}
