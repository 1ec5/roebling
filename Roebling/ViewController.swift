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

class ViewController: UIViewController, MGLMapViewDelegate {
    @IBOutlet weak var mapView: MGLMapView!
    
    var osmTask: NSURLSessionTask?
    var wikidataTask: NSURLSessionTask?
    var architectName: String?
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
        guard let feature = features.filter({ $0.identifier != nil }).first else {
            return
        }
        
        // Visualize the feature.
        mapView.addAnnotation(feature)
        
        performSelector(#selector(showFeaturesRelatedToFeature(_:)), withObject: feature, afterDelay: 0.3)
    }
    
    func showFeaturesRelatedToFeature(feature: MGLFeature) {
        guard let element = OSMElement(feature: feature) else {
            return
        }
        
        // Get images of related features.
        getTagsForOSMElement(element) { (tags) in
            guard let wikidataIdentifier = tags["wikidata"] where wikidataIdentifier.hasPrefix("Q") else {
                return
            }
            let languages = (NSLocale.preferredLanguages().flatMap {
                $0.componentsSeparatedByString("-").first
            } + ["en"]).joinWithSeparator(",")
            let wikidataQuery = "SELECT ?pic ?architectLabel WHERE { wd:\(wikidataIdentifier) wdt:P84 ?architect . ?item wdt:P84 ?architect . ?item wdt:P18 ?pic . SERVICE wikibase:label { bd:serviceParam wikibase:language \"\(languages)\". } }"
            self.getImageURLsForWikidataQuery(wikidataQuery) { (architectName, imageURLs) in
                self.architectName = architectName
                self.imageURLs = imageURLs
                
                // Show a gallery of the images.
                self.performSegueWithIdentifier("ShowGallery", sender: self)
            }
        }
    }
    
    /**
     Fetches the tags on the given OpenStreetMap element using the Overpass API, calling the completion handler with any results.
     */
    func getTagsForOSMElement(element: OSMElement, completionHandler: (tags: [String: String]) -> Void) {
        let url = NSURL(string: "https://overpass-api.de/api/interpreter?data=[out:json];\(element);out;")!
        osmTask = NSURLSession.sharedSession().dataTaskWithURL(url) { (data, response, error) in
            guard let data = data else {
                return
            }
            
            let overpassResults: [String: AnyObject]
            do {
                overpassResults = try NSJSONSerialization.JSONObjectWithData(data, options: []) as! [String : AnyObject]
            } catch {
                return
            }
            
            guard let element = (overpassResults["elements"] as? [AnyObject])?.first, tags = element["tags"] as? [String: String] else {
                return
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler(tags: tags)
            }
        }
        osmTask!.resume()
    }
    
    /**
     Executes the given query in the Wikidata Query Service, calling the completion handler with any resulting image URLs.
     */
    func getImageURLsForWikidataQuery(query: String, completionHandler: (architectName: String?, imageURLs: [NSURL]) -> Void) {
        let escapedQuery = query.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())!
        let url = NSURL(string: "https://query.wikidata.org/bigdata/namespace/wdq/sparql?format=json&query=\(escapedQuery)")!
        wikidataTask = NSURLSession.sharedSession().dataTaskWithURL(url) { (data, response, error) in
            guard let data = data else {
                return
            }
            
            let apiResponse: [String: AnyObject]
            do {
                apiResponse = try NSJSONSerialization.JSONObjectWithData(data, options: []) as! [String : AnyObject]
            } catch {
                return
            }
            
            guard let results = apiResponse["results"] as? [String: [[String: [String: String]]]], bindings = results["bindings"] else {
                return
            }
            
            let architectName = bindings.first?["architectLabel"]?["value"]
            let imageURLs: [NSURL] = bindings.flatMap { $0["pic"]?["value"] }.flatMap {
                let components = NSURLComponents(string: $0)
                if components?.scheme == "http" {
                    components?.scheme = "https"
                }
                return components?.URL!
            }
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler(architectName: architectName, imageURLs: imageURLs)
            }
        }
        wikidataTask!.resume()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        switch segue.identifier ?? "" {
        case "ShowGallery":
            if let controller = segue.destinationViewController as? GalleryViewController {
                if let architectName = architectName {
                    controller.title = architectName
                }
                controller.imageURLs = imageURLs
            }
        default:
            break
        }
    }
    
    // MARK: MGLMapViewDelegate methods
    
    func mapView(mapView: MGLMapView, alphaForShapeAnnotation annotation: MGLShape) -> CGFloat {
        return 0.8
    }
    
    func mapView(mapView: MGLMapView, lineWidthForPolylineAnnotation annotation: MGLPolyline) -> CGFloat {
        return 10
    }
    
    func mapView(mapView: MGLMapView, strokeColorForShapeAnnotation annotation: MGLShape) -> UIColor {
        return UIColor(red: 0.4776530861854553, green: 0.2292086482048035, blue: 0.9591622352600098, alpha: 1)
    }
}

