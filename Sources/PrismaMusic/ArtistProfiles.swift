import Foundation

struct ArtistProfile:Codable,Equatable,Sendable {
    var name:String
    var biography:String
    var pageURL:URL
    var language:String
    var photoURL:URL?
    var photoPageURL:URL?
    var photoCredit:String?
    var photoLicense:String?
}
enum ArtistIdentity {
    static func names(_ raw:String)->[String] {
        var seen=Set<String>()
        return raw.components(separatedBy:";").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func contains(_ raw:String,name:String)->Bool { names(raw).contains { OnlineMetadata.normalized($0) == OnlineMetadata.normalized(name) } }
    static func titleMatches(_ title:String,name:String)->Bool {
        OnlineMetadata.normalized(title.components(separatedBy:" (").first ?? title) == OnlineMetadata.normalized(name)
    }
}
actor ArtistProfileService {
    static let shared=ArtistProfileService()
    private var cache:[String:ArtistProfile]=[:]
    private struct Response:Decodable { var query:Query?; struct Query:Decodable { var pages:[Page]? } }
    private struct Page:Decodable {
        var title:String
        var extract:String?
        var fullurl:String?
        var pageimage:String?
        var pageprops:[String:String]?
    }
    static func isMusical(_ text:String)->Bool {
        let intro=String(text.prefix(800)).folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX"))
        return intro.range(of:"\\b(musician|singer|songwriter|composer|rapper|band|cantante|cantautor|cantautora|musico|compositor|compositora|cantor|cantora|banda|grupo musical|duo musical)\\b",options:.regularExpression) != nil
    }
    func profile(name:String,language:String) async throws -> ArtistProfile? {
        let key=language+":"+OnlineMetadata.normalized(name)
        if let cached=cache[key] { return cached }
        for lang in language == "en" ? ["en"] : [language,"en"] {
            try Task.checkCancellation()
            var found=try await query(name:name,language:lang,search:false)
            if found == nil { found=try await query(name:name,language:lang,search:true) }
            if var value=found {
                try Task.checkCancellation()
                if let photo=value.1 { try? await attachPhoto(photo,to:&value.0) }
                try Task.checkCancellation()
                if cache.count >= 64 { cache.removeAll(keepingCapacity:true) }
                cache[key]=value.0; return value.0
            }
        }
        return nil
    }
    private func query(name:String,language:String,search:Bool) async throws -> (ArtistProfile,String?)? {
        guard ["es","en","pt"].contains(language) else { return nil }
        var parameters=["action":"query","format":"json","formatversion":"2","prop":"extracts|pageimages|info|pageprops","exintro":"1","explaintext":"1","exchars":"1200","piprop":"name","inprop":"url","redirects":"1"]
        if search {
            let escaped=name.replacingOccurrences(of:"\"",with:"")
            parameters["generator"]="search"; parameters["gsrlimit"]="5"
            parameters["gsrsearch"]="intitle:\"\(escaped)\" (music OR musician OR cantante OR compositor OR banda OR cantor)"
        } else { parameters["titles"]=name }
        let (data,code)=try await OnlineMetadata.request(OnlineMetadata.url("https://\(language).wikipedia.org/w/api.php",parameters))
        guard code == 200 else { return nil }
        let pages=try JSONDecoder().decode(Response.self,from:data).query?.pages ?? []
        guard let page=pages.first(where:{ ArtistIdentity.titleMatches($0.title,name:name) && $0.pageprops?["disambiguation"] == nil && Self.isMusical($0.extract ?? "") }),
              let extract=page.extract,!extract.isEmpty,let raw=page.fullurl,let url=URL(string:raw),url.scheme == "https",url.host == "\(language).wikipedia.org" else { return nil }
        return (.init(name:page.title,biography:extract,pageURL:url,language:language),page.pageimage)
    }
    private func attachPhoto(_ filename:String,to profile:inout ArtistProfile) async throws {
        let (data,code)=try await OnlineMetadata.request(OnlineMetadata.url("https://commons.wikimedia.org/w/api.php",["action":"query","format":"json","formatversion":"2","prop":"imageinfo","titles":"File:"+filename,"iiprop":"url|extmetadata","iiurlwidth":"600"]))
        guard code == 200 else { return }
        struct ImageResponse:Decodable {
            var query:Query?
            struct Query:Decodable { var pages:[Page] }
            struct Page:Decodable { var imageinfo:[Info]? }
            struct Info:Decodable { var thumburl:String?; var descriptionurl:String?; var extmetadata:[String:Value]? }
            struct Value:Decodable {
                var value:String
                enum CodingKeys:String,CodingKey { case value }
                init(from decoder:Decoder) throws {
                    let values=try decoder.container(keyedBy:CodingKeys.self)
                    value=(try? values.decode(String.self,forKey:.value)) ?? ""
                }
            }
        }
        guard let info=try JSONDecoder().decode(ImageResponse.self,from:data).query?.pages.first?.imageinfo?.first,
              let raw=info.thumburl,let url=URL(string:raw),url.scheme == "https",["upload.wikimedia.org","thumb.wikimedia.org"].contains(url.host ?? ""),
              let credit=info.descriptionurl.flatMap(URL.init(string:)),credit.scheme == "https",credit.host == "commons.wikimedia.org",
              let license=info.extmetadata?["LicenseShortName"]?.value,!license.isEmpty else { return }
        profile.photoURL=url; profile.photoPageURL=credit; profile.photoLicense=license
        profile.photoCredit=info.extmetadata?["Artist"]?.value.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&")
    }
}
