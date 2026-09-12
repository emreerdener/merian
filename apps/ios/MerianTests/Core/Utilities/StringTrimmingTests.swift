@testable import Merian
import Testing

@Suite("String Trimming")
struct StringTrimmingTests {
    @Test func returnsTrimmedContentOrNil() {
        #expect("  habitat\n".trimmedNonEmptyValue == "habitat")
        #expect(" \n\t ".trimmedNonEmptyValue == nil)
        #expect("".trimmedNonEmptyValue == nil)
    }
}
