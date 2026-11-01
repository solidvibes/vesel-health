/// How a number was worked out: the method, its version, what went in, and a plain sentence.
public struct Explanation: Sendable, Equatable, Codable {
    public var method: String
    public var version: Int
    public var inputs: [Input]
    public var text: String

    public struct Input: Sendable, Equatable, Codable {
        public var name: String
        public var value: Double
        public var unit: String

        public init(name: String, value: Double, unit: String) {
            self.name = name
            self.value = value
            self.unit = unit
        }
    }

    public init(method: String, version: Int, inputs: [Input], text: String) {
        self.method = method
        self.version = version
        self.inputs = inputs
        self.text = text
    }
}
