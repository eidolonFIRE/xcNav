import 'dart:math';

class Point {
  double x;
  double y;

  Point(this.x, this.y);
}

double perpendicularDistance(Point p, Point a, Point b) {
  double lengthSquared = pow(b.x - a.x, 2).toDouble() + pow(b.y - a.y, 2);

  if (lengthSquared == 0) {
    return sqrt(pow(p.x - a.x, 2) + pow(p.y - a.y, 2));
  }

  double t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / lengthSquared;
  t = max(0, min(1, t));

  Point projection = Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));

  return sqrt(pow(p.x - projection.x, 2) + pow(p.y - projection.y, 2));
}

List<double> douglasPeucker(List<double> points, double epsilon) {
  if (points.isEmpty || points.length == 1) {
    return points;
  }

  int maxIndex = 0;
  double maxDistance = 0;
  final int length = points.length;

  for (int i = 1; i < length - 1; ++i) {
    double distance =
        perpendicularDistance(Point(i.toDouble(), points[i]), Point(0, points.first), Point(length - 1, points.last));
    if (distance > maxDistance) {
      maxIndex = i;
      maxDistance = distance;
    }
  }

  if (maxDistance > epsilon) {
    List<double> left = douglasPeucker(points.sublist(0, maxIndex + 1), epsilon);
    List<double> right = douglasPeucker(points.sublist(maxIndex), epsilon);

    return left.sublist(0, left.length - 1) + right;
  } else {
    return [points.first, points.last];
  }
}
