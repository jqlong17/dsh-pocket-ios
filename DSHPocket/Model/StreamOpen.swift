// StreamOpen

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


struct StreamOpen: Encodable {
    let type: String
    let streamId: String
    let endpoint: String
    let payload: [String: AnyEncodable]

    init(type: String, streamId: String, endpoint: String, payload: [String: Any]) {
        self.type = type
        self.streamId = streamId
        self.endpoint = endpoint
        self.payload = payload.mapValues(AnyEncodable.init)
    }
}

struct AnyEncodable: Encodable {
    private let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = value as? String { try container.encode(value) }
        else if let value = value as? Int { try container.encode(value) }
        else if let value = value as? Bool { try container.encode(value) }
        else if let value = value as? [String: Any] { try container.encode(value.mapValues(AnyEncodable.init)) }
        else if let value = value as? [Any] { try container.encode(value.map(AnyEncodable.init)) }
        else { try container.encodeNil() }
    }
}
