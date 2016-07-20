import Foundation
import Mapbox

/**
 An element in OpenStreetMap data. In OpenStreetMap, the same number can be a node ID, way ID, or relation ID, so we use an enumeration with an associated value to avoid ambiguity.
 */
enum OSMElement: CustomStringConvertible {
    case Node(identifier: Int)
    case Way(identifier: Int)
    case Relation(identifier: Int)
    
    /**
     Creates an `OSMElement` instance from the given feature obtained from the Mapbox Streets data source.
     */
    init?(feature: MGLFeature) {
        // A feature identifier of 0 means that Mapbox Streets has unioned multiple OSM features into one feature for performance reasons.
        guard let featureIdentifier = feature.identifier as? Int where featureIdentifier > 0 else {
            return nil
        }
        
        let identifier = featureIdentifier / 10
        switch featureIdentifier % 10 {
        case 0:
            self = .Node(identifier: identifier)
        case 1, 2:
            self = .Way(identifier: identifier)
        case 3, 4:
            self = .Relation(identifier: identifier)
        default:
            return nil
        }
    }
    
    /**
     Returns the Overpass query language representation of the element.
     */
    var description: String {
        switch self {
        case Node(let identifier):
            return "node(\(identifier))"
        case Way(let identifier):
            return "way(\(identifier))"
        case Relation(let identifier):
            return "relation(\(identifier))"
        }
    }
}
