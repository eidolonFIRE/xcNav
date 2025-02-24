import 'dart:math';

import 'package:xcnav/util.dart';

/// Function to calculate a 1D Gaussian kernel
List<double> _gaussianKernel(double sigma, int size) {
  if (size % 2 == 0) {
    throw ArgumentError("Kernel size must be odd.");
  }

  final int halfSize = size ~/ 2;
  double sum = 0;
  final List<double> kernel = List.filled(size, 0);

  for (int i = 0; i < size; i++) {
    int x = i - halfSize;
    kernel[i] = exp(-0.5 * pow(x / sigma, 2));
    sum += kernel[i];
  }

  // Normalize the kernel
  for (int i = 0; i < size; i++) {
    kernel[i] /= sum;
  }

  return kernel;
}

Iterable<TimestampDouble> gaussianFilterTimestamped(List<TimestampDouble> data, double sigma, int kernelSize) sync* {
  if (kernelSize % 2 == 0) {
    throw ArgumentError("Kernel size must be odd.");
  }

  final List<double> kernel = _gaussianKernel(sigma, kernelSize);
  final int halfSize = kernelSize ~/ 2;

  for (int i = 0; i < data.length; i++) {
    double filteredY = 0;
    for (int j = 0; j < kernelSize; j++) {
      int dataIndex = i + j - halfSize;
      if (dataIndex >= 0 && dataIndex < data.length) {
        filteredY += data[dataIndex].value * kernel[j];
      } else {
        // clamp kernel rather than drop values. This prevents a odd data when there's bias.
        filteredY += data[i].value * kernel[j];
      }
    }
    yield TimestampDouble(data[i].time, filteredY);
  }
}
