import UIKit
import Mapbox

// All the Mapbox Streets v9 layers that draw from the #roads source layer and start with “bridge-”. Features in these layers are more likely to have `wikidata` tags referring to Wikidata items that themselves are tagged with architects.
let layers = Set(arrayLiteral:
    "bridge-aerialway",
    "bridge-construction",
    "bridge-motorway",
    "bridge-motorway_link",
    "bridge-motorway_link-case",
    "bridge-motorway-case",
    "bridge-oneway-arrows-motorway",
    "bridge-oneway-arrows-other",
    "bridge-oneway-arrows-trunk",
    "bridge-path",
    "bridge-path-bg",
    "bridge-pedestrian",
    "bridge-pedestrian-case",
    "bridge-primary",
    "bridge-primary-case",
    "bridge-rail",
    "bridge-rail-tracks",
    "bridge-secondary-tertiary",
    "bridge-secondary-tertiary-case",
    "bridge-service-link-track",
    "bridge-service-link-track-case",
    "bridge-street",
    "bridge-street_limited",
    "bridge-street_limited-case",
    "bridge-street_limited-low",
    "bridge-street-case",
    "bridge-street-low",
    "bridge-trunk",
    "bridge-trunk_link",
    "bridge-trunk_link-case",
    "bridge-trunk-case")

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

class ViewController: UIViewController {
    @IBOutlet weak var mapView: MGLMapView!
    
    var imageURLs: [NSURL] = []
    
    /**
     Responds to a long press gesture by showing related features in a gallery.
     */
    @IBAction func showRelatedFeatures(gesture: UILongPressGestureRecognizer) {
        // Only act once per gesture, once the finger has been pressed long enough to trigger the gesture recognizer but not after.
        guard gesture.state == .Began else {
            return
        }
        
        // Query the map for visible features at the pressed location.
        let features = mapView.visibleFeatures(at: gesture.locationInView(mapView), styleLayerIdentifiers: layers)
        guard let feature = features.filter({ $0.identifier != nil }).first, element = OSMElement(feature: feature) else {
            return
        }
        
        // Visualize the feature.
        mapView.addAnnotation(feature)
        
        // Get images of related features.
        guard let wikidataIdentifier = tagsForOSMElement(element)?["wikidata"] where wikidataIdentifier.hasPrefix("Q") else {
            return
        }
        let wikidataQuery = "SELECT ?pic WHERE { wd:\(wikidataIdentifier) wdt:P84 ?architect . ?item wdt:P84 ?architect . ?item wdt:P18 ?pic . }"
        imageURLs = resultsForWikidataQuery(wikidataQuery) ?? []
        
        // Show a gallery of the images.
        performSegueWithIdentifier("ShowGallery", sender: self)
    }
    
    /**
     Returns the tags on the given OpenStreetMap element using the Overpass API.
     */
    func tagsForOSMElement(element: OSMElement) -> [String: String]? {
        let osmURL = NSURL(string: "https://overpass-api.de/api/interpreter?data=[out:json];\(element);out;")!
        guard let osmData = NSData(contentsOfURL: osmURL) else {
            return nil
        }
        
        let overpassResults: [String: AnyObject]
        do {
            overpassResults = try NSJSONSerialization.JSONObjectWithData(osmData, options: []) as! [String : AnyObject]
        } catch {
            return nil
        }
        
        guard let element = (overpassResults["elements"] as? [AnyObject])?.first else {
            return nil
        }
        
        return element["tags"] as? [String: String]
    }
    
    /**
     Returns results from executing the given query in the Wikidata Query Service.
     */
    func resultsForWikidataQuery(query: String) -> [NSURL]? {
        let escapedWikidataQuery = query.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())!
        let wikidataQueryURL = NSURL(string: "https://query.wikidata.org/bigdata/namespace/wdq/sparql?format=json&query=\(escapedWikidataQuery)")!
        guard let wikidataQueryData = NSData(contentsOfURL: wikidataQueryURL) else {
            return nil
        }
        
        let wikidataQueryResponse: [String: AnyObject]
        do {
            wikidataQueryResponse = try NSJSONSerialization.JSONObjectWithData(wikidataQueryData, options: []) as! [String : AnyObject]
        } catch {
            return nil
        }
        
        guard let wikidataQueryResults = wikidataQueryResponse["results"] as? [String: [[String: [String: String]]]],
            bindings = wikidataQueryResults["bindings"] else {
            return nil
        }
        
        return bindings.flatMap { $0["pic"]?["value"] }.flatMap {
            let components = NSURLComponents(string: $0)
            if components?.scheme == "http" {
                components?.scheme = "https"
            }
            return components?.URL!
        }
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        switch segue.identifier ?? "" {
        case "ShowGallery":
            if let controller = segue.destinationViewController as? GalleryViewController {
                controller.imageURLs = imageURLs
            }
        default:
            break
        }
    }
}

