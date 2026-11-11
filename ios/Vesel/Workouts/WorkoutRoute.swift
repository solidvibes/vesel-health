import SwiftUI

/// One workout's page, named by the Loop's session folder ("20261103/071000").
struct WorkoutRoute: Hashable {
    let session: String
}

/// Pushes a workout's page on the stack the screen sits in: `@Environment(\.openWorkout) var openWorkout`, then `openWorkout(WorkoutRoute(session:))`.
struct OpenWorkout {
    let action: @MainActor (WorkoutRoute) -> Void

    @MainActor func callAsFunction(_ route: WorkoutRoute) { action(route) }
}

extension EnvironmentValues {
    @Entry var openWorkout = OpenWorkout(action: { _ in })
}

extension View {
    /// Registers the Workout page on this stack.
    func workoutDestinations(environment: AppEnvironment) -> some View {
        navigationDestination(for: WorkoutRoute.self) { WorkoutPage(route: $0, environment: environment) }
    }
}
