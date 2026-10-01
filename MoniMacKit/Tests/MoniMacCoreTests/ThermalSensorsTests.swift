import Testing
@testable import MoniMacCore

struct ThermalSensorsTests {
    @Test(arguments: [
        ("Tp01", SensorGroup.performanceCores), ("Tp0f", .performanceCores),
        ("Te05", .efficiencyCores), ("Tg0D", .gpu),
        ("Tm0P", .memory), ("TH0x", .ssd), ("TB0T", .battery), ("TB2T", .battery),
        ("Ts0P", .palmRest), ("Ts1P", .palmRest), ("TW0P", .wireless), ("TA0P", .ambient),
        ("NAND CH0 temp", .ssd), ("gas gauge battery", .battery), ("PMU tdie3", .socDie), ("PMU2 tdie10", .socDie),
    ])
    func namesMapToGroups(name: String, group: SensorGroup) {
        #expect(SensorGroup.of(sensorNamed: name) == group)
    }

    /// Keys whose location isn't documented stay unnamed rather than guessed.
    @Test(arguments: ["TaLR", "TPD0", "TRD3", "Ts0S", "TCMz", "TVD0", "Tz11", "PMU tdev1", "PMU tcal", "als-temp", "Tp", "Tp012"])
    func unknownNamesStayUnnamed(name: String) {
        #expect(SensorGroup.of(sensorNamed: name) == nil)
    }

    @Test func groupsAverageTheirSensors() {
        let groups = ThermalGroups([
            ThermalSensor(name: "Tp01", celsius: 70), ThermalSensor(name: "Tp05", celsius: 62),
            ThermalSensor(name: "Te05", celsius: 52),
            ThermalSensor(name: "Tg0D", celsius: 54),
        ])

        #expect(groups.average(.performanceCores) == 66)
        #expect(groups.average(.efficiencyCores) == 52)
        #expect(groups.average(.gpu) == 54)
        #expect(groups.average(.ssd) == nil)
        // The CPU averages every core sensor, so it leans towards the kind with more sensors.
        #expect(groups.cpu == 184.0 / 3)
        #expect(groups.hottest == 66)
    }

    /// The hardware reports idle or absent sensors as 0, 6.2, or −9201 °C. They aren't temperatures.
    @Test func placeholderReadingsAreIgnored() {
        let groups = ThermalGroups([
            ThermalSensor(name: "Tp01", celsius: 60), ThermalSensor(name: "Tp02", celsius: 0),
            ThermalSensor(name: "PMU tdev4", celsius: -9201.1), ThermalSensor(name: "Ta01", celsius: 0.5),
            ThermalSensor(name: "TPD0", celsius: 47), ThermalSensor(name: "TRD0", celsius: .nan),
        ])

        #expect(groups.average(.performanceCores) == 60)
        #expect(groups.unnamedCount == 1)
    }

    @Test func cpuFallsBackToTheSoCDie() {
        let groups = ThermalGroups([ThermalSensor(name: "PMU tdie1", celsius: 50), ThermalSensor(name: "PMU tdie2", celsius: 52)])

        #expect(groups.cpu == 51)
    }

    @Test(arguments: [(TemperatureUnit.celsius, 58.4, "58°C", "58 °C"), (.fahrenheit, 58, "136°F", "136 °F")])
    func unitsFormat(unit: TemperatureUnit, celsius: Double, compact: String, spaced: String) {
        #expect(unit.compact(celsius) == compact)
        #expect(unit.format(celsius) == spaced)
    }
}
