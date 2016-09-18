import Foundation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let gist: Gist = Gist(description: "Test Description", fileName: "PostGist.txt", configuration: .anonymous)

gist.post(page: PlaygroundPage.current) { (result) in
    switch result {
    case .error(let error):
        print("error: \(error)")
        break
    case .result(let url):
        print("url of gist: \(url)")
        break
    }
    
    PlaygroundPage.current.complete(withResult: result)
}



