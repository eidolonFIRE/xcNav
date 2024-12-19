import 'dart:math';

import 'package:xcnav/util.dart';

/// Function to calculate a 1D Gaussian kernel
List<double> gaussianKernel(double sigma, int size) {
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

List<TimestampDouble> gaussianFilterTimestamped(List<TimestampDouble> data, double sigma, int kernelSize) {
  if (kernelSize % 2 == 0) {
    throw ArgumentError("Kernel size must be odd.");
  }

  final List<double> kernel = gaussianKernel(sigma, kernelSize);
  final int halfSize = kernelSize ~/ 2;
  final List<TimestampDouble> result = [];

  for (int i = 0; i < data.length; i++) {
    double filteredY = 0;
    for (int j = 0; j < kernelSize; j++) {
      int dataIndex = i + j - halfSize;
      if (dataIndex >= 0 && dataIndex < data.length) {
        filteredY += data[dataIndex].value * kernel[j];
      }
    }
    result.add(TimestampDouble(data[i].time, filteredY));
  }

  return result;
}
