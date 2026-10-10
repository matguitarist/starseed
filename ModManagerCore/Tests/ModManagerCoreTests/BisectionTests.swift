import Foundation
import Testing
@testable import ModManagerCore

@Suite struct BisectionTests {
    /// Content Patcher and SpaceCore are frameworks; SVE needs both.
    static let units: [Bisection.Unit] = [
        .init(id: "cp", name: "Content Patcher", modKeys: ["ContentPatcher"], requires: []),
        .init(id: "spacecore", name: "SpaceCore", modKeys: ["SpaceCore"], requires: []),
        .init(id: "sve", name: "Stardew Valley Expanded", modKeys: ["[CP] SVE", "SVE Code"], requires: ["cp", "spacecore"]),
        .init(id: "automate", name: "Automate", modKeys: ["Automate"], requires: []),
        .init(id: "grass", name: "More Grass", modKeys: ["More Grass"], requires: ["cp"]),
        .init(id: "farm", name: "Farm Cave", modKeys: ["Farm Cave"], requires: ["cp"]),
        .init(id: "lookup", name: "Lookup Anything", modKeys: ["LookupAnything"], requires: []),
    ]

    /// Plays the whole search with a pretend culprit; returns it and the test count.
    func find(_ culprit: String) -> (found: String?, tests: Int) {
        var bisection = Bisection(units: Self.units)
        while !bisection.isFinished {
            let enabled = bisection.startNextTest()
            // A test always includes what its units need.
            for id in enabled {
                for required in bisection.unit(id)!.requires { #expect(enabled.contains(required)) }
            }
            bisection.record(problemHappened: enabled.contains(culprit))
            if bisection.round > 20 { Issue.record("no progress"); break }
        }
        return (bisection.culprit?.id, bisection.round)
    }

    @Test(arguments: ["cp", "spacecore", "sve", "automate", "grass", "farm", "lookup"])
    func findsAnyCulpritInFewTests(culprit: String) {
        let result = find(culprit)
        #expect(result.found == culprit)
        #expect(result.tests <= 3)  // 7 units: ceil(log2 7)
    }

    @Test func ordersRequirementsFirst() {
        let order = Bisection.ordered(Self.units).map(\.id)
        #expect(order.firstIndex(of: "cp")! < order.firstIndex(of: "sve")!)
        #expect(order.firstIndex(of: "spacecore")! < order.firstIndex(of: "sve")!)
    }

    @Test func isInconclusiveWhenEveryTestIsFine() {
        var bisection = Bisection(units: Self.units)
        while !bisection.isFinished {
            bisection.startNextTest()
            bisection.record(problemHappened: false)
        }
        #expect(bisection.isInconclusive)
    }

    @Test func survivesARoundTripThroughJSON() throws {
        var bisection = Bisection(units: Self.units)
        bisection.startNextTest()
        let copy = try JSONDecoder().decode(Bisection.self, from: JSONEncoder().encode(bisection))
        #expect(copy == bisection)
    }
}
