import SwiftUI

/// Reads the app's model from the environment, falling back to the shared
/// instance. A window restored by macOS after a crash or forced quit can be
/// rebuilt without the `.environment(model)` of its scene, and a plain
/// `@Environment(AppModel.self)` traps ("No Observable object of type
/// AppModel found") in that case. There is only one model, so the fallback
/// is always the right one.
@MainActor
@propertyWrapper
struct AppModelEnvironment: DynamicProperty {
    @Environment(AppModel.self) private var model: AppModel?

    var wrappedValue: AppModel { model ?? .shared }
}
