struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let message: String
    let data: Value
}

struct ServiceErrorEnvelope: Decodable, Sendable {
    let code: Int?
    let message: String?
}
