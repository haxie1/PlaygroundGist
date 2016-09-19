
import Foundation
import PlaygroundSupport

public extension PlaygroundPage {
    
    #if (arch(i386) || arch(x86_64)) && os(iOS)
    // PlaygroundPage doesn't have a text property on sim or OS X
    // so we try to read out the file from the temp path and use its contents
    var text: String {
        print("------ can't post playground gists from mac based Playgrounds -----")
        return ""
    }
    #endif
    
    var gistableText: String {
        // TODO: strip out the calling code from the playground page
        // Need a way to mark this line in the playground page.
        var results = self.text.components(separatedBy: CharacterSet.newlines)
        if results.count < self.postGistLineNumber! {
            return ""
        }
        
        results.remove(at: self.postGistLineNumber!)
        return results.joined()
    }
    
    @nonobjc static var lineKey = "PostGistCallerLineKey"
    private var postGistLineNumber: Int? {
        set (newValue) {
            objc_setAssociatedObject(self, &PlaygroundPage.lineKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        get {
            return objc_getAssociatedObject(self, &PlaygroundPage.lineKey) as? Int
        }
    }
    
    public func postGist(withDescription description: String, fileName: String, configuration: PostConfiguration, line: Int = #line, completion: @escaping (PostResult) -> Void) {
        self.needsIndefiniteExecution = true
        self.postGistLineNumber = line
        
        let gist = Gist(description: description, fileName: fileName, configuration: configuration)
        gist.post(page: self) { (result) in
            completion(result)
            
            self.finishExecution()
        }
    }
}

public enum PostResult {
    case error(Error)
    case result(URL)
}

public enum PostError: Error {
    case unknown
    case noPlaygroundData
}

public enum PostConfiguration {
    case anonymous
    
    // requires Github Personal Access Token: https://help.github.com/articles/creating-an-access-token-for-command-line-use/
    case user(oauthToken:String, isPublic:Bool)
}

struct Gist {
    let url: URL
    let description: String
    let fileName: String
    let configuration: PostConfiguration
    
    private var isPublic: Bool {
        switch self.configuration {
        case .anonymous: return true
        case .user(_, let visibility): return visibility
        }
    }
    
    private var urlRequest: URLRequest {
        var request: URLRequest = URLRequest(url: self.url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        switch self.configuration {
        case .user(let token, _):
            request.addValue("token \(token)", forHTTPHeaderField: "Authorization")
        default: break
        }
        
        return request
    }
    
    init(withURL url: URL, _ description: String, _ fileName: String, _ configuration: PostConfiguration) {
        self.url = url
        self.description = description
        self.fileName = fileName
        self.configuration = configuration
    }
    
    init(withURLString string: String = "https://api.github.com/gists", description: String, fileName: String, configuration: PostConfiguration) {
        self.init(withURL: URL(string: string)!, description, fileName, configuration)
    }
    
    func post(page: PlaygroundPage, completion: @escaping (PostResult) -> Void) {
        guard let json = self.json(withPath: page) else {
            completion(PostResult.error(PostError.noPlaygroundData))
            return
        }
        
        var request = self.urlRequest
        request.httpBody = json
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let errorResult: (Error?) -> PostResult = { (error) in
                return PostResult.error(error ?? PostError.unknown)
            }
            
            guard let response = response as? HTTPURLResponse else {
                completion(errorResult(error))
                return
            }
            
            // https://developer.github.com/v3/gists/#create-a-gist returns a 201 for success
            if response.statusCode != 201 {
                completion(errorResult(error))
                return
            }
            
            guard let data = data else {
                completion(errorResult(error))
                return
            }
            
            guard let jsonData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                completion(errorResult(error))
                return
            }
            
            if let htmlURLString = jsonData!["html_url"] as? String {
                let url = URL(string: htmlURLString)!
                completion(.result(url))
            } else {
                completion(errorResult(error))
            }
        }
        
        task.resume()
    }
    
    private func json(withPath page: PlaygroundPage) -> Data? {
        guard !page.gistableText.isEmpty else {
            return nil
        }
        
        let textPayload = page.gistableText
        let json: [String : Any] = ["description" : self.description, "public" : self.isPublic, "files" : [self.fileName : ["content" : textPayload]]]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            print("failed to convert json")
            return nil
        }
        
        return data
    }
    
}
