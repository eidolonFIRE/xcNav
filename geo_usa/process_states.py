import xml.etree.ElementTree as ET

def parse_kml(file_path):
    # Parse the KML file
    tree = ET.parse(file_path)
    root = tree.getroot()

    # Namespace dictionary
    namespaces = {
        'kml': 'http://www.opengis.net/kml/2.2',
        'gx': 'http://www.google.com/kml/ext/2.2',
        'atom': 'http://www.w3.org/2005/Atom'
    }

    # Dictionary to store the placemarks
    placemarks = {}

    # Find all Placemark elements
    for placemark in root.findall('.//kml:Placemark', namespaces):
        name = placemark.find('kml:name', namespaces).text
        polygon = placemark.find('.//kml:Polygon', namespaces)
        if polygon is not None:
            coordinates = polygon.find('.//kml:coordinates', namespaces).text
            # Split the coordinates into individual points
            points = [tuple(map(float, point.split(','))) for point in coordinates.strip().split()]
            # Extract only latitude and longitude
            # Round to 3 digits (~111m precision)
            # last point is repeated, so leave it off
            latlng_points = [(round(float(lat), 3), round(((float(lng) + 180) % 360) - 180, 3)) for lng, lat, _ in points[:-1]]
            placemarks[name] = latlng_points

    return placemarks


placemarks = parse_kml('states/states.kml')

# Print the parsed placemarks
with open("out.dart", "w") as outfile:
    outfile.write("const Map<String, List<LatLng>> statePolygons = {\n")
    for name, points in placemarks.items():

        points_str = [f"LatLng({lat}, {lng})" for lat, lng in points]
        outfile.write(f'  "{name}": [{", ".join(points_str)}],\n')
    outfile.write("};")
