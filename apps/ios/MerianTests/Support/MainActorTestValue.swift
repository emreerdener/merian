/// Mutable fixture state shared by callbacks that are isolated to MainActor.
@MainActor
final class MainActorTestValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
