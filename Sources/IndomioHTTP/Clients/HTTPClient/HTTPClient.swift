//
//  IndomioNetwork
//
//  Created by the Mobile Team @ ImmobiliareLabs
//  Email: mobile@immobiliare.it
//  Web: http://labs.immobiliare.it
//
//  Copyright ©2021 Immobiliare.it SpA. All rights reserved.
//  Licensed under MIT License.
//

import Foundation

public class HTTPClient: NSObject, HTTPClientProtocol {
    
    // MARK: - Public Properties
    
    /// Base URL.
    public var baseURL: String
    
    /// Service's URLSession instance to use.
    public var session: URLSession!
    
    /// Headers which are part of each request made using the client.
    public var headers = HTTPHeaders.default
    
    /// Security settings.
    public var security: HTTPSecurityProtocol?
    
    /// Event monitor.
    public var eventMonitor: HTTPClientEventMonitor!
    
    /// Timeout interval for requests. Defaults to `60` seconds.
    /// Requests may override this behaviour.
    public var timeout: TimeInterval = 60
    
    /// Validators for response. Values are executed in order.
    public var validators: [HTTPResponseValidator] = [
        HTTPDefaultValidator() // standard validator for http responses
    ]
        
    /// The cache policy for the request. Defaults to `.useProtocolCachePolicy`.
    /// Requests may override this behaviour.
    public var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    
    // MARK: - Initialization

    
    /// Initialize a new HTTP client with given `URLSessionConfiguration` instance.
    ///
    ///
    /// - Parameters:
    ///   - baseURL: base URL.
    ///   - configuration: `URLSession` configuration. The available types are `default`,
    ///                    `ephemeral` and `background`, if you don't provide any or don't have
    ///                     special needs then Default will be used.
    ///
    ///                     - `default`: uses a persistent disk-based cache (except when the result is downloaded to a file)
    ///                     and stores credentials in the user’s keychain.
    ///                     It also stores cookies (by default) in the same shared cookie store as the
    ///                     NSURLConnection and NSURLDownload classes.
    ///                     - `ephemeral`: similar to a default session configuration object except that
    ///                     the corresponding session object does not store caches,
    ///                     credential stores, or any session-related data to disk. Instead,
    ///                     session-related data is stored in RAM.
    ///                     - `background`: suitable for transferring data files while the app runs in the background.
    ///                     A session configured with this object hands control of the transfers over to the system,
    ///                     which handles the transfers in a separate process.
    ///                     In iOS, this configuration makes it possible for transfers to continue even when
    ///                     the app itself is suspended or terminated.
    public init(baseURL: String = "", configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        super.init()
        
        self.eventMonitor = HTTPClientEventMonitor(client: self)
        self.session = URLSession(configuration: configuration, delegate: eventMonitor, delegateQueue: nil)
    }
    
    // MARK: - Public Functions
    
    /// Execute the request immediately.
    ///
    /// - Parameter request: request.
    /// - Returns: the request itself
    @discardableResult
    public func execute(request: HTTPRequestProtocol) -> HTTPRequestProtocol {
        do {
            let task = try createTask(for: request) // create the URLRequest and associated URLSessionTask to execute
            eventMonitor.addRequest(request, withTask: task) // add to monitor the response
            task.resume() // start it immediately
        } catch {
            // Something went wrong building request, avoid adding operation and dispatch the message
            let response = HTTPRawResponse(error: .failedBuildingURLRequest, forRequest: request)
            request.receiveHTTPResponse(response, client: self)
        }
        
        return request
    }
    
}