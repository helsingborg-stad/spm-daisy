import Foundation
import Combine
import SwiftUI
import AuthenticationServices
import AutomatedFetcher
import KeychainAccess

/// Instagram basic display api implementation
/// - Note: more information at https://developers.facebook.com/docs/instagram-basic-display-api/overview
public final class Instagram : NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    public struct InstagramFetchError:Codable,Error {
        public let message:String
        public let type:String
        public let code:Int
        public let fbtraceId:String
    }
    /// Instagram setup config
    public struct Config : Codable,Equatable {
        /// The service api url needed to complete the oauth request
        public let serverURL:String
        /// Callback scheme for the app, don't include ://, path components or anything else. it will result in a crash
        public let callbackScheme:String
        /// The client id for the Instagram/Facebook app
        public let clientId:String
        /// The keychain service name used for storing credentials
        public let keychainServiceName:String
        /// The keychain key used for storing credentials
        public let keychainCredentialsKey:String
        /// Initializes a new config
        /// - Parameters:
        ///   - serverURL: The service api url needed to complete the oauth request
        ///   - callbackScheme: Callback scheme for the app, don't include ://, path components or anything else. it will result in a crash
        ///   - clientId: The client id for the Instagram/Facebook app
        ///   - keychainServiceName: The keychain service name used for storing credentials
        ///   - keychainCredentialsKey: The keychain key used for storing credentials
        public init(serverURL:String, callbackScheme:String, clientId:String, keychainServiceName:String, keychainCredentialsKey:String) {
            self.serverURL = serverURL
            self.callbackScheme = callbackScheme
            self.clientId = clientId
            self.keychainServiceName = keychainServiceName
            self.keychainCredentialsKey = keychainCredentialsKey
        }
    }
    /// Credential used for decoding the instagram api results
    struct TempCredentials : Codable {
        /// Access token
        let accessToken:String
        /// Type of accesstoken, typically "Bearer"
        let tokenType:String
        /// Expires in x seconds
        let expiresIn:Int
    }
    /// Credential used for keychain storage
    struct Credentials: Codable {
        /// Access token
        let accessToken:String
        /// Date of expiration
        let expires:Date
        
        /// Store credentials in keychain
        /// - Parameters:
        ///   - keychain: the kechain to use
        ///   - key: the key used for storage
        func save(in keychain:Keychain, with key:String) {
            let encoder = JSONEncoder()
            do {
                keychain[data: key] = try encoder.encode(self)
            } catch {
                debugPrint(error)
            }
        }
        /// Delete credetials from keychain
        /// - Parameters:
        ///   - keychain: the keychain to use
        ///   - key: the key used for deletion
        static func delete(from keychain:Keychain, with key:String) {
            keychain[data: key] = nil
        }
        /// Load credentials from keychain
        /// - Parameters:
        ///   - keychain: keychain to use
        ///   - key: key used for loading
        /// - Returns: stored credentials
        static func load(from keychain:Keychain, with key:String) -> Credentials? {
            guard let data = keychain[data: key] else {
                return nil
            }
            let decoder = JSONDecoder()
            do {
                let credentials = try decoder.decode(Credentials.self, from: data)
                if credentials.expires < Date() {
                    delete(from: keychain, with: key)
                    return nil
                }
                return credentials
            } catch {
                debugPrint(error)
            }
            return nil
        }
    }
    /// Instagram media object
    public struct Media: Codable, Equatable,Identifiable {
        /// Media type
        public enum MediaType: String, Codable, Equatable {
            /// Media type IMAGE
            case image = "IMAGE"
            /// Media type VIDEO
            case video = "VIDEO"
            /// Media type CAROUSEL_ALBUM
            case album = "CAROUSEL_ALBUM"
        }
        /// Media id
        public let id:String
        /// Media caption
        public var caption:String?
        /// Media url
        public let mediaUrl:URL
        /// Media thumbnail url
        public let thumbnailUrl:URL?
        /// Timestamp, or date of publication
        public let timestamp:Date
        /// Type of media
        public let mediaType:MediaType
        /// Children (mediatype == .album only)
        public var children:[Media]
        /// Init from decoder
        /// - Parameter decoder: decoder
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.caption = try? values.decode(String.self, forKey: .caption)
            self.mediaUrl = try values.decode(URL.self, forKey: .mediaUrl)
            self.thumbnailUrl = try? values.decode(URL.self, forKey: .thumbnailUrl)
            self.timestamp = try values.decode(Date.self, forKey: .timestamp)
            self.id = try values.decode(String.self, forKey: .id)
            self.mediaType = try values.decode(MediaType.self, forKey: .mediaType)
            self.children = (try? values.decode([Media].self, forKey: .children))  ?? []
        }
        /// Initializes a new Media object, only used for creating Preview Data
        /// - Parameters:
        ///   - mediaUrl: the url of the media
        ///   - mediaType: the type of media
        init(mediaUrl:URL,mediaType:MediaType, caption:String = "Preview image comment") {
            self.id = UUID().uuidString
            self.mediaUrl = mediaUrl
            self.mediaType = mediaType
            self.children = []
            self.timestamp = Date()
            self.caption = caption
            self.thumbnailUrl = nil
        }
    }
    /// Media list result, used for decoding api results
    public struct MediaListResult: Codable, Equatable {
        /// Media result paging
        public struct Paging: Codable, Equatable {
            public struct Cursors: Codable, Equatable {
                public let after:String
                public let before:String
            }
            public let cursors:Cursors
            public let previous:URL?
            public let next:URL?
            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                cursors = try values.decode(Cursors.self, forKey: .cursors)
                previous = try? values.decode(URL.self, forKey: .previous)
                next = try? values.decode(URL.self, forKey: .next)
            }
        }
        /// The actual media result
        public var data:[Media]
        /// List paging, if any
        public var paging:Paging?
    }
    /// Instagram errors
    public enum InstagramError : Error {
        /// Missing or invalid authorization code returned from instagram authorization request
        case missingAuthorizationCode
        /// No credentials available when calling instagram api
        case missingCredentials
        /// Configuration missing
        case missingConfig
        /// Corrupt authorization url
        case unableToProcessAuthorizationURL
        /// Invalid authorization url
        case invalidAuthorizationURL
        /// Used in weak self closures
        case contextDied
    }
    /// Configuration
    /// Automatically loades the credentials from keychain and fetches result from server if automatic fetches are enabled.
    /// If the the config changes all resutls will be removed from memory.
    public var config:Config? {
        didSet {
            if config == oldValue {
                return
            }
            setupKeychainAndLoadCredentials()
            if oldValue != nil {
                // remove images when configuration changes
                dataSubject.send(nil)
            } else if fetchAutomatically {
                fetch()
            }
        }
    }
    /// Keychain used for storing credentials
    private var keychain:Keychain?
    /// Authentication session object
    private var session:ASWebAuthenticationSession?
    /// Cancellable subscriptions
    private var cancellables = Set<AnyCancellable>()
    /// Cancellable subscriptions
    private var automatedfFetcherCancellable:AnyCancellable?
    /// Current state, used when requesting an accesstoken
    private var state = UUID().uuidString
    /// Internal data subject used when publishing new media
    internal var dataSubject = CurrentValueSubject<[Media]?,Never>(nil)
    /// Decoder used for decoding data from instagram api
    private let decoder = JSONDecoder()
    /// The automated fetcher used to fetch new content periodically
    private let automatedFetcher:AutomatedFetcher<[Media]?>
    /// Generates a new state code and returns an authorization url. Call only once per authorization request
    private var authorizeUrl:URL? {
        state = UUID().uuidString
        guard let config = config else {
            return nil
        }
        return URL(string: "https://api.instagram.com/oauth/authorize?client_id=\(config.clientId)&redirect_uri=\(config.serverURL)/authenticated&scope=user_profile,user_media&response_type=code&state=\(state)")!
    }
    /// The current credentials
    /// Turns off the automatic fetcher if presented with a nil value, automatically fetches content if not nil.
    /// Stores credentials automatically in keychain when presented with a value.
    private var credentials:Credentials? {
        didSet {
            if let credentials = credentials {
                isAuthenticated = true
                if let keychain = keychain, let key = config?.keychainCredentialsKey {
                    credentials.save(in: keychain, with: key)
                }
                automatedFetcher.isOn = fetchAutomatically
                if fetchAutomatically {
                    fetch()
                }
            } else {
                cancellables.removeAll()
                automatedFetcher.isOn = false
                isAuthenticated = false
                if let keychain = keychain, let key = config?.keychainCredentialsKey {
                    Credentials.delete(from: keychain, with: key)
                }
                dataSubject.send(nil)
            }
        }
    }
    /// The latest fetched values.
    /// If no values have been retrieved the subscriber will recieve nil
    public let latest:AnyPublisher<[Media]?,Never>
    /// Indicates whether or not the instance is in preview mode
    @Published public private(set) var previewData:Bool = false
    /// Indicates whether or not the user is authenticated
    @Published public internal(set) var isAuthenticated = false
    /// Indicates whether or not the instance should fetch content automatically.
    @Published public var fetchAutomatically = true {
        didSet { automatedFetcher.isOn = fetchAutomatically }
    }
    
    /// Instantiates a new Instagram object
    /// - Parameters:
    ///   - config: the confiugration
    ///   - fetchAutomatically: Indicates whether or not the instance should fetch content automatically.
    ///   - fetchInterval: The interval of automatic fetches, default value `60 * 30` seconds
    ///   - previewData: Indicates whether or not the instance is in preview mode
    public init(config:Config?, fetchAutomatically:Bool = true, fetchInterval:TimeInterval = 60 * 30, previewData:Bool = false) {
        self.previewData = previewData
        self.config = config
        self.fetchAutomatically = fetchAutomatically
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        decoder.dateDecodingStrategy = .formatted(formatter)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.latest = dataSubject.eraseToAnyPublisher()
        self.automatedFetcher = AutomatedFetcher<[Media]?>.init(dataSubject, isOn: fetchAutomatically, timeInterval: fetchInterval)
        super.init()
        automatedfFetcherCancellable = self.automatedFetcher.triggered.sink { [weak self] in
            self?.fetch()
        }
        
        if fetchAutomatically {
            fetch()
        }
        self.setupKeychainAndLoadCredentials()
        self.isAuthenticated = previewData || credentials != nil
    }
    
    /// Setup the keychain using the configuration paramters. Once setup credentials are loaded into memory in available
    /// In case the config is missing the credentials and kechain will be set to nil
    private func setupKeychainAndLoadCredentials() {
        if let config = config {
            keychain = Keychain(service: config.keychainServiceName).accessibility(.whenUnlockedThisDeviceOnly)
            if let keychain = keychain {
                credentials = Credentials.load(from: keychain, with: config.keychainCredentialsKey)
            } else {
                credentials = nil
            }
        } else {
            keychain = nil
            credentials = nil
        }
    }
    
    /// Fetch media from the server
    /// - Parameter force: force a fetch, regardless of the automated fetcher status. The only time the force does not trigger is when the user is unauthenticated or the config is missing.
    public func fetch(force:Bool = false) {
        if !isAuthenticated { return }
        if previewData {
            dataSubject.send(Self.previewData)
            return
        }
        if config == nil { return }
        if force == false && automatedFetcher.shouldFetch == false && dataSubject.value != nil {
            return
        }
        automatedFetcher.started()
        var p:AnyCancellable?
        p = mediaPublisher().sink(receiveCompletion: { [weak self] completion in
            if case .failure(let error) = completion {
                debugPrint(error)
            }
            self?.automatedFetcher.failed()
        }, receiveValue: { [weak self] media in
            guard let this = self else {
                return
            }
            this.dataSubject.send(media)
            if let p = p {
                this.cancellables.remove(p)
            }
            self?.automatedFetcher.completed()
        })
        if let p = p {
            self.cancellables.insert(p)
        }
    }
    
    /// Required function used by ASWebAuthenticationSession
    /// - Parameter session: the ASWebAuthenticationSession
    /// - Returns: a ASPresentationAnchor
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
    
    /// Set credentials to nil, removes data from memory and publushes nil to the subscribers. See instance credentails implementaion for further details.
    public func logout() {
        credentials = nil
    }
    
    /// Start authorization flow
    /// - Returns: completion publisher
    public func authorize() -> AnyPublisher<Void,Error> {
        guard let config = config else {
            return Fail(error: InstagramError.missingConfig).eraseToAnyPublisher()
        }
        guard let authorizeUrl = authorizeUrl else {
            return Fail(error: InstagramError.invalidAuthorizationURL).eraseToAnyPublisher()
        }
        let sub = PassthroughSubject<Void,Error>()
        self.session = ASWebAuthenticationSession(url: authorizeUrl, callbackURLScheme: config.callbackScheme) { [weak self ](url, err) in
            guard let this = self else {
                sub.send(completion: .failure(InstagramError.contextDied))
                return
            }
            if let err = err {
                sub.send(completion: .failure(err))
                return
            }
            guard let url = url,let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                sub.send(completion: .failure(InstagramError.unableToProcessAuthorizationURL))
                return
            }
            guard let code = components.queryItems?.first(where: { item in item.name == "code"})?.value else {
                sub.send(completion: .failure(InstagramError.missingAuthorizationCode))
                return
            }
            this.getAccessToken(code: code).sink { err in
                sub.send(completion: err)
            } receiveValue: { c in
                this.credentials = c
                sub.send()
            }.store(in: &this.cancellables)
        }
        session?.presentationContextProvider = self
        session?.start()
        return sub.eraseToAnyPublisher()
    }
    
    /// Retrieve long lived access token
    /// - Parameter code: short lived code retrieved from the ASWebAuthenticationSession
    /// - Returns: completion publisher
    private func getAccessToken(code:String) -> AnyPublisher<Credentials,Error> {
        guard let config = config else {
            return Fail(error: InstagramError.missingConfig).eraseToAnyPublisher()
        }
        guard let url = URL(string: "\(config.serverURL)/accessToken/\(code)") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        return URLSession.shared.dataTaskPublisher(for:URLRequest(url: url))
            .tryMap() { $0.data }
            .decode(type: TempCredentials.self, decoder: decoder)
            .map { Credentials(accessToken: $0.accessToken, expires: Date().addingTimeInterval(TimeInterval($0.expiresIn))) }
            .eraseToAnyPublisher()
    }
    
    /// Retrieve media from instagram API
    /// - Returns: completion publisher
    private func mediaPublisher() -> AnyPublisher<[Media],Error> {
        func mediaPublisher(media:Media) -> AnyPublisher<Media,Error> {
            guard media.mediaType == .album else {
                return Result.success(media).publisher.eraseToAnyPublisher()
            }
            var media = media
            guard let credentials = credentials else {
                return Fail(error: InstagramError.missingCredentials).eraseToAnyPublisher()
            }
            guard let url = URL(string: "https://graph.instagram.com/\(media.id)/children?fields=media_url,thumbnail_url,timestamp,media_type&access_token=\(credentials.accessToken)") else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            return URLSession.shared.dataTaskPublisher(for: URLRequest(url: url))
                .tryMap() { element -> Data in
                    guard let httpResponse = element.response as? HTTPURLResponse, httpResponse.statusCode < 400 else {
                        throw (try? JSONDecoder().decode(InstagramFetchError.self, from: element.data)) ?? URLError(.badServerResponse)
                    }
                    return element.data
                }
                .decode(type: MediaListResult.self, decoder: decoder)
                .map { $0.data}
                .map {
                    media.children = $0
                    for (i,_) in media.children.enumerated() {
                        media.children[i].caption = media.caption
                    }
                    return media
                }
                .eraseToAnyPublisher()
        }
        guard let credentials = credentials else {
            return Fail(error: InstagramError.missingCredentials).eraseToAnyPublisher()
        }
        guard let url = URL(string: "https://graph.instagram.com/me/media?fields=media_url,thumbnail_url,timestamp,media_type,caption&access_token=\(credentials.accessToken)") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        return URLSession.shared.dataTaskPublisher(for: URLRequest(url: url))
            .tryMap() { element -> Data in
                guard let httpResponse = element.response as? HTTPURLResponse, httpResponse.statusCode < 400 else {
                    throw (try? JSONDecoder().decode(InstagramFetchError.self, from: element.data)) ?? URLError(.badServerResponse)
                }
                return element.data
            }
            .decode(type: MediaListResult.self, decoder: decoder)
            .map { $0.data}
            .flatMap { Publishers.MergeMany($0.map { mediaPublisher(media: $0) }).collect() }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Instance used for preview scenarios
    static public let previewInstance:Instagram = Instagram(config: Config(serverURL: "", callbackScheme: "", clientId: "", keychainServiceName: "myapp", keychainCredentialsKey: "mycredentials"), fetchAutomatically: true, previewData: true)
    /// Data used for preview senarios
    static public let previewData:[Media] = [
        .init(mediaUrl: URL(string: "https://images.unsplash.com/photo-1624374984719-0d146ea066e1?ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&ixlib=rb-1.2.1&auto=format&fit=crop&w=750&q=80")!, mediaType: .image),
        .init(mediaUrl: URL(string: "https://images.unsplash.com/photo-1628547274104-fca69938d030?ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80")!, mediaType: .image)
    ]
}
