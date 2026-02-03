import Foundation
import CryptoKit

// MARK: - Enums
enum DivoomCategory: Int, CaseIterable, Identifiable {
    case recommend = 18
    case character = 3
    case emoji = 4
    case daily = 5
    case nature = 6
    case symbol = 7
    case pattern = 8
    case creative = 9
    case photo = 12
    case top = 14
    case gadget = 15
    case business = 16
    case festival = 17
    case plant = 31
    case animal = 32
    case person = 33
    case food = 35

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .recommend: return "Recommended"
        case .character: return "Character"
        case .emoji: return "Emoji"
        case .daily: return "Daily"
        case .nature: return "Nature"
        case .symbol: return "Symbol"
        case .pattern: return "Pattern"
        case .creative: return "Creative"
        case .photo: return "Photo"
        case .top: return "Top"
        case .gadget: return "Gadget"
        case .business: return "Business"
        case .festival: return "Festival"
        case .plant: return "Plant"
        case .animal: return "Animal"
        case .person: return "Person"
        case .food: return "Food"
        }
    }
}

// MARK: - Models
struct DivoomUser: Codable {
    let userId: Int
    let token: Int

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case token = "Token"
    }
}

struct DivoomGalleryResponse: Codable {
    let returnCode: Int
    let fileList: [DivoomFile]

    enum CodingKeys: String, CodingKey {
        case returnCode = "ReturnCode"
        case fileList = "FileList"
    }
}

struct DivoomFile: Codable, Identifiable {
    let fileId: String
    let fileName: String
    let fileUrl: String
    let likeCount: Int
    let shareCount: Int
    let watchCount: Int
    let category: Int

    var id: String { fileId }

    var constructedUrl: URL? {
        if !fileUrl.isEmpty, let url = URL(string: fileUrl) {
            // Force HTTPS if possible or assume it's valid.
            // Most Divoom URLs are f.divoom-gz.com which supports HTTPS.
            if url.scheme == "http" {
                 var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                 components?.scheme = "https"
                 return components?.url ?? url
            }
            return url
        }
        return URL(string: "https://f.divoom-gz.com/" + fileId)
    }

    enum CodingKeys: String, CodingKey {
        case fileId = "FileId"
        case fileName = "FileName"
        case fileUrl = "FileURL"
        case likeCount = "LikeCnt"
        case shareCount = "ShareCnt"
        case watchCount = "WatchCnt"
        case category = "Classify"
    }
}

struct DivoomLoginResponse: Codable {
    let returnCode: Int?
    let message: String?
    let userId: Int?
    let token: Int?

    enum CodingKeys: String, CodingKey {
        case returnCode = "ReturnCode"
        case message = "Message"
        case userId = "UserId"
        case token = "Token"
    }
}

// MARK: - Client
class DivoomClient: ObservableObject {
    static let shared = DivoomClient()

    @Published var currentUser: DivoomUser?
    @Published var isLoggedIn = false

    private let baseUrl = "https://app.divoom-gz.com"
    private var session = URLSession.shared

    // Derived from apixoo python library
    private let userAgent = "Aurabox/3.1.10 (iPad; iOS 14.8; Scale/2.00)"

    init() {
        // Look for saved credentials or token if implemented later
    }

    // MARK: - Auth
    func login(email: String, password: String) async throws -> Bool {
        let endpoint = "/UserLogin"
        let md5Password = MD5(string: password)

        let payload: [String: Any] = [
            "Email": email,
            "Password": md5Password
        ]

        let result: DivoomLoginResponse = try await postRequest(endpoint: endpoint, payload: payload, authenticated: false)

        // Success if we have UserId and Token
        if let uid = result.userId, let tkn = result.token {
            let user = DivoomUser(userId: uid, token: tkn)
            await MainActor.run {
                self.currentUser = user
                self.isLoggedIn = true
            }
            return true
        } else {
             // If we have a return code, use it, otherwise generic error
            let code = result.returnCode ?? -1
            throw NSError(domain: "DivoomClient", code: code, userInfo: [NSLocalizedDescriptionKey: result.message ?? "Login failed (No UserID/Token received)"])
        }
    }

    // MARK: - Gallery
    func fetchFiles(category: DivoomCategory, page: Int = 1, perPage: Int = 12) async throws -> [DivoomFile] {
        guard isLoggedIn, let user = currentUser else {
            throw NSError(domain: "DivoomClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        let endpoint = "/GetCategoryFileListV2"
        let startNum = ((page - 1) * perPage) + 1
        let endNum = startNum + perPage - 1

        let payload: [String: Any] = [
            "StartNum": startNum,
            "EndNum": endNum,
            "Classify": category.rawValue,
            "FileSize": 15, // ALL dimensions
            "FileType": 0, // 0=Picture? apixoo logic seems complex here but 5=ALL is used in example.
            // Re-checking apixoo const.py: GalleryType.ALL = 5.
            // Let's stick to what apixoo example used or defaults.
            // Example: dimension=GalleryDimension.W64H64 (4), file_type=GalleryType.ALL (5)
            // But let's verify what we want. We generally want Animations or Pictures or Multi-Animation.
            // Let's use 5 (ALL) for FileType.
            "FileSort": 1, // Most Liked
            "Version": 12,
            "RefreshIndex": 0
        ]

        // Note: authenticated request typically needs Token/UserID injected

        let response: DivoomGalleryResponse = try await postRequest(endpoint: endpoint, payload: payload, authenticated: true)
        return response.fileList
    }

    // MARK: - Helpers
    private func postRequest<T: Codable>(endpoint: String, payload: [String: Any], authenticated: Bool) async throws -> T {
        guard let url = URL(string: baseUrl + endpoint) else {
            throw NSError(domain: "DivoomClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var finalPayload = payload
        if authenticated, let user = currentUser {
            finalPayload["Token"] = user.token
            finalPayload["UserId"] = user.userId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: finalPayload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "DivoomClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid Response"])
        }

        print("[DivoomClient] Status: \(httpResponse.statusCode)")
        let responseString = String(data: data, encoding: .utf8) ?? "[Binary Data]"
        // print("[DivoomClient] Response from \(endpoint): \(responseString)")

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "DivoomClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error \(httpResponse.statusCode): \(responseString)"])
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
             // If decoding fails, include the raw response in the error description so the user sees it in the UI alert
            throw NSError(domain: "DivoomClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Decoding Error: \(error.localizedDescription). Raw: \(responseString)"])
        }
    }

    private func MD5(string: String) -> String {
        let digest = Insecure.MD5.hash(data: string.data(using: .utf8) ?? Data())
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
}
