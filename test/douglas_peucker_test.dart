import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/douglas_peucker.dart';

void main() {
  test('Test with empty list', () {
    List<double> points = [];
    double epsilon = 1.0;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals([]));
  });

  test('Test with single point', () {
    List<double> points = [2.0];
    double epsilon = 1.0;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals([2.0]));
  });

  test('Test with two points', () {
    List<double> points = [1.0, 3.0];
    double epsilon = 1.0;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals([1.0, 3.0]));
  });

  test('Test with multiple points, no simplification', () {
    List<double> points = [1.0, 3.0, 2.0, 5.0, 4.0];
    double epsilon = 0.1;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals(points));
  });

  test('Test with multiple points, simplification', () {
    List<double> points = [1.0, 2.0, 3.0, 4.0, 5.0];
    double epsilon = 1.0;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals([1.0, 5.0]));
  });

  test('Test with custom polyline and epsilon', () {
    List<double> points = [1.0, 2.5, 4.0, 5.5, 7.0];
    double epsilon = 1.5;
    List<double> simplified = douglasPeucker(points, epsilon);
    expect(simplified, equals([1.0, 7.0]));
  });
}
