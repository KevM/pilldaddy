import Foundation

// DailyMed search response structures
struct DailyMedSearchResponse: Codable {
    let data: [DailyMedSearchResult]
}

struct DailyMedSearchResult: Codable, Identifiable {
    var id: String { setid }
    let setid: String
    let title: String
    let spl_version: Int
    let published_date: String
}

// DailyMed media response structures
struct DailyMedMediaResponse: Codable {
    let data: DailyMedMediaData
}

struct DailyMedMediaData: Codable {
    let media: [DailyMedMediaItem]
}

struct DailyMedMediaItem: Codable {
    let name: String
    let mime_type: String
    let url: String
}

// RxNorm response structures
struct RxNormResponse: Codable {
    let ndcPropertyList: RxNormNdcPropertyList?
}

struct RxNormNdcPropertyList: Codable {
    let ndcProperty: [RxNormNdcProperty]?
}

struct RxNormNdcProperty: Codable {
    let ndc10: String?
    let splSetIdItem: String?
    let propertyConceptList: RxNormPropertyConceptList?
}

struct RxNormPropertyConceptList: Codable {
    let propertyConcept: [RxNormPropertyConcept]?
}

struct RxNormPropertyConcept: Codable {
    let propName: String
    let propValue: String
}

class MedicationAPIService {
    static let shared = MedicationAPIService()
    private init() {}
    
    func searchMedications(name: String) async throws -> [DailyMedSearchResult] {
        guard !name.isEmpty else { return [] }
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlString = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?drug_name=\(encodedName)&pagesize=8"
        guard let url = URL(string: urlString) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(DailyMedSearchResponse.self, from: data)
        return response.data
    }
    
    struct MedicationDetails {
        let imageUrls: [String]
        let ndc: String?
        let imprint: String?
        let shapeCode: String?
        let shapeText: String?
        let colorCode: String?
        let colorText: String?
        let size: String?
    }
    
    func fetchDetails(for setid: String) async throws -> MedicationDetails {
        // Fetch media
        let mediaUrlString = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls/\(setid)/media.json"
        var imageUrls: [String] = []
        if let mediaUrl = URL(string: mediaUrlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: mediaUrl)
                let response = try JSONDecoder().decode(DailyMedMediaResponse.self, from: data)
                // Filter all image/jpeg or image/png media
                imageUrls = response.data.media.filter { 
                    $0.mime_type.contains("image/") || $0.name.lowercased().hasSuffix(".jpg") || $0.name.lowercased().hasSuffix(".png")
                }.map { $0.url }
            } catch {
                print("Error fetching media for setid \(setid): \(error)")
            }
        }
        
        // Fetch RxNorm Properties
        let rxNormUrlString = "https://rxnav.nlm.nih.gov/REST/ndcproperties.json?id=\(setid)"
        var ndc: String? = nil
        var imprint: String? = nil
        var shapeCode: String? = nil
        var shapeText: String? = nil
        var colorCode: String? = nil
        var colorText: String? = nil
        var size: String? = nil
        
        if let rxNormUrl = URL(string: rxNormUrlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: rxNormUrl)
                let response = try JSONDecoder().decode(RxNormResponse.self, from: data)
                
                if let properties = response.ndcPropertyList?.ndcProperty?.first {
                    ndc = properties.ndc10
                    
                    if let concepts = properties.propertyConceptList?.propertyConcept {
                        for concept in concepts {
                            switch concept.propName {
                            case "IMPRINT_CODE": imprint = concept.propValue
                            case "SHAPE": shapeCode = concept.propValue
                            case "SHAPETEXT": shapeText = concept.propValue
                            case "COLOR": colorCode = concept.propValue
                            case "COLORTEXT": colorText = concept.propValue
                            case "SIZE": size = concept.propValue
                            default: break
                            }
                        }
                    }
                }
            } catch {
                print("Error fetching RxNorm properties for setid \(setid): \(error)")
            }
        }
        
        return MedicationDetails(
            imageUrls: imageUrls,
            ndc: ndc,
            imprint: imprint,
            shapeCode: shapeCode,
            shapeText: shapeText,
            colorCode: colorCode,
            colorText: colorText,
            size: size
        )
    }
    
    // Clean up long, uppercase DailyMed titles
    func cleanTitle(_ title: String) -> String {
        // 1. Remove manufacturer suffix in brackets
        var clean = title.components(separatedBy: " [").first ?? title
        
        // 2. Remove trailing punctuation
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 3. Title case it if it is entirely uppercase
        if clean == clean.uppercased() {
            clean = clean.localizedCapitalized
        }
        
        return clean
    }
}
