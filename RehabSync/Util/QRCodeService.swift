import CoreImage
import CryptoKit
import Foundation
import UIKit

// MARK: - QRCodeService

class QRCodeService {

    // MARK: - Types

    struct VerifyResult {
        let valid: Bool
        let data: [String: Any]?
        let expiry: String?
        let reason: String?
    }

    enum QRCodeError: Error, LocalizedError {
        case serializationFailed
        case invalidJSON
        case missingField(String)
        case signatureInvalid
        case expired(String)
        case invalidExpiry

        var errorDescription: String? {
            switch self {
            case .serializationFailed:    return "JSON 序列化失敗"
            case .invalidJSON:            return "QR Code 格式錯誤，無法解析 JSON"
            case .missingField(let f):    return "缺少必要欄位：\(f)"
            case .signatureInvalid:       return "簽章驗證失敗，QR Code 可能被竄改"
            case .expired(let e):         return "QR Code 已過期（expiry: \(e))"
            case .invalidExpiry:          return "expiry 時間格式錯誤"
            }
        }
    }

    // MARK: - Properties

    private let secret: String
    private let expiryMinutes: Int = 10

    init() {
        self.secret = ProcessInfo.processInfo.environment["SECRET_KEY"]
            ?? "bd31e10e3121be9b9229589e076bc3199f1529a00badd75a91192694fc8dfcbf"
    }

    // MARK: - Signature

    func generateSig(payload: [String: Any]) throws -> String {
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let payloadStr = String(data: jsonData, encoding: .utf8) else {
            throw QRCodeError.serializationFailed
        }
        print("[QR] generateSig payloadStr: \(payloadStr)")
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payloadStr.utf8), using: key)
        let result = Data(mac).base64EncodedString()
        print("[QR] generateSig result: \(result)")
        return result
    }

    func verifySig(payload: [String: Any], sig: String) throws -> Bool {
        let expectedSig = try generateSig(payload: payload)
        print("[QR] verifySig expected: \(expectedSig)")
        print("[QR] verifySig received: \(sig)")
        guard let expectedData = Data(base64Encoded: expectedSig),
              let sigData    = Data(base64Encoded: sig) else { return false }
        return constantTimeEqual(expectedData, sigData)
    }

    // MARK: - Generate

    func generateQRCode(data: [String: Any]) throws -> (image: UIImage?, payload: [String: Any]) {
        let formatter = ISO8601DateFormatter()
        let expiry = formatter.string(from: Date().addingTimeInterval(TimeInterval(expiryMinutes * 60)))

        let payload: [String: Any] = ["data": data, "expiry": expiry]
        let sig = try generateSig(payload: payload)
        var payloadWithSig = payload
        payloadWithSig["sig"] = sig

        let qrData = try JSONSerialization.data(withJSONObject: payloadWithSig, options: [.sortedKeys])
        let qrContent = String(data: qrData, encoding: .utf8) ?? ""

        return (makeQRImage(from: qrContent), payloadWithSig)
    }

    // MARK: - Verify

    func verifyQRCode(qrRaw: String) -> VerifyResult {
        print("[QR] raw input: \(qrRaw)")
        guard let rawData = qrRaw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            return .init(valid: false, data: nil, expiry: nil, reason: "QR Code 格式錯誤，無法解析 JSON")
        }

        for field in ["data", "expiry", "sig"] {
            if json[field] == nil {
                return .init(valid: false, data: nil, expiry: nil, reason: "缺少必要欄位：\(field)")
            }
        }

        guard let innerData = json["data"] as? [String: Any],
              let expiry    = json["expiry"] as? String,
              let sig       = json["sig"] as? String else {
            return .init(valid: false, data: nil, expiry: nil, reason: "欄位格式錯誤")
        }

        let payload: [String: Any] = ["data": innerData, "expiry": expiry]
        guard let isValid = try? verifySig(payload: payload, sig: sig), isValid else {
            return .init(valid: false, data: nil, expiry: nil, reason: "簽章驗證失敗，QR Code 可能被竄改")
        }

        guard let expiryDate = parseISO8601(expiry) else {
            return .init(valid: false, data: nil, expiry: nil, reason: "expiry 時間格式錯誤")
        }

        if Date() > expiryDate {
            return .init(valid: false, data: nil, expiry: expiry, reason: "QR Code 已過期（expiry: \(expiry))")
        }

        return .init(valid: true, data: innerData, expiry: expiry, reason: nil)
    }

    // MARK: - Private Helpers

    private func makeQRImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) { result |= x ^ y }
        return result == 0
    }
}
