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

public class HTTPClientEventMonitor: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    
    // MARK: - Private Properties
    
    /// Parent client.
    internal private(set) weak var client: HTTPClientProtocol?
    
    var requests: [HTTPRequestProtocol] {
        queue.sync {
            Array(tasksToRequest.values)
        }
    }
    
    /// Serial queue.
    private var queue = DispatchQueue(label: "com.httpclient.eventmonitor.queue")
    
    /// Map of the session/requests.
    private var tasksToRequest = [URLSessionTask: HTTPRequestProtocol]()
    private var dataTable = [URLSessionTask: HTTPRawData]()

    // MARK: - Initialization
    
    internal init(client: HTTPClientProtocol) {
        self.client = client
    }
    
    // MARK: - Internal Functions
    
    internal func addRequest(_ request: HTTPRequestProtocol, withTask task: URLSessionTask) {
        queue.sync {
            tasksToRequest[task] = request
        }
    }
    
    internal func removeRequest(forTask task: URLSessionTask) {
        queue.sync {
            dataTable.removeValue(forKey: task)
            tasksToRequest.removeValue(forKey: task)
        }
    }
    
    internal func request(forTask task: URLSessionTask) -> (request: HTTPRequestProtocol?, dataURL: HTTPRawData?) {
        queue.sync {
            let data = dataTable[task]
            let request = tasksToRequest[task]
            return (request, data)
        }
    }
    

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print("didBecomeInvalidWithError")
    }
    
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("didReceive")
        
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("urlSessionDidFinishEvents")
        
    }
    // MARK: - URLSessionDownloadTask

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            print("Progress \(downloadTask) \(progress)")
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let fileURL = location.copyFileToDefaultLocation(task: downloadTask) else {
            // copy file from a temporary location to a valid location
            return
        }
        
        queue.sync { dataTable[downloadTask] = .file(fileURL) } // set data
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        didCompleteTask(task, didCompleteWithError: error)
    }
    
    // MARK: - URLSessionDataTask
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.sync { dataTable[dataTask] = .data(data) }
    }
    
    // MARK: - Private Functions
    
    private func didCompleteTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        if let client = self.client as? HTTPClientQueue,
              let operation = client.operationForTask(task) {
            operation.end() // mark the operation as finished
        }
        
        let (request, data) = request(forTask: task)
        guard let request = request else {
            return
        }
        
        // Parse the response and create the object which contains all the datas.
        let rawResponse = (task.response, data, error)
        var response = HTTPRawResponse(request: request, response: rawResponse)
        response.attachURLRequests(original: task.originalRequest, current: task.currentRequest)
        
        didComplete(request: request, response: &response)
        
        removeRequest(forTask: task)
    }
    
    /// Called when request did complete.
    ///
    /// - Parameters:
    ///   - request: request.
    ///   - urlRequest: urlRequest executed.
    ///   - rawData: raw data.
    private func didComplete(request: HTTPRequestProtocol, response: inout HTTPRawResponse) {
        guard let client = self.client else { return }
        
        let validationAction = client.validate(response: response)
        switch validationAction {
        case .failWithError(let error): // Response validation failed with error, set the new error and forward it
            response.error = HTTPError(.invalidResponse, error: error)
            request.receiveHTTPResponse(response, client: client)

        case .retryAfter(let altRequest):
            request.reset(retries: true)
            
            if let queueClient = client as? HTTPClientQueue {
                do {
                    // Create a new operation for this request but link it with a dependency to the alt request
                    // so it will be executed in order (alt -> this).
                    let linkedOperation = try HTTPRequestOperation(task: queueClient.createTask(for: altRequest))
                    let thisOperation = try HTTPRequestOperation(task: queueClient.createTask(for: request))
                    thisOperation.addDependency(linkedOperation)
                    
                    queueClient.addOperations(linkedOperation, thisOperation)
                } catch {
                    response.error = HTTPError(.invalidResponse, error: error)
                    request.receiveHTTPResponse(response, client: client)
                }
            } else {
                // Response validation failed, you can retry but we need to execute another call first.
                client.execute(request: altRequest).rawResponse(in: nil, { altResponse in
                    request.reset(retries: true)
                    client.execute(request: request)
                })
            }
            
        case .retryIfPossible: // Retry if max retries has not be reached
            request.currentRetry += 1
            
            guard request.currentRetry < request.maxRetries else {
                // Maximum number of retry attempts made.
                response.error = HTTPError(.maxRetryAttemptsReached)
                request.receiveHTTPResponse(response, client: client)
                return
            }
            
            // Reset the state and make another attempt
            request.reset(retries: false)
            client.execute(request: request)

        case .passed: // Passed, nothing to do
            request.receiveHTTPResponse(response, client: client)
        }
    }

}
