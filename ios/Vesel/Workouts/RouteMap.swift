import MapKit
import SwiftUI
import VeselCore

/// The phone's route on Apple's map (decision `2026-11-03-route-map.md`): MapKit fetches only the tiles for this area while
/// it shows; the line is drawn on the phone. No points of interest, no interaction, no search, place names or Look Around,
/// and never the phone's own location. Offline, MapKit shows its empty grid with the line still drawn.
struct RouteMap: View {
    let points: [RoutePoint]
    /// What VoiceOver reads for it: "8.4 km · 11.9 km/h average".
    let summary: String

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The route's bounds with a margin around them.
    private var camera: MapCameraPosition {
        let rect = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
        let margin = max(rect.width, rect.height) * 0.2 + 200
        return .rect(rect.insetBy(dx: -margin, dy: -margin))
    }

    var body: some View {
        let coordinates = coordinates
        Map(initialPosition: camera, interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.Palette.workout, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Circle()
                        .fill(Theme.Palette.workout)
                        .stroke(Theme.Palette.surface, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
                .annotationTitles(.hidden)
            }
            if let end = coordinates.last {
                Annotation("End", coordinate: end) {
                    Circle()
                        .fill(Theme.Palette.surface)
                        .stroke(Theme.Palette.workout, lineWidth: 4)
                        .frame(width: 14, height: 14)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(.rect(cornerRadius: Theme.Corner.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route on the map, from a filled dot at the start to a ring at the end")
        .accessibilityValue(summary)
    }
}

#if DEBUG
#Preview {
    let start = Date(timeIntervalSince1970: 1_792_900_000)
    let points = (0..<200).map {
        RoutePoint(
            time: start.addingTimeInterval(Double($0) * 5), latitude: 52.52 + sin(Double($0) / 40) * 0.01,
            longitude: 13.40 + Double($0) * 0.0002, accuracy: 5)
    }
    RouteMap(points: points, summary: "8.4 km · 11.9 km/h average")
        .padding(Theme.Spacing.edge)
}
#endif
