//
//  YearInfo2.swift
//  SwiftRRule
//
//  Created by Joshua Morris on 1/24/21.
//

import Foundation
import SwiftDate

infix operator %%: MultiplicationPrecedence

public func %%<T: BinaryInteger>(lhs: T, rhs: T) -> T {
    let rem = lhs % rhs // -rhs <= rem <= rhs
    return rem >= 0 ? rem : rem + rhs
}

extension Array where Element == YearWeeknoMask.Patch {
    public func applyAll(to target: inout WeeknoMask) {
        forEach { patch in patch.apply(to: &target)}
    }
}

public struct YearWeekDayMask {
    let
        basis: WeekDayMask,
        starting: Number

    public var computed: WeekDayMask { Array(basis[starting...]) }

    public init(_ details: YearDetails, weekDayMask: WeekDayMask? = nil) {
        self.basis = weekDayMask ?? Constants.weekDayMask
        self.starting = basis.firstIndex(of: details.newYearsWeekDay.rawValue)!
    }
}

public struct YearWeeknoMask {
    public struct Patch {
        let
            at: Number,
            change: [Number]

        public static func builder(terminus: Number, using weekDayMask: WeekDayMask) ->
            (_: Number) -> Self {
            
            { starting in
                var contents: [Number] = []

                for offset in (0..<7) {
                    contents.append(1)
                    if weekDayMask[starting + offset + 1] == terminus {
                        break
                    }
                }

                return Self(at: starting, contents)
            }
        }

        public init(at: Number, _ change: [Number]) {
            self.at = at
            self.change = change
        }

        public func apply(to target: inout WeeknoMask) -> Void {
            target.replaceSubrange((at..<(at + change.count)), with: change)
        }
    }

    public let
        normalByweekno: Multi<Number>,
        normalWkst: Number,
        weekDayMask: WeekDayMask,

        computedWeeks: Number,
        naturalWeekOffset: Number,
        computedWeekOffset: Number,
        length: Number,
        yearLength: Number,

        priorNewYearsWeekDay: Number,
        priorYearLength: Number

    internal var leadingWeekPatch: Patch? {
        guard computedWeekOffset != 0 else {
            return nil
        }

        var
            priorComputedFinalWeek: Number,
            priorComputedWeekOffset: Number = (normalWkst + 7 - priorNewYearsWeekDay) %% 7

        if normalByweekno.contains(-1) {
            priorComputedFinalWeek = -1
        } else {
            let priorLiteralWeekOffset = priorComputedWeekOffset >= 4
                ? priorYearLength + (priorNewYearsWeekDay - normalWkst) %% 7
                : length - computedWeekOffset
            priorComputedFinalWeek = Int(floor(52.0 + Double(priorLiteralWeekOffset %% 7) / 4.0))
        }

        if normalByweekno.contains(priorComputedFinalWeek) {
            let patchBuilder = Patch.builder(terminus: priorComputedWeekOffset, using: weekDayMask)
            return patchBuilder(0)
        } else {
            return nil
        }
    }

    internal var firstWeekPatch: Patch? {
        let patchBuilder = Patch.builder(terminus: normalWkst, using: weekDayMask)

        if normalByweekno.contains(1) {
            // Check week #1 of next year as well
            let basis = computedWeekOffset + computedWeeks * 7

            let at = computedWeekOffset == naturalWeekOffset
                ? basis
                : basis - (7 - naturalWeekOffset)

            return at < yearLength
                ? patchBuilder(at)
                : nil
        } else {
            return nil
        }
    }

    internal var centralWeekPatches: [Patch?] {
        let patchBuilder = Patch.builder(terminus: normalWkst, using: weekDayMask)

        return
            normalByweekno.map { (weekno) -> Patch? in
                let normalizedWeekno = weekno < 0
                    ? weekno + computedWeeks + 1 // really subtracting from end of year
                    : weekno
                var at: Number

                if (1...computedWeeks).contains(normalizedWeekno) {
                    if normalizedWeekno == 1 {
                        at = computedWeekOffset
                    } else {
                        let basis = computedWeekOffset + (normalizedWeekno - 1) * 7
                        at = computedWeekOffset == naturalWeekOffset
                            ? basis
                            : basis - (7 - naturalWeekOffset)
                    }

                    return patchBuilder(at)
                } else {
                    return nil
                }
            }
    }

    public var computed: WeeknoMask {
        var
            mask: WeeknoMask = Array(repeating: 0, count: yearLength + 7),
            patches: [Patch?] = []

        patches.append(firstWeekPatch)
        patches.append(contentsOf: centralWeekPatches)
        patches.append(leadingWeekPatch)

        patches.compactMap { $0 }.applyAll(to: &mask)

        return mask
    }

