// LoginRedirectRecorder

import SwiftUI
import Security
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


/// 只用来记录登录请求是否发生过重定向，重定向本身仍然跟随。
final class LoginRedirectRecorder: NSObject, URLSessionTaskDelegate {
    private(set) var redirected = false

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirected = true
        completionHandler(request)
    }
}
