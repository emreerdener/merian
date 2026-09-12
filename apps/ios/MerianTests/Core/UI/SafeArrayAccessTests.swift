@testable import Merian
import Testing

@Suite("Safe Array Access")
struct SafeArrayAccessTests {
    @Test func returnsElementsOnlyForValidIndices() {
        let values = ["first", "second"]

        #expect(values[safe: 0] == "first")
        #expect(values[safe: 1] == "second")
        #expect(values[safe: -1] == nil)
        #expect(values[safe: 2] == nil)
    }
}