    public init(
        _ details: YearDetails,
        normalByweekno byweekno: Multi<Number>,
        normalWkst wkst: Number,
        yearWeekDayMask: YearWeekDayMask? = nil
    ) {
        let
            basisYearWeekDayMask = yearWeekDayMask ?? YearWeekDayMask(details),
            newYearsWeekDay = details.newYearsWeekDay.rawValue

        self.normalByweekno = byweekno
        self.normalWkst = wkst
        self.weekDayMask = basisYearWeekDayMask.computed

        self.naturalWeekOffset = (wkst + 7 - newYearsWeekDay) %% 7
        self.yearLength = details.length.rawValue

        if naturalWeekOffset >= 4 {
            let
                length = (newYearsWeekDay - normalWkst) %% 7 + yearLength,
                literalWeeks = Int(floor(Double(length) / 7.0)),
                excessWeekDays = length %% 7

            self.length = length
            self.computedWeekOffset = 0
            self.computedWeeks = Number(floor(Double(literalWeeks) + Double(excessWeekDays) / 4.0))
        } else {
            let
                length = yearLength - naturalWeekOffset,
                literalWeeks = Int(floor(Double(length) / 7.0)),
                excessWeekDays = length %% 7

            self.length = length
            self.computedWeekOffset = naturalWeekOffset
            self.computedWeeks = Number(floor(Double(literalWeeks) + Double(excessWeekDays) / 4.0))
        }

        self.priorNewYearsWeekDay = details.priorNewYearsWeekDay.rawValue
        self.priorYearLength = details.priorLength.rawValue
    }
}

public struct YearMasks {
    var
        month: MonthMask,
        posDay: DayMask,
        negDay: DayMask,
        weekDay: WeekDayMask,
        weekno: WeeknoMask? = nil

    public init(_ details: YearDetails, normalByweekno byweekno: Multi<Number>, normalWkst wkst: Number,
        yearWeekDayMask: YearWeekDayMask? = nil) {
        let basisYearWeekDayMask = yearWeekDayMask ?? YearWeekDayMask(details)

        switch details.length {
        case .normal:
            self.month = Constants.month365Mask
            self.posDay = Constants.posDay365Mask
            self.negDay = Constants.negDay365Mask
        case .leap:
            self.month = Constants.month366Mask
            self.posDay = Constants.posDay366Mask
            self.negDay = Constants.negDay366Mask
        }

        self.weekDay = basisYearWeekDayMask.computed

        if byweekno.isEmpty {
            self.weekno = nil
        } else {
            self.weekno =
                YearWeeknoMask(
                    details,
                    normalByweekno: byweekno,
                    normalWkst: wkst,
                    yearWeekDayMask: basisYearWeekDayMask
                ).computed
        }
    }
}

public enum YearLength: Int {
    case normal = 365
    case leap = 366
}

extension Date {
    public var isLeap: Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

public struct YearDetails {
    public let
        length: YearLength,
        newYears: Date,
        newYearsWeekDay: RRuleWeekDay,
        newYearsOrdinal: Ord,
        monthRange: MonthRange,

        priorLength: YearLength,
        priorNewYears: Date,
        priorNewYearsWeekDay: RRuleWeekDay,

        nextLength: YearLength

    public init(_ year: Number, calendar providedCalendar: Calendar? = nil) {
        var calendar: Calendar

        if providedCalendar == nil {
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(abbreviation: "UTC")!
        } else {
            calendar = providedCalendar!
        }

        let
            eraNewYears = calendar.date(from: DateComponents(calendar: calendar, year: 1))!,
            newYears = calendar.date(from: DateComponents(calendar: calendar, year: year))!,
            priorNewYears = calendar.date(from: DateComponents(calendar: calendar, year: year - 1))!,
            nextNewYears = calendar.date(from: DateComponents(calendar: calendar, year: year + 1))!

        self.length = newYears.isLeap ? .leap : .normal
        self.newYears = newYears
        self.newYearsWeekDay = WeekDay(rawValue: newYears.weekday)!.rruleWeekDay
        self.newYearsOrdinal = calendar.dateComponents([.day], from: eraNewYears, to: newYears).day! - 1
        self.monthRange = newYears.isLeap ? Constants.month365Range : Constants.month366Range

        self.priorLength = priorNewYears.isLeap ? .leap : .normal
        self.priorNewYears = priorNewYears
        self.priorNewYearsWeekDay = WeekDay(rawValue: priorNewYears.weekday)!.rruleWeekDay

        self.nextLength = nextNewYears.isLeap ? .leap : .normal
    }
}

public struct YearInfo {
    public let
        details: YearDetails,
        masks: YearMasks

    public init(_ year: Number, recurrable: Recurrable, calendar: Calendar? = nil) {
        var calendar: Calendar = calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let details = YearDetails(year, calendar: calendar)
        self.details = details
        self.masks = YearMasks(details, normalByweekno: recurrable.byweekno, normalWkst: recurrable.wkst)
    }
}